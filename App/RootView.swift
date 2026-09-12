import SwiftUI

enum SidebarItem: String, CaseIterable, Identifiable {
    case transactions, accounts, review, analysis, taxes, settings

    var id: String {
        rawValue
    }

    var title: LocalizedStringResource {
        switch self {
        case .transactions: "Buchungen"
        case .accounts: "Konten"
        case .review: "Prüfen"
        case .analysis: "Auswertung"
        case .taxes: "Steuern"
        case .settings: "Einstellungen"
        }
    }

    var symbol: String {
        switch self {
        case .transactions: "list.bullet.rectangle"
        case .accounts: "building.columns"
        case .review: "checkmark.seal"
        case .analysis: "chart.bar"
        case .taxes: "percent"
        case .settings: "gearshape"
        }
    }
}

struct RootView: View {
    @Environment(AppModel.self) private var model
    @State private var selection: SidebarItem? = .transactions

    var body: some View {
        @Bindable var model = model
        Group {
            switch model.stage {
            case .profile:
                OnboardingView()
            case .ready:
                NavigationSplitView {
                    List(SidebarItem.allCases, selection: $selection) { item in
                        Label(item.title, systemImage: item.symbol).tag(item)
                    }
                    .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 260)
                } detail: {
                    detail
                }
            }
        }
        .alert("Es ist ein Fehler aufgetreten", isPresented: .constant(model.errorMessage != nil)) {
            Button("OK") { model.errorMessage = nil }
        } message: {
            Text(model.errorMessage ?? "")
        }
    }

    @ViewBuilder
    private var detail: some View {
        switch selection {
        case .transactions:
            if let database = model.database {
                TransactionsView(database: database)
            }
        case .settings:
            SettingsView()
        case .accounts:
            placeholder(
                "Konten",
                symbol: "building.columns",
                description: "Kontoauszüge importieren und Zahlungen zuordnen. Kommt mit Meilenstein M6."
            )
        case .review:
            placeholder(
                "Prüfen",
                symbol: "checkmark.seal",
                description: "Vorschläge der KI prüfen und bestätigen. Kommt mit Meilenstein M4."
            )
        case .analysis:
            placeholder(
                "Auswertung",
                symbol: "chart.bar",
                description: "Einnahmen, Ausgaben und Umsatzsteuer je Zeitraum. Kommt mit Meilenstein M9."
            )
        case .taxes:
            placeholder(
                "Steuern",
                symbol: "percent",
                description: "UStVA und EÜR vorbereiten. Kommt mit Meilenstein M10."
            )
        case nil:
            ContentUnavailableView("Nichts ausgewählt", systemImage: "sidebar.left")
        }
    }

    private func placeholder(
        _ title: LocalizedStringKey,
        symbol: String,
        description: LocalizedStringKey
    ) -> some View {
        ContentUnavailableView {
            Label(title, systemImage: symbol)
        } description: {
            Text(description)
        }
        .navigationTitle(Text(title))
    }
}
