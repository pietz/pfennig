import Foundation

struct PreviewStartData {
    struct Flow: Identifiable {
        let id: String
        let title: String
        let detail: String
        let count: Int
        let symbol: String
        let tone: PreviewTone
    }

    struct Upcoming: Identifiable {
        let id: String
        let title: String
        let detail: String
        let date: String
        let symbol: String
    }

    let year: String
    let incomeText: String
    let expenseText: String
    let resultText: String
    let openItems: [Flow]
    let upcoming: [Upcoming]

    static let sample = PreviewStartData(
        year: "2025",
        incomeText: "38.240,00 €",
        expenseText: "12.860,00 €",
        resultText: "25.380,00 €",
        openItems: [
            Flow(
                id: "review",
                title: "Buchungen prüfen",
                detail: "Neue Einträge warten auf deine Freigabe",
                count: 4,
                symbol: "checkmark.seal",
                tone: .accent
            ),
            Flow(
                id: "documents",
                title: "Belege ergänzen",
                detail: "Buchungen ohne zugeordneten Beleg",
                count: 6,
                symbol: "doc.badge.plus",
                tone: .warning
            ),
            Flow(
                id: "imports",
                title: "Importvorschläge",
                detail: "Vorschläge im Beispieldatensatz",
                count: 2,
                symbol: "tray.and.arrow.down",
                tone: .neutral
            )
        ],
        upcoming: [
            Upcoming(
                id: "quarter-receipts",
                title: "Belege für Q2 ergänzen",
                detail: "Eigener Beispieltermin",
                date: "30.06.2025",
                symbol: "calendar"
            ),
            Upcoming(
                id: "euer-documents",
                title: "EÜR-Unterlagen sammeln",
                detail: "Eigener Beispieltermin",
                date: "15.07.2025",
                symbol: "folder"
            ),
            Upcoming(
                id: "bank-export",
                title: "Bankexport ablegen",
                detail: "Eigener Beispieltermin",
                date: "05.08.2025",
                symbol: "arrow.down.doc"
            )
        ]
    )
}

enum PreviewTone {
    case accent
    case positive
    case warning
    case neutral
}
