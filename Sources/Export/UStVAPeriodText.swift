import Tax

/// Human and machine names for a UStVA period, shared by the XML exporter and
/// the copyable value list.
enum UStVAPeriodText {
    private static let monthNames = [
        "Januar", "Februar", "März", "April", "Mai", "Juni",
        "Juli", "August", "September", "Oktober", "November", "Dezember"
    ]

    /// ELSTER `Zeitraum` code: `01`-`12` for months, `41`-`44` for quarters.
    ///
    /// Unverified: the quarter codes come from the open-source project
    /// geierlein and the common ELSTER convention, not from an elster.de page
    /// (see docs/research-ustva-xml.md, "Verifiziert vs. unsicher").
    static func zeitraumCode(_ period: UStVAPeriod) -> String {
        switch period.kind {
        case .monthly: String(format: "%02d", period.index)
        case .quarterly: String(40 + period.index)
        }
    }

    /// Compact token used in file names: `Q3` or `07`.
    static func fileToken(_ period: UStVAPeriod) -> String {
        switch period.kind {
        case .monthly: String(format: "%02d", period.index)
        case .quarterly: "Q\(period.index)"
        }
    }

    /// Heading used in the copyable value list: `Q3 2026` or `Juli 2026`.
    static func title(_ period: UStVAPeriod) -> String {
        switch period.kind {
        case .monthly: "\(monthNames[period.index - 1]) \(period.year)"
        case .quarterly: "Q\(period.index) \(period.year)"
        }
    }
}
