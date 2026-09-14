import Domain
import Foundation
@testable import Tax
import Testing

/// Mirrors the subset of `Fixtures/documents/*/expected.json` (spec 13) that
/// `TaxTreatmentDecider` needs.
private struct ExpectedFixture: Decodable {
    struct Counterparty: Decodable {
        let countryCode: String?
        let vatId: String?
    }

    struct Invoice: Decodable {
        let taxAmount: String
    }

    struct TreatmentHint: Decodable {
        let treatment: TaxTreatment
    }

    let direction: Direction
    let counterparty: Counterparty
    let invoice: Invoice
    let taxTreatmentHint: TreatmentHint
}

@Suite("TaxTreatmentDecider - fixture scenarios (Fixtures/documents)")
struct FixtureScenarioTests {
    /// Fixture folder name -> supply type. Not part of `expected.json`
    /// (spec 13 has no explicit supplyType field); inferred from the
    /// document description the same way a human bookkeeper would.
    static let supplyTypes: [String: SupplyType] = [
        "01-irish-saas-reverse-charge": .service,
        "02-german-hosting-monthly": .service,
        "03-office-supplies-kassenbon": .goods,
        "04-bahn-ticket-mixed-vat": .service,
        "05-hotel-invoice-lodging-breakfast": .service,
        "06-us-software-usd-reverse-charge": .service,
        "07-uk-consultancy-gbp-reverse-charge": .service,
        "08-hardware-laptop-asset-candidate": .goods,
        "09-hardware-monitor-small": .goods,
        "10-income-invoice-domestic-gmbh": .service,
        "11-income-invoice-france-reverse-charge": .service,
        "12-credit-note-hosting": .service,
        "13-telecom-deposit-line": .service,
        "14-cafe-receipt-photo": .goods
    ]

    static var fixturesRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // FixtureScenarioTests.swift -> Tests/TaxTests
            .deletingLastPathComponent() // TaxTests -> Tests
            .deletingLastPathComponent() // Tests -> repo root
            .appendingPathComponent("Fixtures/documents")
    }

    static var fixtureCases: [(name: String, url: URL)] {
        let fixtures = fixturesRoot
        guard let entries = try? FileManager.default.contentsOfDirectory(at: fixtures, includingPropertiesForKeys: nil)
        else {
            return []
        }
        return entries
            .filter(\.hasDirectoryPath)
            .map { ($0.lastPathComponent, $0.appendingPathComponent("expected.json")) }
            .sorted { $0.name < $1.name }
    }

    @Test("All 14 fixture folders are discovered", arguments: [14])
    func fixtureCount(expected: Int) {
        #expect(Self.fixtureCases.count == expected)
    }

    @Test("Decided treatment matches the fixture's taxTreatmentHint", arguments: Self.fixtureCases)
    func decisionMatchesFixture(fixture: (name: String, url: URL)) throws {
        let data = try Data(contentsOf: fixture.url)
        let expected = try JSONDecoder().decode(ExpectedFixture.self, from: data)
        let supplyType = Self.supplyTypes[fixture.name] ?? .unknown
        #expect(supplyType != .unknown, "missing supply type mapping for \(fixture.name)")

        let taxShown = (Decimal(string: expected.invoice.taxAmount).map { $0 != 0 }) ?? false
        let decision = TaxTreatmentDecider.decide(TaxTreatmentDecisionInput(
            profile: ProfileFacts(countryCode: "DE", vatStatus: .taxable, accountingMethod: .cash),
            direction: expected.direction,
            counterparty: CounterpartyTaxFacts(
                countryCode: expected.counterparty.countryCode,
                hasVATId: expected.counterparty.vatId != nil
            ),
            supplyType: supplyType,
            document: DocumentTaxFacts(taxShown: taxShown)
        ))

        #expect(decision.treatment == expected.taxTreatmentHint.treatment, "fixture: \(fixture.name)")
    }
}
