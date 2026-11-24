import Foundation

/// A booking's amount on a tax line, before any adjustment to the line total.
public struct Buchungsbeitrag: Encodable, Hashable, Sendable {
    public let buchungId: Int64?
    public let datum: LocalDate
    public let titel: String
    public let betrag: Cent

    init(_ buchung: Buchung, datum: LocalDate, betrag: Cent) {
        buchungId = buchung.id
        self.datum = datum
        titel = buchung.titel
        self.betrag = betrag
    }

    func mitBetrag(_ betrag: Cent) -> Buchungsbeitrag {
        Buchungsbeitrag(buchungId: buchungId, datum: datum, titel: titel, betrag: betrag)
    }

    private init(buchungId: Int64?, datum: LocalDate, titel: String, betrag: Cent) {
        self.buchungId = buchungId
        self.datum = datum
        self.titel = titel
        self.betrag = betrag
    }
}
