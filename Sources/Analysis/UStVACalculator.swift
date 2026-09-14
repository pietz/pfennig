import Database
import Domain
import Foundation
import GRDB
import Tax

/// Deterministic UStVA preparation for one Voranmeldungszeitraum
/// (`docs/specs/ustva-preparation.md`).
///
/// Everything is read from the stored bookkeeping records: the current
/// `tax_assessments` row is the truth about a transaction's treatment and its
/// self-assessed amounts, `tax_components` is the truth about its rate split.
/// Nothing is re-derived here, so a manual override the user made in the
/// inspector flows straight into the form values. Start-page totals are never
/// reused; every figure is recomputed from payments and components.
///
/// Dates, per Ist-Versteuerung (spec "Fachliche Regeln"):
///
/// - **Income** counts per payment, in the period of the payment date. Partial
///   payments contribute proportionally through ``AllocationSplitter``.
/// - **Input VAT on expenses** counts per payment at `max(Rechnungsdatum,
///   Zahlungsdatum)` - conservative against §15 UStG, and it needs no
///   "invoice on hand" field.
/// - **§13b and intra-Community acquisitions** count in full with the invoice
///   date - failing that, the start of the service period - regardless of
///   payment. Without either date the transaction becomes an exception
///   instead of a line.
public enum UStVACalculator {
    /// Prepares one period. `db` is a GRDB connection inside a read or write.
    public static func prepare(
        period: UStVAPeriod,
        profile: BusinessProfile,
        db: Database
    ) throws -> UStVAReturn {
        var builder = Builder(period: period, profile: profile)
        let rows = try transactionRows(db, period: period, profileID: profile.id)
        let ids = rows.map(\.id)
        let components = try componentRows(db, transactionIDs: ids)
        let allocations = try allocationRows(db, transactionIDs: ids)

        for row in rows {
            builder.add(row, components: components[row.id] ?? [], allocations: allocations[row.id] ?? [])
        }
        for payment in try unallocatedPaymentRows(db, period: period) {
            builder.addUnallocatedPayment(payment)
        }
        return builder.result()
    }

    /// Convenience for callers that hold the archive database.
    public static func prepare(
        period: UStVAPeriod,
        profile: BusinessProfile,
        database: AppDatabase
    ) throws -> UStVAReturn {
        try database.reader.read { try prepare(period: period, profile: profile, db: $0) }
    }

    public static func observation(period: UStVAPeriod, profile: BusinessProfile)
        -> ValueObservation<ValueReducers.Fetch<UStVAReturn>>
    {
        ValueObservation.tracking { try prepare(period: period, profile: profile, db: $0) }
    }

    // MARK: - Rows

    struct TransactionRow: FetchableRecord, Decodable {
        var id: String
        var direction: Direction
        var title: String?
        var invoiceDate: LocalDate?
        var servicePeriodStart: LocalDate?
        var bookedCurrency: String
        var bookedNetMinor: Int64?
        var bookedTaxMinor: Int64?
        var bookedGrossMinor: Int64?
        var treatment: TaxTreatment?
        var taxableBaseMinor: Int64?
        var selfAssessedVatMinor: Int64?
        var counterpartyName: String?
        var counterpartyCountry: String?
        var needsDocument: Bool

        static var databaseColumnDecodingStrategy: DatabaseColumnDecodingStrategy {
            .convertFromSnakeCase
        }
    }

    struct AllocationRow: FetchableRecord, Decodable {
        var id: String
        var transactionId: String
        var paymentId: String
        /// Signed by the payment's direction: positive when the money moved
        /// the way the transaction expects, negative for a refund. A credit
        /// note is settled by a payment in the opposite direction and so
        /// arrives here with the negative sign its own amounts carry.
        var allocatedMinor: Int64
        var currency: String
        var paymentDate: LocalDate

        static var databaseColumnDecodingStrategy: DatabaseColumnDecodingStrategy {
            .convertFromSnakeCase
        }
    }

