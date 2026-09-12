import CryptoKit
import Foundation

/// SHA-256 of file contents: the immutable identity of every imported
/// document (spec 25).
public enum FileHasher {
    public static func sha256(contentsOf url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: 1 << 20), !chunk.isEmpty {
            hasher.update(data: chunk)
        }
        return hexString(hasher.finalize())
    }

    public static func sha256(of data: Data) -> String {
        hexString(SHA256.hash(data: data))
    }

    private static func hexString(_ digest: some Sequence<UInt8>) -> String {
        digest.map { String(format: "%02x", $0) }.joined()
    }
}
