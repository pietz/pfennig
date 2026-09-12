import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Turns a file in the archive into something the Responses API accepts
/// (spec 10.4): PDFs go through unchanged within the page limit, HEIC is
/// converted to JPEG locally, JPEG and PNG pass through.
public enum DocumentPreparer {
    /// Configurable page limit; longer PDFs are rejected with a message.
    public static let defaultPageLimit = 20

    public static func prepare(fileAt url: URL, pageLimit: Int = defaultPageLimit) throws -> PreparedDocument {
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw AIError.unsupportedDocument("Die Datei \(url.lastPathComponent) konnte nicht gelesen werden.")
        }
        return try prepare(data: data, filename: url.lastPathComponent, pageLimit: pageLimit)
    }

    public static func prepare(
        data: Data,
        filename: String,
        pageLimit: Int = defaultPageLimit
    ) throws -> PreparedDocument {
        switch mimeType(data: data, filename: filename) {
        case "application/pdf":
            let pages = try pageCount(of: data, filename: filename)
            guard pages <= pageLimit else {
                throw AIError.unsupportedDocument(
                    "\(filename) hat \(pages) Seiten. Es werden höchstens \(pageLimit) Seiten ausgewertet."
                )
            }
            return PreparedDocument(
                kind: .pdf,
                data: data,
                filename: filename,
                mimeType: "application/pdf",
                pageCount: pages
            )
        case "image/jpeg", "image/png":
            return PreparedDocument(
                kind: .image,
                data: data,
                filename: filename,
                mimeType: mimeType(data: data, filename: filename)
            )
        case "image/heic":
            let jpeg = try jpegFromHEIC(data, filename: filename)
            return PreparedDocument(
                kind: .image,
                data: jpeg,
                filename: (filename as NSString).deletingPathExtension + ".jpg",
                mimeType: "image/jpeg"
            )
        default:
            throw AIError.unsupportedDocument(
                "\(filename) hat ein nicht unterstütztes Format. Erlaubt sind PDF, JPEG, PNG und HEIC."
            )
        }
    }

    /// Content sniffing first, extension second: a renamed file must not
    /// reach the API with the wrong media type.
    public static func mimeType(data: Data, filename: String) -> String {
        if data.starts(with: Array("%PDF".utf8)) {
            return "application/pdf"
        }
        if data.starts(with: [0xFF, 0xD8, 0xFF]) {
            return "image/jpeg"
        }
        if data.starts(with: [0x89, 0x50, 0x4E, 0x47]) {
            return "image/png"
        }
        if data.count > 12, data[4 ..< 8] == Data("ftyp".utf8) {
            let brand = String(decoding: data[8 ..< 12], as: UTF8.self)
            if brand.hasPrefix("hei") || brand.hasPrefix("mif") || brand.hasPrefix("msf") {
                return "image/heic"
            }
        }
        let ext = (filename as NSString).pathExtension.lowercased()
        return UTType(filenameExtension: ext)?.preferredMIMEType ?? "application/octet-stream"
    }

    public static func pageCount(of data: Data, filename: String = "") throws -> Int {
        guard let provider = CGDataProvider(data: data as CFData),
              let document = CGPDFDocument(provider)
        else {
            throw AIError.unsupportedDocument("\(filename) ist kein lesbares PDF.")
        }
        return document.numberOfPages
    }

    static func jpegFromHEIC(_ data: Data, filename: String) throws -> Data {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else {
            throw AIError.unsupportedDocument("\(filename) konnte nicht in JPEG umgewandelt werden.")
        }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            output, UTType.jpeg.identifier as CFString, 1, nil
        ) else {
            throw AIError.unsupportedDocument("\(filename) konnte nicht in JPEG umgewandelt werden.")
        }
        CGImageDestinationAddImage(
            destination,
            image,
            [kCGImageDestinationLossyCompressionQuality: 0.9] as CFDictionary
        )
        guard CGImageDestinationFinalize(destination) else {
            throw AIError.unsupportedDocument("\(filename) konnte nicht in JPEG umgewandelt werden.")
        }
        return output as Data
    }
}
