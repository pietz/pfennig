import Foundation

/// One physical record of a CSV file. `lineNumber` is 1-based and counts
/// records, not newlines, so a quoted field containing a line break does not
/// shift the numbers the user sees in an error message.
public struct CSVRow: Sendable, Equatable {
    public let lineNumber: Int
    public let fields: [String]

    public init(lineNumber: Int, fields: [String]) {
        self.lineNumber = lineNumber
        self.fields = fields
    }

    public var isBlank: Bool {
        fields.allSatisfy { $0.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    public func field(_ index: Int) -> String? {
        guard index >= 0, index < fields.count else { return nil }
        return fields[index]
    }
}

/// A decoded CSV file: the rows, plus what had to be guessed to read it.
public struct CSVFile: Sendable, Equatable {
    public let rows: [CSVRow]
    public let delimiter: Character
    public let encoding: String.Encoding
    public let hadByteOrderMark: Bool
}

public enum CSVReaderError: Error, Equatable, Sendable, LocalizedError {
    case undecodableText
    case empty

    public var errorDescription: String? {
        switch self {
        case .undecodableText: "Die Datei konnte weder als UTF-8 noch als Latin-1 gelesen werden."
        case .empty: "Die Datei enthält keine Zeilen."
        }
    }
}

/// A small RFC-4180-tolerant CSV reader.
///
/// Deliberately not a general CSV library: it does exactly what German bank
/// and payment-processor exports need — a delimiter guessed from the file,
/// a stripped byte-order mark, a Latin-1 fallback when the bytes are not
/// valid UTF-8, quoted fields with doubled quotes and embedded newlines, and
/// any mix of `CRLF`, `LF` and `CR` line endings.
public enum CSVReader {
    /// Delimiters we consider, in preference order for ties.
    public static let candidateDelimiters: [Character] = [";", ",", "\t", "|"]

    public static func read(_ data: Data, delimiter: Character? = nil) throws -> CSVFile {
        let decoded = try decode(data)
        let chosen = delimiter ?? detectDelimiter(in: decoded.text)
        let rows = parse(decoded.text, delimiter: chosen)
        guard !rows.isEmpty else { throw CSVReaderError.empty }
        return CSVFile(
            rows: rows,
            delimiter: chosen,
            encoding: decoded.encoding,
            hadByteOrderMark: decoded.hadByteOrderMark
        )
    }

    public static func read(contentsOf url: URL, delimiter: Character? = nil) throws -> CSVFile {
        try read(Data(contentsOf: url), delimiter: delimiter)
    }

    // MARK: - Decoding

    struct DecodedText {
        let text: String
        let encoding: String.Encoding
        let hadByteOrderMark: Bool
    }

    /// UTF-8 first (with or without BOM), then Windows-1252, which is a
    /// superset of ISO-8859-1 and decodes ISO-8859-15 bytes without failing.
    /// Latin-1 never rejects a byte, so it is the last resort by design.
    static func decode(_ data: Data) throws -> DecodedText {
        var bytes = data
        var hadBOM = false
        if bytes.starts(with: [0xEF, 0xBB, 0xBF]) {
            bytes = bytes.dropFirst(3)
            hadBOM = true
        }
        if let text = String(data: bytes, encoding: .utf8) {
            return DecodedText(text: text, encoding: .utf8, hadByteOrderMark: hadBOM)
        }
        for encoding in [String.Encoding.windowsCP1252, .isoLatin1] {
            if let text = String(data: bytes, encoding: encoding) {
                return DecodedText(text: text, encoding: encoding, hadByteOrderMark: hadBOM)
            }
        }
        throw CSVReaderError.undecodableText
    }

    // MARK: - Delimiter detection

    /// Picks the delimiter that makes the file most rectangular: for each
    /// candidate, take the most common field count of at least two and score
    /// it by the number of cells it explains (rows × columns).
    ///
    /// Counting cells rather than rows is what keeps ING's prose preamble —
    /// one sentence with two commas in it — from outvoting the actual
    /// seven-column, semicolon-separated table below it.
    public static func detectDelimiter(in text: String) -> Character {
        var best: (delimiter: Character, score: Int, rows: Int)?
        for candidate in candidateDelimiters {
            let rows = parse(text, delimiter: candidate, limit: 60)
            var histogram: [Int: Int] = [:]
            for row in rows where !row.isBlank {
                histogram[row.fields.count, default: 0] += 1
            }
            let modal = histogram
                .filter { $0.key >= 2 }
                .max { left, right in (left.value * left.key, left.value) < (right.value * right.key, right.value) }
            guard let modal else { continue }
            let score = modal.value * modal.key
            if let current = best, (score, modal.value) <= (current.score, current.rows) {
                continue
            }
            best = (candidate, score, modal.value)
        }
        return best?.delimiter ?? ";"
    }

    // MARK: - Parsing

    /// RFC 4180 with the usual tolerances. `limit` stops after that many rows,
    /// which keeps delimiter detection cheap on large exports.
    public static func parse(_ text: String, delimiter: Character, limit: Int = .max) -> [CSVRow] {
        var rows: [CSVRow] = []
        var fields: [String] = []
        var field = ""
        var inQuotes = false
        var lineNumber = 1
        var index = text.startIndex

        func endField() {
            fields.append(field)
            field = ""
        }

        func endRow() {
            endField()
            rows.append(CSVRow(lineNumber: lineNumber, fields: fields))
            fields = []
            lineNumber += 1
        }

        while index < text.endIndex, rows.count < limit {
            let character = text[index]
            if inQuotes {
                switch character {
                case "\"":
                    let next = text.index(after: index)
                    if next < text.endIndex, text[next] == "\"" {
                        field.append("\"")
                        index = next
                    } else {
                        inQuotes = false
                    }
                // Swift reads CRLF as one Character; a newline inside a
                // quoted field is kept, normalized to LF.
                case "\r\n", "\r":
                    field.append("\n")
                default:
                    field.append(character)
                }
            } else {
                switch character {
                case "\"" where field.isEmpty:
                    inQuotes = true
                case delimiter:
                    endField()
                case "\r\n", "\r", "\n":
                    endRow()
                default:
                    field.append(character)
                }
            }
            index = text.index(after: index)
        }

        if rows.count < limit, !field.isEmpty || !fields.isEmpty {
            endRow()
        }
        return rows
    }
}