    struct ComponentRow: FetchableRecord, Decodable {
        var transactionId: String
        var rate: String?
        var netMinor: Int64
        var taxMinor: Int64

        static var databaseColumnDecodingStrategy: DatabaseColumnDecodingStrategy {
            .convertFromSnakeCase
        }
    }

    struct OrphanPaymentRow: FetchableRecord, Decodable {
        var id: String
        var paymentDate: LocalDate
        var counterpartyNameRaw: String?
        var reference: String?

        static var databaseColumnDecodingStrategy: DatabaseColumnDecodingStrategy {
            .convertFromSnakeCase
        }
    }

    /// Transactions that can touch the period: their invoice date is inside
    /// it, one of their payments is, or - for §13b and intra-Community
    /// acquisitions without an invoice date - their service period starts in
    /// it. That
    /// covers every dating rule above, because `max(Rechnung, Zahlung)` can
    /// only land in the period when one of the two does.
    private static func transactionRows(
        _ db: Database,
        period: UStVAPeriod,
        profileID: String
    ) throws -> [TransactionRow] {
        try TransactionRow.fetchAll(
            db,
            sql: """
            SELECT t.id, t.direction, t.title, t.invoice_date, t.service_period_start,
                   t.booked_currency, t.booked_net_minor, t.booked_tax_minor, t.booked_gross_minor,
                   ta.treatment AS treatment,
                   ta.taxable_base_minor AS taxable_base_minor,
                   ta.self_assessed_vat_minor AS self_assessed_vat_minor,
                   c.display_name AS counterparty_name,
                   c.country_code AS counterparty_country,
                   CASE WHEN \(TransactionQueryRules.missingDocumentsPredicate(for: "t"))
                        THEN 1 ELSE 0 END AS needs_document
              FROM transactions t
              LEFT JOIN tax_assessments ta ON ta.transaction_id = t.id
              LEFT JOIN counterparties c ON c.id = t.counterparty_id
             WHERE t.business_profile_id = :profile
               AND \(TransactionQueryRules.recordedVisibilityPredicate(for: "t"))
               AND (
                    (t.invoice_date >= :start AND t.invoice_date <= :end)
                 OR (t.invoice_date IS NULL AND t.service_period_start >= :start
                     AND t.service_period_start <= :end)
                 OR EXISTS (
                        SELECT 1 FROM payment_allocations pa
                          JOIN payments p ON p.id = pa.payment_id
                         WHERE pa.transaction_id = t.id
                           AND p.payment_date >= :start AND p.payment_date <= :end
                    )
               )
             ORDER BY t.invoice_date, t.created_at, t.id
            """,
            arguments: [
                "profile": profileID,
                "start": period.periodStart.description,
                "end": period.periodEnd.description
            ]
        )
    }

    private static func componentRows(_ db: Database, transactionIDs: [String]) throws -> [String: [ComponentRow]] {
        guard !transactionIDs.isEmpty else { return [:] }
        let rows = try ComponentRow.fetchAll(
            db,
            sql: """
            SELECT transaction_id, rate, net_minor, tax_minor
              FROM tax_components
             WHERE transaction_id IN \(placeholders(transactionIDs.count))
             ORDER BY transaction_id, sort_order, id
            """,
            arguments: StatementArguments(transactionIDs)
        )
        return Dictionary(grouping: rows, by: \.transactionId)
    }

