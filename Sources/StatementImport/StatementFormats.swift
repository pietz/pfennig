import Domain
import Foundation

/// The header signatures documented in `docs/statement-formats.md`, one entry
/// per export. Adding a format here is a data change, not a new parser: every
/// entry is just a ``StatementColumnMapping`` plus the header cells that
/// identify it.
public extension HeaderMappingCatalog {
    static let formats: [StatementFormat] = [
        sparkasseCAMT,
        sparkasseMT940,
        volksbankVR,
        dkb,
        n26German,
        n26English,
        ingGermany,
        comdirect,
        paypalGerman,
        stripeBalance,
        amexGermany,
        revolut
    ]

    // MARK: - 1. Sparkasse CSV-CAMT (V2)

    static let sparkasseCAMT = StatementFormat(
        id: "sparkasse-camt",
        displayName: "Sparkasse CSV-CAMT",
        signature: [
            "Auftragskonto", "Buchungstag", "Valutadatum", "Verwendungszweck",
            "Beguenstigter/Zahlungspflichtiger", "Kontonummer/IBAN", "Betrag", "Waehrung"
        ],
        mapping: StatementColumnMapping(
            bookingDate: "Buchungstag",
            bookingDateFormat: .dayMonthYear,
            valueDate: "Valutadatum",
            valueDateFormat: .dayMonthYear,
            amount: .signed(column: "Betrag"),
            currencyColumn: "Waehrung",
            counterparty: .column("Beguenstigter/Zahlungspflichtiger"),
            counterpartyIBAN: "Kontonummer/IBAN",
            reference: .columns(["Verwendungszweck"]),
            bookingText: "Buchungstext",
            ownIBANColumn: "Auftragskonto"
        )
    )

    // MARK: - 2. Sparkasse CSV-MT940

    static let sparkasseMT940 = StatementFormat(
        id: "sparkasse-mt940",
        displayName: "Sparkasse CSV-MT940",
        signature: [
            "Auftragskonto", "Buchungstag", "Valutadatum", "Verwendungszweck",
            "Beguenstigter/Zahlungspflichtiger", "Kontonummer", "BLZ", "Betrag", "Waehrung"
        ],
        mapping: StatementColumnMapping(
            bookingDate: "Buchungstag",
            bookingDateFormat: .dayMonthYear,
            valueDate: "Valutadatum",
            valueDateFormat: .dayMonthYear,
            amount: .signed(column: "Betrag"),
            currencyColumn: "Waehrung",
            counterparty: .column("Beguenstigter/Zahlungspflichtiger"),
            // Domestic account numbers live here, not IBANs; anything that is
            // not IBAN-shaped is dropped when the line is built.
            counterpartyIBAN: "Kontonummer",
            reference: .columns(["Verwendungszweck"]),
            bookingText: "Buchungstext",
            ownIBANColumn: "Auftragskonto"
        )
    )

    // MARK: - 3. Volksbank / Raiffeisenbank web portal

    static let volksbankVR = StatementFormat(
        id: "volksbank-vr",
        displayName: "Volksbank / Raiffeisenbank (VR OnlineBanking)",
        signature: [
            "IBAN Auftragskonto", "Buchungstag", "Valutadatum", "Name Zahlungsbeteiligter",
            "IBAN Zahlungsbeteiligter", "Verwendungszweck", "Betrag", "Saldo nach Buchung"
        ],
        mapping: StatementColumnMapping(
            bookingDate: "Buchungstag",
            bookingDateFormat: .dayMonthYear,
            valueDate: "Valutadatum",
            valueDateFormat: .dayMonthYear,
            amount: .signed(column: "Betrag"),
            balanceColumn: "Saldo nach Buchung",
            currencyColumn: "Waehrung",
            counterparty: .column("Name Zahlungsbeteiligter"),
            counterpartyIBAN: "IBAN Zahlungsbeteiligter",
            reference: .columns(["Verwendungszweck"]),
            bookingText: "Buchungstext",
            ownIBANColumn: "IBAN Auftragskonto"
        )
    )

