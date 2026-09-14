import Database
import Domain
import Foundation
import GRDB
import Tax

/// The UStVA task list behind the "Steuern" section on Start and the data the
/// task window needs beyond the calculated return
/// (`docs/specs/ustva-preparation.md`, "Aufgabe auf Start und Aufgabenfenster").
///
/// Nothing here calculates tax: every figure comes from
/// ``UStVACalculator/prepare(period:profile:db:)``. This type only decides
/// *which* periods are worth showing, when they are due, and whether the user
/// already filed them.
public enum UStVATasks {
    /// Whether the profile files regular Voranmeldungen at all.
    public enum Mode: Sendable, Equatable {
        /// Monthly or quarterly Voranmeldungen; every period is a task.
        case regular
        /// Kleinunternehmer, or "keine regelmäßigen Voranmeldungen": a period
        /// becomes a task only when §13b or an intra-Community acquisition
        /// creates a filing duty of its own (§18 Abs. 4a UStG).
        case selfAssessedOnly
    }

    /// Kennzahlen that create a filing duty without regular Voranmeldungen:
    /// §13b services (Kz 46/47, 84/85) and intra-Community acquisitions
    /// (Kz 89/93).
    public static let selfAssessedKennzahlen: Set<Int> = [46, 47, 84, 85, 89, 93]

    /// One row of the "Steuern" section.
    public struct Summary: Sendable, Equatable, Identifiable {
        public var id: String {
            UStVATasks.submissionKey(period)
        }

        public let period: UStVAPeriod
        /// 10th of the month after the period, plus one month with Dauerfristverlängerung.
        public let dueDate: LocalDate
        /// Kz 83: positive = Zahllast, negative = Erstattung.
        public let payableMinor: Int64
        public let exceptionCount: Int
        /// The period reports at least one Kennzahl.
        public let hasValues: Bool
        /// The whole period lies before the first date the archive knows,
        /// so Pfennig was not keeping these books yet.
        public let precedesArchive: Bool
        /// True when the period carries §13b or intra-Community amounts.
        public let hasSelfAssessedLines: Bool
        /// The period whose deadline comes next; shown even when it is filed.
        public let isCurrent: Bool
        public let submittedAt: String?
        /// The period was marked submitted and its values moved afterwards.
        public let changedSinceSubmission: Bool

        public var isSubmitted: Bool {
            submittedAt != nil
        }

        public var isDraft: Bool {
            exceptionCount > 0
        }

        public init(
            period: UStVAPeriod,
            dueDate: LocalDate,
            payableMinor: Int64,
            exceptionCount: Int,
            hasValues: Bool,
            precedesArchive: Bool,
            hasSelfAssessedLines: Bool,
            isCurrent: Bool,
            submittedAt: String?,
            changedSinceSubmission: Bool
        ) {
            self.period = period
            self.dueDate = dueDate
            self.payableMinor = payableMinor
            self.exceptionCount = exceptionCount
            self.hasValues = hasValues
            self.precedesArchive = precedesArchive
            self.hasSelfAssessedLines = hasSelfAssessedLines
            self.isCurrent = isCurrent
            self.submittedAt = submittedAt
            self.changedSinceSubmission = changedSinceSubmission
        }
    }

    // MARK: - Periods

    public static func mode(for profile: BusinessProfile) -> Mode {
        guard profile.vatStatus == .taxable, profile.ustvaPeriod != .yearly else { return .selfAssessedOnly }
        return .regular
    }

    /// Monthly only when the profile says so; every other case is reported per
    /// quarter, which is also the fallback rhythm for a §13b-only filing.
    public static func periodKind(for profile: BusinessProfile) -> UStVAPeriod.Kind {
        profile.ustvaPeriod == .monthly ? .monthly : .quarterly
    }

    public static func period(containing date: LocalDate, kind: UStVAPeriod.Kind) -> UStVAPeriod {
        switch kind {
        case .monthly: UStVAPeriod(year: date.year, month: date.month)
        case .quarterly: UStVAPeriod(year: date.year, quarter: (date.month - 1) / 3 + 1)
        }
    }

    public static func previous(_ period: UStVAPeriod) -> UStVAPeriod {
        switch period.kind {
        case .monthly:
            period.index == 1
                ? UStVAPeriod(year: period.year - 1, month: 12)
                : UStVAPeriod(year: period.year, month: period.index - 1)
        case .quarterly:
            period.index == 1
                ? UStVAPeriod(year: period.year - 1, quarter: 4)
                : UStVAPeriod(year: period.year, quarter: period.index - 1)
        }
    }