    /// Every allocation of the candidate transactions, not only those inside
    /// the period: the proportional split is cumulative, so a later period's
    /// share depends on what earlier payments already consumed.
    private static func allocationRows(_ db: Database, transactionIDs: [String]) throws -> [String: [AllocationRow]] {
        guard !transactionIDs.isEmpty else { return [:] }
        let rows = try AllocationRow.fetchAll(
            db,
            sql: """
            SELECT pa.id, pa.transaction_id, pa.payment_id, pa.currency,
                   \(TransactionQueryRules.signedAllocationExpression(
                       allocation: "pa",
                       payment: "p",
                       transaction: "t"
                   )) AS allocated_minor,
                   p.payment_date AS payment_date
              FROM payment_allocations pa
              JOIN payments p ON p.id = pa.payment_id
              JOIN transactions t ON t.id = pa.transaction_id
             WHERE pa.transaction_id IN \(placeholders(transactionIDs.count))
             ORDER BY pa.transaction_id, p.payment_date, pa.payment_id, pa.id
            """,
            arguments: StatementArguments(transactionIDs)
        )
        return Dictionary(grouping: rows, by: \.transactionId)
    }

    /// "Zahlung ohne Vorgang": money moved in the period but was never
    /// assigned to a transaction. A foreign key makes the opposite case
    /// impossible, so this is the only orphan the calculator can see.
    private static func unallocatedPaymentRows(_ db: Database, period: UStVAPeriod) throws -> [OrphanPaymentRow] {
        try OrphanPaymentRow.fetchAll(
            db,
            sql: """
            SELECT p.id, p.payment_date, p.counterparty_name_raw, p.reference
              FROM payments p
             WHERE p.payment_date >= :start AND p.payment_date <= :end
               AND NOT EXISTS (SELECT 1 FROM payment_allocations pa WHERE pa.payment_id = p.id)
             ORDER BY p.payment_date, p.id
            """,
            arguments: ["start": period.periodStart.description, "end": period.periodEnd.description]
        )
    }

    private static func placeholders(_ count: Int) -> String {
        "(" + Array(repeating: "?", count: count).joined(separator: ", ") + ")"
    }
}

// MARK: - Builder

private extension UStVACalculator {
    struct LineBuilder {
        var amountMinor: Int64 = 0
        var contributions: [UStVAReturn.Contribution] = []
    }

    struct Builder {
        let period: UStVAPeriod
        let profile: BusinessProfile
        var isSmallBusiness: Bool {
            profile.vatStatus == .smallBusiness
        }

        private var lines: [Int: LineBuilder] = [:]
        private var exceptions: [UStVAReturn.Exception] = []

        init(period: UStVAPeriod, profile: BusinessProfile) {
            self.period = period
            self.profile = profile
        }

        // MARK: One transaction

        mutating func add(
            _ row: TransactionRow,
            components rawComponents: [ComponentRow],
            allocations: [AllocationRow]
        ) {
            guard row.bookedCurrency == "EUR", let gross = row.bookedGrossMinor else {
                note(.missingEURAmount, row, "Kein EUR-Bruttobetrag - der Vorgang kann nicht gemeldet werden.")
                return
            }
            guard let treatment = row.treatment, treatment != .unknown else {
                note(.unknownTreatment, row, "Steuerliche Behandlung unbekannt - bitte im Inspector festlegen.")
                return
            }
            if let foreign = allocations.first(where: { $0.currency != "EUR" }) {
                note(.missingEURAmount, row, "Zahlung in \(foreign.currency) ohne EUR-Betrag.")
                return
            }

            var components = Self.components(rawComponents, row: row, gross: gross)
            var mismatch = false
            if AllocationSplitter.grossMinor(of: components) != gross {
                mismatch = true
                components = [Self.synthesizedComponent(row: row, gross: gross)]
            }

            let slices = AllocationSplitter.split(
                components: components,
                allocations: allocations.map(\.allocatedMinor)
            )

            var dates: [LocalDate] = []
            switch row.direction {
            case .income:
                dates = addIncome(row, treatment: treatment, allocations: allocations, slices: slices)
            case .expense:
                dates = addExpense(
                    row,
                    treatment: treatment,
                    gross: gross,
                    components: components,
                    allocations: allocations,
                    slices: slices
                )
            case .unknown:
                note(.other, row, "Richtung des Vorgangs unbekannt - weder Einnahme noch Ausgabe.")
                return
            }

            guard !dates.isEmpty else { return }
            if mismatch {
                note(
                    .componentMismatch,
                    row,
                    "Die Steuerkomponenten passen nicht zur Bruttosumme; "
                        + "gerechnet wird mit den Gesamtbeträgen des Vorgangs."
                )
            }
            if row.direction == .expense, row.needsDocument {
                note(.expenseWithoutDocument, row, "Ausgabe ohne Beleg im Zeitraum.")
            }
        }

