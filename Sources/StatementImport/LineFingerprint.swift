import CryptoKit
import Domain
import Foundation

/// Stable identity of a statement line, so overlapping statement exports are
/// safe to import twice (spec 17.12 / 34).
///
/// Two shapes, chosen per line:
///
/// - The export carries its own transaction id (PayPal `Transaktionscode`,
///   Stripe `balance_transaction_id`): that id *is* the identity. It survives
///   a reworded Verwendungszweck between two exports of the same period, and
///   it never collides with another movement.
/// - Otherwise the identity is what the file actually says: booking date,
///   amount, currency, purpose and counterparty. Two rows of one file can
///   legitimately be identical - the same coffee bought twice on one day - so
///   the second and any further occurrence carry an occurrence index. Both are
///   real movements and both are kept; an overlapping later export produces
///   the same indices and is still recognized as already known.
public enum LineFingerprint {
    /// - Parameters:
    ///   - accountID: the account key the line belongs to. The identity is
    ///     per account, which is why the importer computes it and the
    ///     persistence layer only stores it.
    ///   - occurrence: 1 for the first line with this identity in a file, 2
    ///     for the next identical one, and so on. Occurrence 1 adds nothing,
    ///     so the overwhelming majority of lines - the unique ones - are
    ///     fingerprinted by their facts alone.
    public static func make(accountID: String, line: StatementLineDraft, occurrence: Int = 1) -> String {
        var parts = [
            accountID,
            line.bookingDate.description,
            String(line.amountMinor),
            line.currency.rawValue.uppercased()
        ]
        let externalID = normalize(line.externalId)
        if !externalID.isEmpty {
            parts.append("id:" + externalID)
        } else {
            parts.append(normalize(line.reference))
            parts.append(normalize(line.counterpartyRaw))
        }
        if occurrence > 1 {
            parts.append("#\(occurrence)")
        }
        return SHA256Hex.of(parts.joined(separator: "|"))
    }

    /// Lowercased and with runs of whitespace collapsed. Deliberately its own
    /// normalization and not `HeaderNormalization`: that one exists to compare
    /// column names and may be tightened at any time, while every change here
    /// invalidates the identity of lines already in an archive.
    private static func normalize(_ value: String?) -> String {
        guard let value else { return "" }
        return value
            .lowercased()
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
}

/// Lowercase hex SHA-256 of a string. Shared by the line fingerprint and the
/// header fingerprint, which both only need a stable identity.
public enum SHA256Hex {
    public static func of(_ text: String) -> String {
        SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}
