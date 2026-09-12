import Domain
import Foundation

/// Extra facts a write carries beyond the draft itself: which proposal it
/// commits, which document and model run it came from, and the provenance of
/// individual fields (spec 8.3, 26). Manual editing keeps the default.
public struct WriteContext: Sendable {
    public var proposalID: String?
    public var sourceDocumentID: String?
    public var modelRunID: String?
    /// Provenance per `"<entityType>.<fieldName>"`; overrides what the actor
    /// alone would imply.
    public var provenance: [String: ProvenanceEntry]

    public init(
        proposalID: String? = nil,
        sourceDocumentID: String? = nil,
        modelRunID: String? = nil,
        provenance: [ProvenanceEntry] = []
    ) {
        self.proposalID = proposalID
        self.sourceDocumentID = sourceDocumentID
        self.modelRunID = modelRunID
        self.provenance = Dictionary(
            provenance.map { ("\($0.entityType).\($0.fieldName)", $0) },
            uniquingKeysWith: { _, last in last }
        )
    }

    public func entry(_ entityType: String, _ fieldName: String) -> ProvenanceEntry? {
        provenance["\(entityType).\(fieldName)"]
    }
}