        // MARK: Income

        private mutating func addIncome(
            _ row: TransactionRow,
            treatment: TaxTreatment,
            allocations: [AllocationRow],
            slices: [[TaxSlice]]
        ) -> [LocalDate] {
            var dates: [LocalDate] = []
            for (index, allocation) in allocations.enumerated() where period.contains(allocation.paymentDate) {
                dates.append(allocation.paymentDate)
                for slice in slices[index] {
                    guard let kennzahl = UStVA_2026.incomeKennzahl(treatment: treatment, rate: slice.rate) else {
                        if slice.grossMinor != 0 {
                            note(
                                .other,
                                row,
                                "Für \(treatment.rawValue) mit Steuersatz "
                                    + "\(slice.rate ?? "ohne Angabe") gibt es keine Kennzahl im Formular 2026."
                            )
                        }
                        continue
                    }
                    // A Kleinunternehmer files a UStVA only because of §13b
                    // (§18 Abs. 4a UStG) and reports only that; the §19 income
                    // itself does not go into Kz 48.
                    if isSmallBusiness, kennzahl == 48 {
                        continue
                    }
                    credit(
                        kennzahl,
                        slice.baseMinor,
                        row: row,
                        paymentID: allocation.paymentId,
                        date: allocation.paymentDate
                    )
                }
            }
            return dates
        }

        // MARK: Expense

        private mutating func addExpense(
            _ row: TransactionRow,
            treatment: TaxTreatment,
            gross: Int64,
            components: [AllocationSplitter.Component],
            allocations: [AllocationRow],
            slices: [[TaxSlice]]
        ) -> [LocalDate] {
            switch treatment {
            case .domesticVAT, .importVAT:
                // Vorsteuer at max(Rechnungsdatum, Zahlungsdatum), per payment.
                let kennzahl = treatment == .importVAT ? 62 : 66
                var dates: [LocalDate] = []
                for (index, allocation) in allocations.enumerated() {
                    let date = max(row.invoiceDate ?? allocation.paymentDate, allocation.paymentDate)
                    guard period.contains(date) else { continue }
                    dates.append(date)
                    guard !isSmallBusiness else { continue } // §19: keine Vorsteuer
                    let tax = slices[index].reduce(Int64(0)) { $0 + $1.taxMinor }
                    credit(kennzahl, tax, row: row, paymentID: allocation.paymentId, date: date)
                }
                return dates

            case .reverseCharge:
                guard let date = row.invoiceDate ?? row.servicePeriodStart else {
                    note(.other, row, "Rechnungsdatum fehlt")
                    return []
                }
                guard period.contains(date) else { return [] }
                let base = row.taxableBaseMinor ?? row.bookedNetMinor ?? gross
                let tax = row.selfAssessedVatMinor ?? Self.standardVAT(base: base, at: date)
                let route = UStVA_2026.reverseChargeExpense(supplierCountry: row.counterpartyCountry)
                credit(route.base, base, row: row, paymentID: nil, date: date)
                credit(route.tax, tax, row: row, paymentID: nil, date: date)
                if !isSmallBusiness {
                    credit(67, tax, row: row, paymentID: nil, date: date)
                }
                noteBaseWithoutTax(row, base: base, tax: tax)
                if UStVA_2026.reverseChargeCountryIsUnclear(supplierCountry: row.counterpartyCountry) {
                    note(
                        .reverseChargeUnclear,
                        row,
                        "Sitzland des Leistenden unbekannt - gemeldet als "
                            + "Kz \(route.base)/\(route.tax); bitte Leistungsort und Anbieterland prüfen."
                    )
                }
                return [date]

            case .intraCommunityAcquisition:
                guard let date = row.invoiceDate ?? row.servicePeriodStart else {
                    note(.other, row, "Rechnungsdatum fehlt")
                    return []
                }
                guard period.contains(date) else { return [] }
                let base = row.taxableBaseMinor ?? row.bookedNetMinor ?? gross
                let rate = components.compactMap(\.rate).first { $0 == "7" || $0 == "19" }
                let kennzahl = UStVA_2026.intraCommunityAcquisitionBase(rate: rate)
                credit(kennzahl, base, row: row, paymentID: nil, date: date)
                // The form derives the acquisition tax from the whole-euro
                // base, so the matching Vorsteuer is taken the same way and
                // the two cancel exactly.
                let tax = UStVA_2026.derivedTaxMinor(kennzahl: kennzahl, baseMinor: base)
                if !isSmallBusiness {
                    credit(61, tax, row: row, paymentID: nil, date: date)
                }
                noteBaseWithoutTax(row, base: base, tax: tax)
                return [date]

            case .smallBusiness, .exempt, .nonTaxable:
                // Supplier charged no deductible VAT; nothing to report.
                return allocations.map(\.paymentDate).filter(period.contains)

            case .export, .intraCommunitySupply:
                let dates = allocations.map(\.paymentDate).filter(period.contains)
                if !dates.isEmpty {
                    note(
                        .other,
                        row,
                        "Die Behandlung \(treatment.rawValue) ist auf der Ausgabenseite "
                            + "nicht vorgesehen - bitte im Inspector prüfen."
                    )
                }
                return dates

            case .unknown:
                return []
            }
        }

