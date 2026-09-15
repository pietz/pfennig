/// How often the UStVA is due.
public enum Rhythmus: String, CaseIterable, Hashable, Sendable {
    case monatlich
    case vierteljaehrlich
}

/// The user's own data, stored as single keys in `einstellungen`.
public struct Profil: Hashable, Sendable {
    /// The user's own name, person or business. The agent needs it to tell an
    /// own outgoing invoice from an incoming one.
    public var name: String
    public var adresse: String
    public var steuernummer: String
    public var ustid: String
    public var kleinunternehmer: Bool
    public var rhythmus: Rhythmus
    public var dauerfristverlaengerung: Bool

    public init(
        name: String = "",
        adresse: String = "",
        steuernummer: String = "",
        ustid: String = "",
        kleinunternehmer: Bool = false,
        rhythmus: Rhythmus = .vierteljaehrlich,
        dauerfristverlaengerung: Bool = false
    ) {
        self.name = name
        self.adresse = adresse
        self.steuernummer = steuernummer
        self.ustid = ustid
        self.kleinunternehmer = kleinunternehmer
        self.rhythmus = rhythmus
        self.dauerfristverlaengerung = dauerfristverlaengerung
    }
}
