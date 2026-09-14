import Domain

/// Duplicate-detection checks that need DB context beyond a single entity
/// snapshot (spec 14.1, 14.2, 25). The caller supplies the facts already
/// looked up from the database.
public enum DuplicateValidator {
    /// Spec 14.1: "Duplicate immutable document identity (sha256)."
    public static func validateDocumentIdentity(sha256: String, existingHashes: Set<String>) -> ValidationIssue? {
        guard existingHashes.contains(sha256) else { return nil }
        return ValidationIssue(code: .duplicateDocumentIdentity, fieldName: "sha256", params: ["sha256": sha256])
    }

    /// Spec 14.1: "Duplicate statement line fingerprint on the same account."
    public static func validateStatementLineFingerprint(
        accountIBAN: String,
        fingerprint: String,
        existingFingerprints: Set<StatementLineFingerprintKey>
    ) -> ValidationIssue? {
        let key = StatementLineFingerprintKey(accountIBAN: accountIBAN, fingerprint: fingerprint)
        guard existingFingerprints.contains(key) else { return nil }
        return ValidationIssue(
            code: .duplicateStatementLineFingerprint,
            fieldName: "fingerprint",
            params: ["fingerprint": fingerprint]
        )
    }

    /// Spec 14.2 / 25: "Likely semantic duplicate." The caller computes the
    /// similarity score against DB-resident candidates (same counterparty,
    /// amount and nearby date, per spec 25); this only applies the threshold.
    public static func validateSemanticDuplicate(
        similarityScore: Double,
        threshold: Double = 0.85
    ) -> ValidationIssue? {
        guard similarityScore >= threshold else { return nil }
        return ValidationIssue(code: .semanticDuplicate, params: ["score": String(similarityScore)])
    }
}
