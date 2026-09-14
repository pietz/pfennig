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
    @State private var transactionsInspectorHasChanges = false
    @State private var pendingSidebarSelection: SidebarItem?
    @State private var isConfirmingSidebarDiscard = false
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
                        List(SidebarItem.allCases, selection: guardedSidebarSelection) { item in
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
        .confirmationDialog(
            "Ungespeicherte Änderungen verwerfen?",
            isPresented: $isConfirmingSidebarDiscard,
            titleVisibility: .visible
        ) {
            Button("Änderungen verwerfen", role: .destructive) {
                let destination = pendingSidebarSelection
                pendingSidebarSelection = nil
                transactionsInspectorHasChanges = false
                selection = destination
            }
            Button("Weiter bearbeiten", role: .cancel) {
                pendingSidebarSelection = nil
            }
        } message: {
            Text("Speichern Sie die aktuelle Buchung zuerst, wenn Sie Ihre Änderungen behalten möchten.")
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
                TransactionsView(
                    database: database,
                    filter: $transactionFilter,
                    inspectorHasChanges: $transactionsInspectorHasChanges
                )
            }
        case .review:
            if let database = model.database {
                ReviewView(database: database)
            }
        case nil:
            ContentUnavailableView("Nichts ausgewählt", systemImage: "sidebar.left")
        }
    }

    private var guardedSidebarSelection: Binding<SidebarItem?> {
        Binding(
            get: { selection },
            set: { newSelection in
                guard selection != newSelection else { return }
                guard selection == .transactions, transactionsInspectorHasChanges else {
                    selectSidebarItem(newSelection)
                    return
                }
                pendingSidebarSelection = newSelection
                isConfirmingSidebarDiscard = true
            }
        )
    }

    private func selectSidebarItem(_ item: SidebarItem?) {
        if item == .transactions {
            transactionFilter = TransactionListFilter()
        }
        selection = item
    }
}
