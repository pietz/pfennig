import CryptoKit
import Foundation

/// Stable identity of a statement line, so overlapping statement exports are
/// safe to import twice (spec 17.12 / 34).
public enum LineFingerprint {
    public static func make(
        accountID: String,
        bookingDate: String,
        amountMinor: Int64,
        currency: String,
        reference: String?,
        counterpartyRaw: String?
    ) -> String {
        let parts = [
            accountID,
            bookingDate,
            String(amountMinor),
            currency.uppercased(),
            normalize(reference),
            normalize(counterpartyRaw)
        ]
        let digest = SHA256.hash(data: Data(parts.joined(separator: "|").utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private static func normalize(_ value: String?) -> String {
        guard let value else { return "" }
        return value
            .lowercased()
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
}