    // MARK: - 4. DKB (2023+ portal)

    static let dkb = StatementFormat(
        id: "dkb",
        displayName: "DKB",
        signature: [
            "Buchungsdatum", "Wertstellung", "Zahlungspflichtige*r", "Zahlungsempfänger*in",
            "Verwendungszweck", "Umsatztyp", "Betrag (€)"
        ],
        mapping: StatementColumnMapping(
            bookingDate: "Buchungsdatum",
            bookingDateFormat: .dayMonthYear,
            valueDate: "Wertstellung",
            valueDateFormat: .dayMonthYear,
            amount: .signed(column: "Betrag (€)"),
            // Both name columns are always filled, one of them being the
            // account owner; the sign of the amount decides which is which.
            counterparty: .payerOrPayee(payer: "Zahlungspflichtige*r", payee: "Zahlungsempfänger*in"),
            counterpartyIBAN: "IBAN",
            reference: .columns(["Verwendungszweck"]),
            bookingText: "Umsatztyp"
        )
    )

    // MARK: - 5. N26

    static let n26German = StatementFormat(
        id: "n26-de",
        displayName: "N26 (deutscher Export)",
        signature: [
            "Datum", "Empfänger", "Kontonummer", "Transaktionstyp", "Verwendungszweck", "Betrag (EUR)"
        ],
        mapping: StatementColumnMapping(
            bookingDate: "Datum",
            bookingDateFormat: .iso,
            amount: .signed(column: "Betrag (EUR)"),
            counterparty: .column("Empfänger"),
            counterpartyIBAN: "Kontonummer",
            reference: .columns(["Verwendungszweck"]),
            bookingText: "Transaktionstyp"
        )
    )

    static let n26English = StatementFormat(
        id: "n26-en",
        displayName: "N26 (English export)",
        signature: [
            "Booking Date", "Value Date", "Partner Name", "Partner Iban", "Payment Reference", "Amount (EUR)"
        ],
        mapping: StatementColumnMapping(
            bookingDate: "Booking Date",
            bookingDateFormat: .iso,
            valueDate: "Value Date",
            valueDateFormat: .iso,
            amount: .signed(column: "Amount (EUR)"),
            counterparty: .column("Partner Name"),
            counterpartyIBAN: "Partner Iban",
            reference: .columns(["Payment Reference"]),
            bookingText: "Type"
        )
    )

    // MARK: - 6. ING Germany

    static let ingGermany = StatementFormat(
        id: "ing-de",
        displayName: "ING Deutschland (Umsatzanzeige)",
        signature: [
            "Buchung", "Wertstellungsdatum", "Auftraggeber/Empfänger", "Buchungstext",
            "Verwendungszweck", "Betrag", "Währung"
        ],
        mapping: StatementColumnMapping(
            bookingDate: "Buchung",
            bookingDateFormat: .dayMonthYear,
            valueDate: "Wertstellungsdatum",
            valueDateFormat: .dayMonthYear,
            amount: .signed(column: "Betrag"),
            currencyColumn: "Währung",
            counterparty: .column("Auftraggeber/Empfänger"),
            reference: .columns(["Verwendungszweck"]),
            bookingText: "Buchungstext"
        )
    )

    // MARK: - 7. comdirect