    /// Periods the Start section may show, oldest first.
    ///
    /// With regular Voranmeldungen that is the current period plus everything
    /// back to January of the previous year, so a forgotten filing stays
    /// visible. Without them only the current and the previous period are
    /// considered: the section exists solely to catch a §13b case, and
    /// preparing two periods keeps that check cheap.
    public static func candidatePeriods(profile: BusinessProfile, today: LocalDate) -> [UStVAPeriod] {
        let kind = periodKind(for: profile)
        let current = period(containing: today, kind: kind)
        guard mode(for: profile) == .regular else {
            return [previous(current), current]
        }
        var periods = [current]
        var cursor = current
        while cursor.year >= today.year - 1 {
            cursor = previous(cursor)
            guard cursor.year >= today.year - 1 else { break }
            periods.append(cursor)
        }
        return periods.reversed()
    }

    // MARK: - Summaries

    /// Prepares every candidate period and pairs it with its filing state.
    /// Newest period first.
    public static func summaries(
        _ db: Database,
        profile: BusinessProfile,
        today: LocalDate = .today()
    ) throws -> [Summary] {
        let dauerfristverlaengerung = try dauerfristverlaengerung(db)
        let firstRecordedDate = try firstRecordedDate(db)
        let periods = candidatePeriods(profile: profile, today: today)
        let dueDates = periods.map { $0.dueDate(dauerfristverlaengerung: dauerfristverlaengerung) }
        let currentIndex = dueDates.firstIndex { $0 >= today } ?? periods.indices.last
        let submitted = try submittedRecords(db, profileID: profile.id)

        var summaries: [Summary] = []
        for (index, period) in periods.enumerated() {
            let result = try UStVACalculator.prepare(period: period, profile: profile, db: db)
            let record = submitted[submissionKey(period)]
            summaries.append(
                Summary(
                    period: period,
                    dueDate: dueDates[index],
                    payableMinor: result.payableMinor,
                    exceptionCount: result.exceptions.count,
                    hasValues: !result.lines.isEmpty,
                    precedesArchive: firstRecordedDate.map { period.periodEnd < $0 } ?? true,
                    hasSelfAssessedLines: hasSelfAssessedLines(result),
                    isCurrent: index == currentIndex,
                    submittedAt: record?.submittedAt,
                    changedSinceSubmission: record.map {
                        $0.contentHash != SubmittedReturnRepository.contentHash(of: result)
                    } ?? false
                )
            )
        }
        return summaries.reversed()
    }

    /// The rows Start actually shows: the period that is due next, every
    /// earlier period with something to report that is not marked submitted,
    /// and every submitted period whose values moved since.
    ///
    /// An earlier period stays off Start only when it is empty *and* lies
    /// before the first date in the archive: there Pfennig was not keeping the
    /// books yet, and a row of empty quarters marked "überfällig" would drown
    /// the period that matters. An empty period after that first date is a
    /// real task - a regular filer owes a Nullmeldung - and is listed. The
    /// task window reaches every period through its picker. Without regular
    /// Voranmeldungen a row needs §13b or intra-Community amounts to appear at
    /// all.
    public static func startRows(_ summaries: [Summary], mode: Mode) -> [Summary] {
        summaries.filter { summary in
            let isOpen = summary.isCurrent || !summary.isSubmitted || summary.changedSinceSubmission
            let isEmpty = !summary.hasValues && summary.exceptionCount == 0
            let hasWork = summary.isCurrent || !(isEmpty && summary.precedesArchive)
            switch mode {
            case .regular: return isOpen && hasWork
            case .selfAssessedOnly: return isOpen && summary.hasSelfAssessedLines
            }
        }
    }

    /// Live "Steuern" section for Start. The deadline setting is read inside
    /// the observation, so turning Dauerfristverlängerung on moves the dates
    /// without a reload.
    public static func startObservation(
        profile: BusinessProfile,
        today: LocalDate = .today()
    ) -> ValueObservation<ValueReducers.Fetch<[Summary]>> {
        let mode = mode(for: profile)
        return ValueObservation.tracking { db in
            try startRows(summaries(db, profile: profile, today: today), mode: mode)
        }
    }

    public static func hasSelfAssessedLines(_ result: UStVAReturn) -> Bool {
        result.lines.contains { selfAssessedKennzahlen.contains($0.kennzahl) && $0.amountMinor != 0 }
    }

    // MARK: - Task window

    /// The transaction behind an exception, so the task window can show who it
    /// is about and how much it is worth without re-reading the ledger view.
    public struct ExceptionSubject: Sendable, Equatable, FetchableRecord, Decodable {
        public static var databaseColumnDecodingStrategy: DatabaseColumnDecodingStrategy {
            .convertFromSnakeCase
        }

        public var id: String
        public var direction: Direction
        public var title: String?
        public var counterpartyName: String?
        public var bookedGrossMinor: Int64?
        public var bookedCurrency: String

        public var displayName: String {
            counterpartyName ?? title ?? "Ohne Bezeichnung"
        }

        /// Signed by direction, like the ledger shows it.
        public var amount: Money? {
            guard let bookedGrossMinor else { return nil }
            let signed = direction == .expense ? -bookedGrossMinor : bookedGrossMinor
            return Money(minorUnits: signed, currency: CurrencyCode(bookedCurrency))
        }
    }

