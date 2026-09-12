import Domain
import Foundation
import UniformTypeIdentifiers

/// Copies original documents into the archive's `Documents/` folder under
/// their SHA-256 (spec 17.10, 20). Originals are never modified, and an
/// identical file is stored exactly once: the hash is the identity.
public struct DocumentStore {
    public let archive: Archive
    private let fileManager: FileManager

    public init(archive: Archive, fileManager: FileManager = .default) {
        self.archive = archive
        self.fileManager = fileManager
    }

    /// Copies `url` into `Documents/<sha256>.<ext>` unless a file with that
    /// name already exists, and returns the draft the database needs.
    public func store(
        fileAt url: URL,
        role: DocumentRole = .invoice,
        source: DocumentSource = .fileImport
    ) throws -> DocumentDraft {
        let sha = try FileHasher.sha256(contentsOf: url)
        let ext = url.pathExtension.lowercased()
        let storedFilename = ext.isEmpty ? sha : "\(sha).\(ext)"
        let relativePath = "Documents/\(storedFilename)"
        let destination = archive.url(forRelativePath: relativePath)

        try fileManager.createDirectory(at: archive.documentsURL, withIntermediateDirectories: true)
        if !fileManager.fileExists(atPath: destination.path(percentEncoded: false)) {
            try fileManager.copyItem(at: url, to: destination)
        }

        let attributes = try? fileManager.attributesOfItem(atPath: destination.path(percentEncoded: false))
        let size = (attributes?[.size] as? NSNumber)?.int64Value ?? 0
        return DocumentDraft(
            sha256: sha,
            originalFilename: url.lastPathComponent,
            storedFilename: storedFilename,
            relativePath: relativePath,
            mimeType: UTType(filenameExtension: ext)?.preferredMIMEType,
            byteSize: size,
            documentType: Self.documentType(forExtension: ext),
            source: source,
            role: role
        )
    }

    /// File types the app accepts as a Beleg (spec 7.1).
    public static let supportedTypes: [UTType] = [.pdf, .png, .jpeg, .heic, .tiff]

    private static func documentType(forExtension ext: String) -> DocumentType {
        ext == "pdf" ? .invoice : .receipt
    }
}
