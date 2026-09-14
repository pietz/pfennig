import Domain
import Testing
@testable import Validation

@Suite("IssueCode")
struct IssueCodeTests {
    @Test("Every code has a non-empty German message and a message key")
    func everyCodeHasMessage() {
        for code in IssueCode.allCases {
            #expect(!code.germanMessage.isEmpty, "\(code)")
            #expect(code.messageKey == "validation.\(code.rawValue.lowercased())")
        }
    }

    @Test("Hard codes are severity .error")
    func hardCodesAreErrors() {
        for code in IssueCode.hardCodes {
            #expect(code.severity == .error, "\(code)")
            #expect(code.isHard)
        }
    }

    @Test("Soft codes are not hard")
    func softCodesAreNotHard() {
        for code in IssueCode.allCases where !IssueCode.hardCodes.contains(code) {
            #expect(!code.isHard, "\(code)")
        }
    }

    @Test("Only the tolerance-mismatch family can be overridable")
    func onlyToleranceMismatchOverridable() {
        let toleranceFamily: Set<IssueCode> = [
            .taxComponentNetMismatch,
            .taxComponentTaxMismatch,
            .grossMismatch,
            .allocationSumMismatch
        ]
        let tinyDeviation = Money(minorUnits: 1, currency: .eur)
        for code in IssueCode.allCases {
            let overridable = code.isOverridable(deviation: tinyDeviation)
            #expect(overridable == toleranceFamily.contains(code), "\(code)")
        }
    }

    @Test("A tolerance-mismatch code beyond the 1 EUR ceiling is not overridable")
    func toleranceMismatchBeyondCeilingNotOverridable() {
        let largeDeviation = Money(minorUnits: 150, currency: .eur) // 1.50 EUR
        #expect(!IssueCode.grossMismatch.isOverridable(deviation: largeDeviation))
    }

    @Test("A tolerance-mismatch code exactly at the 1 EUR ceiling is overridable")
    func toleranceMismatchAtCeilingOverridable() {
        let atCeiling = Money(minorUnits: 100, currency: .eur) // 1.00 EUR
        #expect(IssueCode.grossMismatch.isOverridable(deviation: atCeiling))
    }

    @Test("Every IssueCode raw value round-trips")
    func rawValueRoundTrip() {
        for code in IssueCode.allCases {
            #expect(IssueCode(rawValue: code.rawValue) == code)
        }
    }
}

@Suite("ValidationIssue")
struct ValidationIssueTests {
    @Test("Default severity comes from the code when not overridden")
    func defaultSeverity() {
        let issue = ValidationIssue(code: .grossMismatch)
        #expect(issue.severity == .error)
    }

    @Test("Severity can be overridden explicitly")
    func explicitSeverity() {
        let issue = ValidationIssue(code: .grossMismatch, severity: .warning)
        #expect(issue.severity == .warning)
    }
}
