import AppKit
import Database
import SwiftUI
import Tax

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
    /// Opens the UStVA task window for one Voranmeldungszeitraum.
    case ustva(UStVAPeriod)
}

struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow
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
        .background(WindowReader { window in
            if let window {
                model.mainWindow = window
            }
        })
        .onChange(of: model.requestedTransactionID) { _, id in
            // Another window asked for a booking; the ledger has to be on
            // screen before `TransactionsView` can select it.
            guard id != nil else { return }
            selection = .transactions
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
                case let .ustva(period):
                    model.ustvaTaskPeriod = period
                    openWindow(id: UStVATaskWindow.windowID)
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
                ReviewView(database: database) { filter in
                    transactionFilter = filter
                    selection = .transactions
                }
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

// MARK: - Window

/// Hands the hosting `NSWindow` to SwiftUI. The view itself stays empty and is
/// meant to sit in a `background`, where it takes part in no layout.
struct WindowReader: NSViewRepresentable {
    let onChange: (NSWindow?) -> Void

    func makeNSView(context _: Context) -> ReadingView {
        let view = ReadingView()
        view.onChange = onChange
        return view
    }

    func updateNSView(_ view: ReadingView, context _: Context) {
        view.onChange = onChange
    }

    final class ReadingView: NSView {
        var onChange: ((NSWindow?) -> Void)?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            onChange?(window)
        }
    }
}
