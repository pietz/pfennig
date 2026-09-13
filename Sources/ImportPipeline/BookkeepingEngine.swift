import Database
import Domain
import Foundation
import Tax
import Validation

/// A draft with everything Swift derives from it: the tax assessment
/// (treatment, self-assessed VAT, tax points) and the deterministic
/// validation result. The editor calls this on every keystroke to show live
/// issues, and the repository stores exactly what it returns.
public struct DerivedTransaction: Sendable {
    /// The input draft with derived values filled in (assessment, asset flags).
    public var draft: TransactionDraft
    public var issues: [ValidationIssueDraft]
    /// Why the treatment was decided this way (spec 16.2 `reasoning`).
    public var reasoning: String?
    /// True when the treatment came from the `TaxTreatmentDecider`, not the user.
    public var isTreatmentAutomatic: Bool

    public var hardIssues: [ValidationIssueDraft] {
        issues.filter(\.isHard)
    }

    public var softIssues: [ValidationIssueDraft] {
        issues.filter { !$0.isHard }
    }

    public var canSave: Bool {
        hardIssues.isEmpty
    }

    public var treatment: TaxTreatment {
        draft.assessment?.treatment ?? .unknown
    }
}

/// The glue between the pure `Tax` and `Validation` modules and the editable
/// draft (spec 22: neither module may reach into the database, so the facts
/// they need are assembled here).
public enum BookkeepingEngine {
    public static func derive(
        _ input: TransactionDraft,
        profile: BusinessProfile,
        categories: [Database.Category] = [],
        hint: ModelTreatmentHint? = nil,
        reverseChargeNote: Bool = false
    ) -> DerivedTransaction {
        var draft = input
        let currency = draft.currency
        let net = draft.net ?? Money.zero(currency)
        let tax = draft.tax ?? Money.zero(currency)
        let gross = draft.gross ?? Money.zero(currency)

        // 1 - treatment: the user's choice wins, otherwise Swift decides (spec 13).
        let counterpartyCountry = draft.counterpartyCountryCode?.uppercased() ?? profile.countryCode.uppercased()
        // Manual entries rarely state a supply type; a freelancer's invoices
        // are services unless the user says otherwise.
        let supplyType = draft.supplyType == .unknown ? .service : draft.supplyType
        let decision = TaxTreatmentDecider.decide(
            TaxTreatmentDecisionInput(
                profile: ProfileFacts(
                    countryCode: profile.countryCode,
                    vatStatus: profile.vatStatus,
                    accountingMethod: profile.vatAccountingMethod
                ),
                direction: draft.direction,
                counterparty: CounterpartyTaxFacts(
                    countryCode: counterpartyCountry,
                    hasVATId: draft.counterpartyVatId?.isEmpty == false
                ),
                supplyType: supplyType,
                document: DocumentTaxFacts(
                    taxShown: tax.minorUnits != 0,
                    reverseChargeNotePresent: reverseChargeNote,
                    rateComponents: draft.components.compactMap(\.rate)
                ),
                modelHint: hint
            )
        )
        let treatment = draft.treatmentOverride ?? decision.treatment
        let reasoning = Self.reasoning(for: decision.treatment, direction: draft.direction)
        let isSmallBusinessExpense = draft.direction == .expense
            && (profile.vatStatus == .smallBusiness || treatment == .smallBusiness)

        // A model parse failure remains blocking while its field is still
        // missing. If a reviewer supplies a valid replacement, the stale
        // import metadata no longer applies.
        let unparseableDateFields = (draft.unparseableDateFields ?? []).filter { field in
            switch field {
            case "invoiceDate": draft.invoiceDate == nil
            case "serviceDate": draft.serviceDate == nil
            case "servicePeriodStart": draft.servicePeriodStart == nil
            case "servicePeriodEnd": draft.servicePeriodEnd == nil
            default: true
            }
        }

        // 2 - tax points (spec 5.1).
        let paymentDates = draft.payments.map(\.paymentDate)
        let points = TaxPointDeriver.derive(
            TaxPointsInput(
                direction: draft.direction,
                treatment: treatment,
                invoiceDate: draft.invoiceDate,
                serviceDate: draft.serviceDate,
                servicePeriodEnd: draft.servicePeriodEnd,
                isAdvancePayment: draft.isAdvancePayment,
                paymentDates: paymentDates
            )
        )

        // 3 - self-assessed VAT for §13b / intra-Community acquisitions (spec 5.4).
        let selfAssessesVAT = draft.direction == .expense
            && (treatment == .reverseCharge || treatment == .intraCommunityAcquisition)
        let base = net.isZero ? gross : net
        let vatDate = points.inputVATDate ?? draft.invoiceDate ?? LocalDate.today()
        let selfAssessed = selfAssessesVAT
            ? try? SelfAssessedVAT.compute(
                taxableBase: base,
                at: vatDate,
                fullyDeductible: !isSmallBusinessExpense
            )
            : nil

        let deductibleInputVAT: Int64? = switch draft.direction {
        case .expense:
            isSmallBusinessExpense ? 0 : (selfAssessed?.deductibleInputVAT.minorUnits ?? tax.minorUnits)
        case .income, .unknown: nil
        }
        draft.assessment = TaxAssessmentDraft(
            treatment: treatment,
            taxCountry: profile.countryCode,
            customerType: draft.counterpartyVatId?.isEmpty == false ? .b2b : .unknown,
            supplyType: supplyType,
            customerVatId: draft.direction == .income ? draft.counterpartyVatId : nil,
            taxableBaseMinor: base.minorUnits,
            vatShownMinor: tax.minorUnits,
            selfAssessedVatMinor: selfAssessed?.selfAssessedVAT.minorUnits,
            deductibleInputVatMinor: deductibleInputVAT,
            outputVatMinor: draft.direction == .income ? tax.minorUnits : nil,
            eurDate: points.eurDate,
            inputVatDate: points.inputVATDate,
            outputVatDate: points.outputVATDate,
            status: draft.treatmentOverride == nil ? .proposed : .manualOverride,
            reasoning: draft.treatmentOverride == nil ? reasoning : nil
        )

        // 4 - asset candidates (spec 5.6).
        let kinds = Dictionary(uniqueKeysWithValues: categories.map { ($0.id, $0.kind) })
        draft.allocations = draft.allocations.map { allocation in
            var allocation = allocation
            if let kind = kinds[allocation.categoryId] {
                allocation.assetFlag = AssetDetection.assetFlagApplies(
                    categoryID: allocation.categoryId,
                    categoryKind: kind,
                    netAmount: Money(minorUnits: allocation.amountMinor, currency: currency)
                )
            }
            return allocation
        }

        // 5 - deterministic validation (spec 14).
        let snapshot = TransactionSnapshot(
            unparseableDateFields: unparseableDateFields,
            invoiceDate: draft.invoiceDate,
            serviceDate: draft.serviceDate,
            servicePeriodStart: draft.servicePeriodStart,
            servicePeriodEnd: draft.servicePeriodEnd,
            paymentDates: paymentDates,
            net: net,
            tax: tax,
            gross: gross,
            taxComponents: draft.components.map {
                TaxComponentSnapshot(
                    rate: $0.rate,
                    net: Money(minorUnits: $0.netMinor, currency: currency),
                    tax: Money(minorUnits: $0.taxMinor, currency: currency),
                    kind: $0.kind
                )
            },
            allocations: draft.allocations.map {
                AllocationSnapshot(
                    categoryID: $0.categoryId,
                    amount: Money(minorUnits: $0.amountMinor, currency: currency),
                    assetFlag: $0.assetFlag
                )
            },
            allocationExpectedTotal: isSmallBusinessExpense ? gross : (net.isZero ? gross : net),
            paymentAllocations: draft.payments.map {
                let amount = Money(minorUnits: $0.amountMinor, currency: $0.currency)
                let allocated = Money(minorUnits: $0.allocated, currency: $0.currency)
                return PaymentAllocationFact(
                    paymentID: $0.id ?? "neu",
                    paymentBookedAmount: amount,
                    allocatedToThisTransaction: allocated,
                    totalAllocatedForPayment: allocated
                )
            },
            totalPaid: paymentDates.isEmpty
                ? nil
                : Money(minorUnits: draft.payments.reduce(0) { $0 + $1.allocated }, currency: currency),
            treatment: treatment,
            direction: draft.direction,
            isCounterpartyDomestic: counterpartyCountry == profile.countryCode.uppercased(),
            isCounterpartyEUMember: TaxTreatmentDecider.euMemberStates.contains(counterpartyCountry),
            customerVATIDPresent: draft.counterpartyVatId?.isEmpty == false,
            isKleinbetrag: Kleinbetrag.appliesTo(gross: gross, treatment: treatment),
            invoiceNumberPresent: draft.invoiceNumber?.isEmpty == false,
            paymentsInTenDayWindow: paymentDates.filter(TenDayRule.isInWindow)
        )
        let result = TransactionValidator.validate(snapshot)

        return DerivedTransaction(
            draft: draft,
            issues: (result.hard + result.soft).map(Self.issueDraft),
            reasoning: reasoning,
            isTreatmentAutomatic: draft.treatmentOverride == nil
        )
    }

