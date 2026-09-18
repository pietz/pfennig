import Foundation

/// Errors that prevent Pfennig from writing a tax export.
public enum ExportError: LocalizedError, Equatable, Sendable {
    case unsupportedYear(Int)

    /// The UStVA Kennzahlen/XML contract and the EÜR mappings are verified
    /// only for the 2026 tax year.
    public static func validate(year: Int) throws {
        guard year == 2026 else { throw ExportError.unsupportedYear(year) }
    }

    public var errorDescription: String? {
        switch self {
        case let .unsupportedYear(year):
            "Der Export für das Steuerjahr \(year) ist nicht möglich. Pfennig unterstützt derzeit nur das Steuerjahr 2026."
        }
    }
}
