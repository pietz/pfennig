import Domain
import Foundation
import GRDB

/// Canonical bookkeeping categories (spec 17.4). Seeded by `v001_initial`;
/// IDs are stable slugs and must never change.
public enum SystemCategories {
    public struct Seed: Sendable {
        public let id: String
        public let nameDE: String
        public let nameEN: String
        public let kind: CategoryKind
        public let documentExpected: Bool
    }

    public static let all: [Seed] = [
        // income
        Seed(
            id: "revenue_services",
            nameDE: "Erlöse Dienstleistungen",
            nameEN: "Revenue services",
            kind: .income,
            documentExpected: true
        ),
        Seed(
            id: "revenue_goods",
            nameDE: "Erlöse Waren",
            nameEN: "Revenue goods",
            kind: .income,
            documentExpected: true
        ),
        Seed(
            id: "revenue_licenses",
            nameDE: "Erlöse Lizenzen",
            nameEN: "Revenue licenses",
            kind: .income,
            documentExpected: true
        ),
        Seed(
            id: "other_income",
            nameDE: "Sonstige Einnahmen",
            nameEN: "Other income",
            kind: .income,
            documentExpected: true
        ),
        Seed(
            id: "vat_refund",
            nameDE: "Umsatzsteuererstattung",
            nameEN: "VAT refund",
            kind: .income,
            documentExpected: false
        ),
        Seed(
            id: "interest_income",
            nameDE: "Zinserträge",
            nameEN: "Interest income",
            kind: .income,
            documentExpected: false
        ),
        // expense
        Seed(
            id: "software_subscriptions",
            nameDE: "Software-Abonnements",
            nameEN: "Software subscriptions",
            kind: .expense,
            documentExpected: true
        ),
        Seed(
            id: "hosting_cloud",
            nameDE: "Hosting und Cloud",
            nameEN: "Hosting and cloud",
            kind: .expense,
            documentExpected: true
        ),
        Seed(
            id: "telecom",
            nameDE: "Telekommunikation",
            nameEN: "Telecommunication",
            kind: .expense,
            documentExpected: true
        ),
        Seed(
            id: "office_supplies",
            nameDE: "Bürobedarf",
            nameEN: "Office supplies",
            kind: .expense,
            documentExpected: true
        ),
        Seed(id: "office_rent", nameDE: "Raumkosten", nameEN: "Office rent", kind: .expense, documentExpected: true),
        Seed(
            id: "hardware_small",
            nameDE: "Geringwertige Hardware",
            nameEN: "Small hardware",
            kind: .expense,
            documentExpected: true
        ),
        Seed(id: "advertising", nameDE: "Werbung", nameEN: "Advertising", kind: .expense, documentExpected: true),
        Seed(
            id: "professional_services",
            nameDE: "Rechts- und Beratungskosten",
            nameEN: "Professional services",
            kind: .expense,
            documentExpected: true
        ),
        Seed(
            id: "contractors_freelancers",
            nameDE: "Fremdleistungen",
            nameEN: "Contractors and freelancers",
            kind: .expense,
            documentExpected: true
        ),
        Seed(
            id: "travel_transport",
            nameDE: "Reisekosten Fahrt",
            nameEN: "Travel transport",
            kind: .expense,
            documentExpected: true
        ),
        Seed(
            id: "travel_lodging",
            nameDE: "Reisekosten Übernachtung",
            nameEN: "Travel lodging",
            kind: .expense,
            documentExpected: true
        ),
        Seed(
            id: "meals_entertainment",
            nameDE: "Bewirtung",
            nameEN: "Meals and entertainment",
            kind: .expense,
            documentExpected: true
        ),
        Seed(
            id: "training_books",
            nameDE: "Fortbildung und Fachliteratur",
            nameEN: "Training and books",
            kind: .expense,
            documentExpected: true
        ),
        Seed(
            id: "insurance_business",
            nameDE: "Betriebliche Versicherungen",
            nameEN: "Business insurance",
            kind: .expense,
            documentExpected: true
        ),
        Seed(
            id: "bank_fees",
            nameDE: "Kontoführungsgebühren",
            nameEN: "Bank fees",
            kind: .expense,
            documentExpected: false
        ),
        Seed(
            id: "payment_provider_fees",
            nameDE: "Zahlungsdienstleister-Gebühren",
            nameEN: "Payment provider fees",
            kind: .expense,
            documentExpected: true
        ),
        Seed(
            id: "memberships",
            nameDE: "Beiträge und Mitgliedschaften",
            nameEN: "Memberships",
            kind: .expense,
            documentExpected: true
        ),
        Seed(
            id: "postage_shipping",
            nameDE: "Porto und Versand",
            nameEN: "Postage and shipping",
            kind: .expense,
            documentExpected: true
        ),
        Seed(
            id: "vat_payment",
            nameDE: "Umsatzsteuerzahlung",
            nameEN: "VAT payment",
            kind: .expense,
            documentExpected: false
        ),
        Seed(
            id: "other_expense",
            nameDE: "Sonstige Betriebsausgaben",
            nameEN: "Other expenses",
            kind: .expense,
            documentExpected: true
        ),
        // assetCandidate
        Seed(
            id: "hardware_equipment",
            nameDE: "Hardware und Geräte",
            nameEN: "Hardware and equipment",
            kind: .assetCandidate,
            documentExpected: true
        ),
        Seed(
            id: "furniture",
            nameDE: "Büroeinrichtung",
            nameEN: "Furniture",
            kind: .assetCandidate,
            documentExpected: true
        ),
        Seed(id: "vehicles", nameDE: "Fahrzeuge", nameEN: "Vehicles", kind: .assetCandidate, documentExpected: true),
        // neutral
        Seed(
            id: "uncategorized",
            nameDE: "Nicht kategorisiert",
            nameEN: "Uncategorized",
            kind: .neutral,
            documentExpected: true
        )
    ]

    static func seed(_ db: Database) throws {
        for (index, category) in all.enumerated() {
            try db.execute(
                sql: """
                INSERT INTO categories (id, parent_id, name_de, name_en, kind, document_expected, is_system, sort_order, archived_at)
                VALUES (?, NULL, ?, ?, ?, ?, 1, ?, NULL)
                """,
                arguments: [
                    category.id, category.nameDE, category.nameEN,
                    category.kind.rawValue, category.documentExpected ? 1 : 0, index * 10
                ]
            )
        }
    }
}
