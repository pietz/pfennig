import Domain
import Foundation
import GRDB

/// Canonical bookkeeping categories (spec 17.4). Seeded by `v001_initial`;
/// IDs are stable slugs and must never change.
public enum SystemCategories {
    public struct Seed: Sendable {
        public let id: String
        public let nameDE: String
        public let kind: CategoryKind
        public let documentExpected: Bool
    }

    public static let all: [Seed] = [
        // income
        Seed(
            id: "revenue_services",
            nameDE: "Erlöse Dienstleistungen",
            kind: .income,
            documentExpected: true
        ),
        Seed(
            id: "revenue_goods",
            nameDE: "Erlöse Waren",
            kind: .income,
            documentExpected: true
        ),
        Seed(
            id: "revenue_licenses",
            nameDE: "Erlöse Lizenzen",
            kind: .income,
            documentExpected: true
        ),
        Seed(
            id: "other_income",
            nameDE: "Sonstige Einnahmen",
            kind: .income,
            documentExpected: true
        ),
        Seed(
            id: "vat_refund",
            nameDE: "Umsatzsteuererstattung",
            kind: .income,
            documentExpected: false
        ),
        Seed(
            id: "interest_income",
            nameDE: "Zinserträge",
            kind: .income,
            documentExpected: false
        ),
        // expense
        Seed(
            id: "software_subscriptions",
            nameDE: "Software-Abonnements",
            kind: .expense,
            documentExpected: true
        ),
        Seed(
            id: "hosting_cloud",
            nameDE: "Hosting und Cloud",
            kind: .expense,
            documentExpected: true
        ),
        Seed(
            id: "telecom",
            nameDE: "Telekommunikation",
            kind: .expense,
            documentExpected: true
        ),
        Seed(
            id: "office_supplies",
            nameDE: "Bürobedarf",
            kind: .expense,
            documentExpected: true
        ),
        Seed(id: "office_rent", nameDE: "Raumkosten", kind: .expense, documentExpected: true),
        Seed(
            id: "hardware_small",
            nameDE: "Geringwertige Hardware",
            kind: .expense,
            documentExpected: true
        ),
        Seed(id: "advertising", nameDE: "Werbung", kind: .expense, documentExpected: true),
        Seed(
            id: "professional_services",
            nameDE: "Rechts- und Beratungskosten",
            kind: .expense,
            documentExpected: true
        ),
        Seed(
            id: "contractors_freelancers",
            nameDE: "Fremdleistungen",
            kind: .expense,
            documentExpected: true
        ),
        Seed(
            id: "travel_transport",
            nameDE: "Reisekosten Fahrt",
            kind: .expense,
            documentExpected: true
        ),
        Seed(
            id: "travel_lodging",
            nameDE: "Reisekosten Übernachtung",
            kind: .expense,
            documentExpected: true
        ),
        Seed(
            id: "meals_entertainment",
            nameDE: "Bewirtung",
            kind: .expense,
            documentExpected: true
        ),
        Seed(
            id: "training_books",
            nameDE: "Fortbildung und Fachliteratur",
            kind: .expense,
            documentExpected: true
        ),
        Seed(
            id: "insurance_business",
            nameDE: "Betriebliche Versicherungen",
            kind: .expense,
            documentExpected: true
        ),
        Seed(
            id: "bank_fees",
            nameDE: "Kontoführungsgebühren",
            kind: .expense,
            documentExpected: false
        ),
        Seed(
            id: "payment_provider_fees",
            nameDE: "Zahlungsdienstleister-Gebühren",
            kind: .expense,
            documentExpected: true
        ),
        Seed(
            id: "memberships",
            nameDE: "Beiträge und Mitgliedschaften",
            kind: .expense,
            documentExpected: true
        ),
        Seed(
            id: "postage_shipping",
            nameDE: "Porto und Versand",
            kind: .expense,
            documentExpected: true
        ),
        Seed(
            id: "vat_payment",
            nameDE: "Umsatzsteuerzahlung",
            kind: .expense,
            documentExpected: false
        ),
        Seed(
            id: "other_expense",
            nameDE: "Sonstige Betriebsausgaben",
            kind: .expense,
            documentExpected: true
        ),
        // assetCandidate
        Seed(
            id: "hardware_equipment",
            nameDE: "Hardware und Geräte",
            kind: .assetCandidate,
            documentExpected: true
        ),
        Seed(
            id: "furniture",
            nameDE: "Büroeinrichtung",
            kind: .assetCandidate,
            documentExpected: true
        ),
        Seed(id: "vehicles", nameDE: "Fahrzeuge", kind: .assetCandidate, documentExpected: true),
        // neutral
        Seed(
            id: "uncategorized",
            nameDE: "Nicht kategorisiert",
            kind: .neutral,
            documentExpected: true
        )
    ]

    static func seed(_ db: Database) throws {
        for (index, category) in all.enumerated() {
            try db.execute(
                sql: """
                INSERT INTO categories (id, name_de, kind, document_expected, sort_order, archived_at)
                VALUES (?, ?, ?, ?, ?, NULL)
                """,
                arguments: [
                    category.id, category.nameDE,
                    category.kind.rawValue, category.documentExpected ? 1 : 0, index * 10
                ]
            )
        }
    }
}
