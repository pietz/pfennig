import Domain
@testable import Tax
import Testing

@Suite("AssetDetection")
struct AssetDetectionTests {
    @Test("assetCandidate kind always flags, regardless of amount")
    func assetCandidateAlwaysFlags() throws {
        let small = try Money.fromDecimalString("10.00", currency: .eur)
        #expect(AssetDetection.assetFlagApplies(categoryKind: .assetCandidate, netAmount: small))
    }

    @Test("Expense at exactly 800.00 EUR does not flag")
    func atThresholdDoesNotFlag() throws {
        let net = try Money.fromDecimalString("800.00", currency: .eur)
        #expect(!AssetDetection.assetFlagApplies(categoryKind: .expense, netAmount: net))
    }

    @Test("Expense at 800.01 EUR flags")
    func aboveThresholdFlags() throws {
        let net = try Money.fromDecimalString("800.01", currency: .eur)
        #expect(AssetDetection.assetFlagApplies(categoryKind: .expense, netAmount: net))
    }

    @Test("Expense well below the threshold does not flag")
    func wellBelowThreshold() throws {
        let net = try Money.fromDecimalString("299.00", currency: .eur)
        #expect(!AssetDetection.assetFlagApplies(categoryKind: .expense, netAmount: net))
    }

    @Test("Income kind never flags regardless of amount")
    func incomeNeverFlags() throws {
        let net = try Money.fromDecimalString("5000.00", currency: .eur)
        #expect(!AssetDetection.assetFlagApplies(categoryKind: .income, netAmount: net))
    }

    @Test("Neutral kind never flags regardless of amount")
    func neutralNeverFlags() throws {
        let net = try Money.fromDecimalString("5000.00", currency: .eur)
        #expect(!AssetDetection.assetFlagApplies(categoryKind: .neutral, netAmount: net))
    }
}

/// The category-aware overload (spec 5.6: the amount branch applies to
/// hardware/equipment categories only).
@Suite("AssetDetection by category")
struct AssetDetectionByCategoryTests {
    @Test("Expensive consulting is not an asset candidate")
    func consultingStaysClear() {
        #expect(
            AssetDetection.assetFlagApplies(
                categoryID: "professional_services",
                categoryKind: .expense,
                netAmount: Money(minorUnits: 500_000, currency: .eur)
            ) == false
        )
    }

    @Test("Hardware above the GWG threshold flags")
    func hardwareAboveThreshold() {
        #expect(
            AssetDetection.assetFlagApplies(
                categoryID: "hardware_small",
                categoryKind: .expense,
                netAmount: Money(minorUnits: 120_000, currency: .eur)
            )
        )
        #expect(
            AssetDetection.assetFlagApplies(
                categoryID: "hardware_small",
                categoryKind: .expense,
                netAmount: Money(minorUnits: 40000, currency: .eur)
            ) == false
        )
    }

    @Test("assetCandidate categories flag regardless of amount and ID")
    func assetCandidateAlways() {
        #expect(
            AssetDetection.assetFlagApplies(
                categoryID: "hardware_equipment",
                categoryKind: .assetCandidate,
                netAmount: Money(minorUnits: 100, currency: .eur)
            )
        )
    }
}