    /// Everything the task window displays for one period.
    public struct TaskDetail: Sendable, Equatable {
        public let result: UStVAReturn
        /// Keyed by transaction id.
        public let subjects: [String: ExceptionSubject]
        /// 10th of the month after the period, plus one month with
        /// Dauerfristverlängerung.
        public let dueDate: LocalDate
        public let submittedAt: String?
        public let changedSinceSubmission: Bool

        public var isSubmitted: Bool {
            submittedAt != nil
        }

        public init(
            result: UStVAReturn,
            subjects: [String: ExceptionSubject],
            dueDate: LocalDate,
            submittedAt: String?,
            changedSinceSubmission: Bool
        ) {
            self.result = result
            self.subjects = subjects
            self.dueDate = dueDate
            self.submittedAt = submittedAt
            self.changedSinceSubmission = changedSinceSubmission
        }
    }

    public static func detail(
        _ db: Database,
        period: UStVAPeriod,
        profile: BusinessProfile
    ) throws -> TaskDetail {
        let result = try UStVACalculator.prepare(period: period, profile: profile, db: db)
        let ids = Array(Set(result.exceptions.compactMap(\.transactionID)))
        let record = try submittedRecords(db, profileID: profile.id)[submissionKey(period)]
        return try TaskDetail(
            result: result,
            subjects: exceptionSubjects(db, transactionIDs: ids),
            dueDate: period.dueDate(dauerfristverlaengerung: dauerfristverlaengerung(db)),
            submittedAt: record?.submittedAt,
            changedSinceSubmission: record.map {
                $0.contentHash != SubmittedReturnRepository.contentHash(of: result)
            } ?? false
        )
    }

    /// Live task window: the values follow the ledger while it is open.
    public static func detailObservation(
        period: UStVAPeriod,
        profile: BusinessProfile
    ) -> ValueObservation<ValueReducers.Fetch<TaskDetail>> {
        ValueObservation.tracking { try detail($0, period: period, profile: profile) }
    }

    public static func exceptionSubjects(
        _ db: Database,
        transactionIDs: [String]
    ) throws -> [String: ExceptionSubject] {
        guard !transactionIDs.isEmpty else { return [:] }
        let placeholders = "(" + Array(repeating: "?", count: transactionIDs.count).joined(separator: ", ") + ")"
        let rows = try ExceptionSubject.fetchAll(
            db,
            sql: """
            SELECT t.id, t.direction, t.title, t.booked_gross_minor, t.booked_currency,
                   c.display_name AS counterparty_name
              FROM transactions t
              LEFT JOIN counterparties c ON c.id = t.counterparty_id
             WHERE t.id IN \(placeholders)
            """,
            arguments: StatementArguments(transactionIDs)
        )
        return Dictionary(rows.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    /// The earliest date the archive knows: the first invoice, service or
    /// payment date. Nil while nothing is booked at all. Periods that end
    /// before it are periods Pfennig was not used for.
    public static func firstRecordedDate(_ db: Database) throws -> LocalDate? {
        let value = try String.fetchOne(
            db,
            sql: """
            SELECT MIN(d) FROM (
                SELECT MIN(invoice_date) AS d FROM transactions WHERE deleted_at IS NULL
                UNION ALL
                SELECT MIN(service_date) FROM transactions WHERE deleted_at IS NULL
                UNION ALL
                SELECT MIN(payment_date) FROM payments
            )
            """
        )
        return value.flatMap(LocalDate.init)
    }

    // MARK: - Settings

    /// Dauerfristverlängerung (§§46-48 UStDV) shifts every deadline out by one
    /// month. It lives in the generic `settings` table; reading it through the
    /// same connection as the values keeps both live in one observation.
    public static let dauerfristverlaengerungKey = "ustva.dauerfristverlaengerung"

    public static func dauerfristverlaengerung(_ db: Database) throws -> Bool {
        let json = try String.fetchOne(
            db,
            sql: "SELECT value_json FROM settings WHERE key = ?",
            arguments: [dauerfristverlaengerungKey]
        )
        guard let json else { return false }
        return (try? JSONDecoder().decode(Bool.self, from: Data(json.utf8))) ?? false
    }

    // MARK: - Submission state

    private static func submittedRecords(
        _ db: Database,
        profileID: String
    ) throws -> [String: SubmittedReturnRecord] {
        let rows = try SubmittedReturnRecord.fetchAll(
            db,
            sql: "SELECT * FROM submitted_returns WHERE business_profile_id = ?",
            arguments: [profileID]
        )
        return Dictionary(
            rows.map { ("\($0.year)-\($0.kind)-\($0.periodIndex)", $0) },
            uniquingKeysWith: { first, _ in first }
        )
    }

    static func submissionKey(_ period: UStVAPeriod) -> String {
        "\(period.year)-\(SubmittedReturnRepository.kindName(period.kind))-\(period.index)"
    }
}
