import SwiftUI

/// The window has one native workspace: the live bookings ledger.
struct WorkspaceView: View {
    @Bindable var model: AppModel

    var body: some View {
        NavigationSplitView {
            List {
                Label("Buchungen", systemImage: "list.bullet")
            }
            .listStyle(.sidebar)
            .navigationTitle("Pfennig")
            // A fixed width: the one entry needs no more and no less.
            .navigationSplitViewColumnWidth(WorkspaceView.sidebarWidth)
            // The sidebar always stays: there is nothing to reveal by hiding it.
            .toolbar(removing: .sidebarToggle)
        } detail: {
            // A plain trailing pane, not the native inspector. The native one
            // floats over the detail column instead of narrowing it, which
            // hides the right hand table columns.
            HStack(spacing: 0) {
                MainWindow(modell: model)
                if model.inspectorVisible {
                    Divider()
                    inspectorPane.frame(width: WorkspaceView.inspectorWidth)
                }
            }
        }
        // Keep the single live observation and inbox lifecycle at window scope.
        .task { await model.observe() }
        // The window is never narrower than its parts: sidebar, table and,
        // while it is shown, the inspector.
        .frame(minWidth: minimumWindowWidth, minHeight: 520)
    }

    /// The fixed sidebar width, the fixed inspector width and the smallest
    /// table width the columns need.
    static let sidebarWidth: CGFloat = 160
    static let inspectorWidth: CGFloat = 320
    static let tableMinimumWidth: CGFloat = 640

    private var minimumWindowWidth: CGFloat {
        let inspector = model.inspectorVisible ? Self.inspectorWidth + 1 : 0
        return Self.sidebarWidth + Self.tableMinimumWidth + inspector
    }

    @ViewBuilder private var inspectorPane: some View {
        if let buchung = model.ausgewaehlt {
            Inspector(modell: model, buchung: buchung)
                .id(buchung.id)
        } else {
            ContentUnavailableView("Keine Buchung ausgewählt", systemImage: "list.bullet.rectangle")
        }
    }
}
