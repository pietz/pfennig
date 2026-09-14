import Domain
import Foundation

/// The deterministic half of spec section 4: the two classifications that
/// follow from the data alone.
///
/// `internalTransfer` and `taxPayment` are facts about the line.
/// Business versus private is a user decision and is not made here — every
/// other line stays `unknown` until the matcher and the user get to it.
public enum StatementLineClassifier {
    /// Words that, together with a Steuernummer, mark a VAT payment.
    static let vatMarkers: Set<String> = [
        "ustva", "umsatzsteuer", "umsatzsteuervoranmeldung", "ust", "umst", "mwst", "mehrwertsteuer"
    ]

    public static func classify(_ draft: StatementLineDraft, knownAccountKeys: Set<String>) -> StatementLineClass {
        if isInternalTransfer(draft, knownAccountKeys: knownAccountKeys) {
            return .internalTransfer
        }
        if isTaxPayment(draft) {
            return .taxPayment
        }
        return .unknown
    }

    /// The counterparty IBAN is one of the user's own accounts, meaning an
    /// account that already has statement lines.
    public static func isInternalTransfer(_ draft: StatementLineDraft, knownAccountKeys: Set<String>) -> Bool {
        guard let iban = draft.counterpartyIban else { return false }
        let normalized = StatementValueParser.normalizedIBAN(iban)
        return knownAccountKeys.contains { StatementValueParser.normalizedIBAN($0) == normalized }
    }

    /// Either the counterparty is a Finanzamt, or the purpose carries a
    /// Steuernummer together with a VAT keyword.
    public static func isTaxPayment(_ draft: StatementLineDraft) -> Bool {
        if let name = draft.counterpartyRaw, foldedForMatching(name).contains("finanzamt") {
            return true
        }
        let purpose = [draft.reference, draft.bookingText].compactMap(\.self).joined(separator: " ")
        guard containsSteuernummer(purpose) else { return false }
        return words(in: purpose).contains { vatMarkers.contains($0) }
    }

    /// German Steuernummer as written on a transfer: `143/815/09211`,
    /// `12/345/67890`, optionally with spaces around the slashes.
    static func containsSteuernummer(_ text: String) -> Bool {
        let digitsAndSlashes = text.map { character -> Character in
            if character.isNumber || character == "/" {
                return character
            }
            return " "
        }
        for token in String(digitsAndSlashes).split(separator: " ") {
            let parts = token.split(separator: "/", omittingEmptySubsequences: false)
            guard parts.count == 3, parts.allSatisfy({ $0.allSatisfy(\.isNumber) }) else { continue }
            if (2 ... 3).contains(parts[0].count), parts[1].count == 3, (4 ... 5).contains(parts[2].count) {
                return true
            }
        }
        return false
    }

    /// Lowercased, umlaut-transliterated words. Matching whole words keeps
    /// "USt" from firing on "August".
    static func words(in text: String) -> Set<String> {
        Set(
            foldedForMatching(text)
                .split { !$0.isLetter && !$0.isNumber }
                .map(String.init)
        )
    }

    static func foldedForMatching(_ text: String) -> String {
        HeaderNormalization.normalize(text)
    }
}