        // MARK: Payments without a transaction

        mutating func addUnallocatedPayment(_ payment: OrphanPaymentRow) {
            let name = payment.counterpartyNameRaw ?? payment.reference ?? "unbekannt"
            exceptions.append(
                UStVAReturn.Exception(
                    kind: .paymentWithoutTransaction,
                    transactionID: nil,
                    paymentID: payment.id,
                    message: "Zahlung vom \(payment.paymentDate) (\(name)) ist keinem Vorgang zugeordnet."
                )
            )
        }

        // MARK: Result

        func result() -> UStVAReturn {
            let ordered = lines.keys.sorted {
                (UStVA_2026.formLine($0), $0) < (UStVA_2026.formLine($1), $1)
            }
            let formLines: [UStVAReturn.Line] = ordered.map { kennzahl in
                let builder = lines[kennzahl] ?? LineBuilder()
                return UStVAReturn.Line(
                    kennzahl: kennzahl,
                    title: UStVA_2026.title(kennzahl),
                    isBase: UStVA_2026.isBase(kennzahl),
                    amountMinor: builder.amountMinor,
                    isVerified: UStVA_2026.isVerified(kennzahl),
                    contributions: builder.contributions.sorted {
                        ($0.date.description, $0.transactionID, $0.paymentID ?? "")
                            < ($1.date.description, $1.transactionID, $1.paymentID ?? "")
                    }
                )
            }
            return UStVAReturn(
                period: period,
                formYear: period.year,
                taxNumber: profile.taxNumber,
                isSmallBusiness: isSmallBusiness,
                lines: formLines,
                payableMinor: payable(),
                exceptions: exceptions.sorted {
                    ($0.kind.rawValue, $0.id) < ($1.kind.rawValue, $1.id)
                }
            )
        }

