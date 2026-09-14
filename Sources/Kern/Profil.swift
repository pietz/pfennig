/// How often the UStVA is due.
public enum Rhythmus: String, CaseIterable, Hashable, Sendable {
    case monatlich
    case vierteljaehrlich
}

/// The user's own data, stored as single keys in `einstellungen`.
public struct Profil: Hashable, Sendable {
    public var steuernummer: String
    public var ustid: String
    public var kleinunternehmer: Bool
    public var rhythmus: Rhythmus
    public var dauerfristverlaengerung: Bool

    public init(
        steuernummer: String = "",
        ustid: String = "",
        kleinunternehmer: Bool = false,
        rhythmus: Rhythmus = .vierteljaehrlich,
        dauerfristverlaengerung: Bool = false
    ) {
        self.steuernummer = steuernummer
        self.ustid = ustid
        self.kleinunternehmer = kleinunternehmer
        self.rhythmus = rhythmus
        self.dauerfristverlaengerung = dauerfristverlaengerung
    }
}
