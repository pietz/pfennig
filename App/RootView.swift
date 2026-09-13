import Database
import SwiftUI

enum SidebarItem: String, CaseIterable, Identifiable {
    case start, transactions, review

    var id: String {
        rawValue
    }

    var title: LocalizedStringResource {
        switch self {
        case .start: "Start"
        case .transactions: "Buchungen"
        case .review: "Prüfen"
        }
    }

    var symbol: String {
        switch self {
        case .start: "rectangle.grid.1x2"
        case .transactions: "list.bullet.rectangle"
        case .review: "checkmark.seal"
        }
    }
}

enum StartDestination: Equatable {
    case transactions(TransactionListFilter)
    case review
}

struct RootView: View {
    @Environment(AppModel.self) private var model
    @State private var selection: SidebarItem? = .start
    @State private var transactionFilter = TransactionListFilter()
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    var body: some View {
        @Bindable var model = model
        Group {
            switch model.stage {
            case .profile:
                OnboardingView()
            case .ready:
                NavigationSplitView(columnVisibility: $columnVisibility) {
                    VStack(spacing: 0) {
                        List(SidebarItem.allCases, selection: $selection) { item in
                            Label(item.title, systemImage: item.symbol)
                                .badge(item == .review ? model.pendingProposalCount : 0)
                                .tag(item)
                        }
                        .listStyle(.sidebar)

                        Divider()

                        SettingsLink {
                            Label("Einstellungen", systemImage: "gearshape")
                        }
                        .buttonStyle(.borderless)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                    }
                    .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 260)
                } detail: {
                    detail
                }
                .task { await model.observePendingProposals() }
            }
        }
        .alert(
            "Es ist ein Fehler aufgetreten",
            isPresented: Binding(
                get: { model.errorMessage != nil },
                set: { isPresented in
                    if !isPresented {
                        model.errorMessage = nil
                    }
                }
            )
        ) {
            Button("OK") { model.errorMessage = nil }
        } message: {
            Text(model.errorMessage ?? "")
        }
    }

    @ViewBuilder
    private var detail: some View {
        switch selection {
        case .start:
            StartView { destination in
                switch destination {
                case let .transactions(filter):
                    transactionFilter = filter
                    selection = .transactions
                case .review:
                    selection = .review
                }
            }
        case .transactions:
            if let database = model.database {
                TransactionsView(database: database, filter: transactionFilter)
                    .id(transactionFilter)
            }
        case .review:
            if let database = model.database {
                ReviewView(database: database)
            }
        case nil:
            ContentUnavailableView("Nichts ausgewählt", systemImage: "sidebar.left")
        }
    }
}