    static let comdirect = StatementFormat(
        id: "comdirect",
        displayName: "comdirect",
        signature: ["Buchungstag", "Wertstellung (Valuta)", "Vorgang", "Buchungstext", "Umsatz in EUR"],
        mapping: StatementColumnMapping(
            bookingDate: "Buchungstag",
            bookingDateFormat: .dayMonthYear,
            valueDate: "Wertstellung (Valuta)",
            valueDateFormat: .dayMonthYear,
            amount: .signed(column: "Umsatz in EUR"),
            // comdirect packs counterparty and purpose into one field as
            // labelled, undelimited substrings.
            counterparty: .labelled(column: "Buchungstext", labels: ["Auftraggeber:", "Empfänger:", "Empfaenger:"]),
            reference: .labelled(column: "Buchungstext", label: "Buchungstext:"),
            bookingText: "Vorgang",
            labelVocabulary: [
                "Auftraggeber:", "Empfänger:", "Empfaenger:", "Buchungstext:", "Karte Nr.",
                "Referenz:", "Mandat:", "Gläubiger-ID:"
            ]
        )
    )

    // MARK: - 8. PayPal (German locale)

    static let paypalGerman = StatementFormat(
        id: "paypal-de",
        displayName: "PayPal (Alle Transaktionen)",
        signature: [
            "Datum", "Name", "Typ", "Währung", "Brutto", "Gebühr", "Netto",
            "Transaktionscode", "Rechnungsnummer"
        ],
        mapping: StatementColumnMapping(
            bookingDate: "Datum",
            bookingDateFormat: .dayMonthYear,
            // "Netto" is what actually moves the PayPal balance.
            amount: .signed(column: "Netto"),
            feeColumn: "Gebühr",
            feeIncludedInAmount: true,
            currencyColumn: "Währung",
            counterparty: .column("Name"),
            reference: .columns(["Rechnungsnummer", "Artikelbezeichnung", "Betreff", "Hinweis"]),
            bookingText: "Typ",
            externalID: "Transaktionscode"
        )
    )

    // MARK: - 9. Stripe balance transactions

    static let stripeBalance = StatementFormat(
        id: "stripe-balance",
        displayName: "Stripe (balance transactions)",
        signature: [
            "balance_transaction_id", "created", "available_on", "currency",
            "gross", "fee", "net", "reporting_category", "description"
        ],
        mapping: StatementColumnMapping(
            bookingDate: "created",
            bookingDateFormat: .iso,
            valueDate: "available_on",
            valueDateFormat: .iso,
            amount: .signed(column: "net"),
            feeColumn: "fee",
            feeIncludedInAmount: true,
            currencyColumn: "currency",
            reference: .columns(["description"]),
            bookingText: "reporting_category",
            externalID: "balance_transaction_id"
        )
    )

    // MARK: - 10. American Express Germany

    static let amexGermany = StatementFormat(
        id: "amex-de",
        displayName: "American Express Deutschland",
        signature: ["Datum", "Beschreibung", "Karteninhaber", "Konto #", "Betrag"],
        mapping: StatementColumnMapping(
            bookingDate: "Datum",
            bookingDateFormat: .dayMonthYearSlash,
            amount: .signed(column: "Betrag"),
            // Amex reports purchases positive and payments negative, the
            // opposite of every German bank export.
            invertSign: true,
            counterparty: .column("Beschreibung"),
            reference: .columns(["Beschreibung"])
        )
    )

    // MARK: - 11. Revolut

    static let revolut = StatementFormat(
        id: "revolut",
        displayName: "Revolut",
        signature: [
            "Type", "Product", "Started Date", "Completed Date", "Description",
            "Amount", "Fee", "Currency", "State", "Balance"
        ],
        mapping: StatementColumnMapping(
            bookingDate: "Completed Date",
            bookingDateFormat: .iso,
            valueDate: "Started Date",
            valueDateFormat: .iso,
            amount: .signed(column: "Amount"),
            // The fee is reported positive and still lowers the balance, so
            // the booked movement is Amount - Fee.
            feeColumn: "Fee",
            feeIncludedInAmount: false,
            balanceColumn: "Balance",
            rowFilter: .init(column: "State", keepValues: ["COMPLETED"]),
            currencyColumn: "Currency",
            counterparty: .column("Description"),
            reference: .columns(["Description"]),
            bookingText: "Type"
        )
    )
}