    /// The decider reasons in English (it is a pure rule engine); the UI and
    /// `tax_assessments.reasoning` are German.
    private static func reasoning(for treatment: TaxTreatment, direction: Direction) -> String {
        switch treatment {
        case .domesticVAT:
            "Inländische Firma mit ausgewiesener Umsatzsteuer (§ 13 UStG)."
        case .reverseCharge where direction == .income:
            "EU-B2B-Dienstleistung ohne Umsatzsteuer - Reverse Charge (§ 3a UStG)."
        case .reverseCharge:
            "Ausländische Firma, Dienstleistung ohne Umsatzsteuer - Steuerschuldnerschaft des Leistungsempfängers (§ 13b UStG)."
        case .intraCommunityAcquisition:
            "EU-Firma, Warenlieferung ohne Umsatzsteuer - innergemeinschaftlicher Erwerb (§ 1a UStG)."
        case .export:
            "Einnahme aus einem Drittland ohne Umsatzsteuer - Ausfuhrlieferung (§ 4 Nr. 1 UStG)."
        case .nonTaxable:
            "Kein Umsatzsteuerausweis, nicht steuerbarer Vorgang."
        case .exempt:
            "Kein Umsatzsteuerausweis, steuerfreier Umsatz (§ 4 UStG)."
        case .smallBusiness:
            "Keine Umsatzsteuer aufgrund der Kleinunternehmerregelung (§ 19 UStG)."
        default:
            "Die Angaben passen zu keiner bekannten Regel - bitte steuerliche Behandlung manuell wählen."
        }
    }

    private static func issueDraft(_ issue: ValidationIssue) -> ValidationIssueDraft {
        ValidationIssueDraft(
            code: issue.code.rawValue,
            severity: issue.severity,
            messageKey: issue.messageKey,
            message: issue.code.germanMessage,
            fieldName: issue.fieldName,
            params: issue.params
        )
    }
}