        /// Kz 83. Output VAT is taken the way ELSTER takes it: bases without a
        /// Steuer column (Kz 81, 86, 89, 93) are cut to whole euros first and
        /// multiplied by their statutory percent, so the Zahllast Pfennig
        /// shows is the one the portal computes from the same values.
        private func payable() -> Int64 {
            var total: Int64 = 0
            for (kennzahl, builder) in lines {
                if UStVA_2026.derivedTaxRatePercent[kennzahl] != nil {
                    total += UStVA_2026.derivedTaxMinor(kennzahl: kennzahl, baseMinor: builder.amountMinor)
                } else if UStVA_2026.outputTaxKennzahlen.contains(kennzahl) {
                    total += builder.amountMinor
                } else if UStVA_2026.inputVATKennzahlen.contains(kennzahl) {
                    total -= builder.amountMinor
                }
            }
            return total
        }

        // MARK: Helpers

        private mutating func credit(
            _ kennzahl: Int,
            _ amountMinor: Int64,
            row: TransactionRow,
            paymentID: String?,
            date: LocalDate
        ) {
            guard amountMinor != 0 else { return }
            var builder = lines[kennzahl] ?? LineBuilder()
            builder.amountMinor += amountMinor
            builder.contributions.append(
                UStVAReturn.Contribution(
                    kennzahl: kennzahl,
                    transactionID: row.id,
                    paymentID: paymentID,
                    date: date,
                    counterpartyName: row.counterpartyName,
                    description: row.title ?? row.counterpartyName ?? "Vorgang",
                    amountMinor: amountMinor
                )
            )
            lines[kennzahl] = builder
        }

        /// A §13b service or an intra-Community acquisition with a base but no
        /// tax would report the Bemessungsgrundlage while its Steuer line is
        /// dropped as a zero amount - the one shape of return that looks
        /// complete and is not. Say so instead.
        private mutating func noteBaseWithoutTax(_ row: TransactionRow, base: Int64, tax: Int64) {
            guard base != 0, tax == 0 else { return }
            note(
                .other,
                row,
                "Bemessungsgrundlage ohne Steuerbetrag - die geschuldete Steuer fehlt "
                    + "und wurde nicht gemeldet; bitte im Inspector prüfen."
            )
        }

        private mutating func note(_ kind: UStVAReturn.Exception.Kind, _ row: TransactionRow, _ message: String) {
            exceptions.append(
                UStVAReturn.Exception(kind: kind, transactionID: row.id, paymentID: nil, message: message)
            )
        }

        // MARK: Components

        static func components(
            _ rows: [ComponentRow],
            row: TransactionRow,
            gross: Int64
        ) -> [AllocationSplitter.Component] {
            guard !rows.isEmpty else { return [synthesizedComponent(row: row, gross: gross)] }
            return rows.map {
                AllocationSplitter.Component(
                    rate: AllocationSplitter.normalizedRate($0.rate),
                    netMinor: $0.netMinor,
                    taxMinor: $0.taxMinor
                )
            }
        }

        /// A transaction without stored components (or with components that do
        /// not add up) is split as a single bucket taken from its own totals,
        /// which always sum to the gross amount exactly.
        static func synthesizedComponent(row: TransactionRow, gross: Int64) -> AllocationSplitter.Component {
            let net = row.bookedNetMinor ?? (gross - (row.bookedTaxMinor ?? 0))
            let tax = gross - net
            return AllocationSplitter.Component(
                rate: inferredRate(net: net, tax: tax),
                netMinor: net,
                taxMinor: tax
            )
        }

        /// Recovers the rate of a bucket from its own net and tax, within one
        /// cent. Returns `nil` when neither statutory rate fits, so the caller
        /// reports an exception instead of guessing a Kennzahl.
        static func inferredRate(net: Int64, tax: Int64) -> String? {
            if tax == 0 {
                return "0"
            }
            for percent in [Int64(19), 7] where abs(tax * 100 - net * percent) <= 100 {
                return String(percent)
            }
            return nil
        }

        static func standardVAT(base: Int64, at date: LocalDate) -> Int64 {
            let money = Money(minorUnits: base, currency: .eur)
            let result = try? SelfAssessedVAT.compute(taxableBase: money, at: date)
            return result?.selfAssessedVAT.minorUnits ?? 0
        }
    }
}
