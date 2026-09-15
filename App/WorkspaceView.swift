import SwiftUI

/// The window has one native workspace: the live bookings ledger.
enum Workspace: String, CaseIterable, Identifiable {
    case buchungen

    var id: String {
        rawValue
    }

    var name: String {
        switch self {
        case .buchungen: "Buchungen"
        }
    }

    var symbol: String {
        switch self {
        case .buchungen: "list.bullet"
        }
    }
}

struct WorkspaceView: View {
    @Bindable var model: AppModel
    /// The one workspace of the window, always the selected sidebar item.
    @State private var workspace: Workspace = .buchungen

    var body: some View {
        NavigationSplitView {
            List(Workspace.allCases, selection: $workspace) { item in
                Label(item.name, systemImage: item.symbol).tag(item)
            }
            .listStyle(.sidebar)
            .navigationTitle("Pfennig")
            // A fixed width: the one entry needs no more and no less.
            .navigationSplitViewColumnWidth(WorkspaceView.sidebarWidth)
            // The sidebar always stays: there is nothing to reveal by hiding it.
            .toolbar(removing: .sidebarToggle)
            .safeAreaInset(edge: .bottom, spacing: 0) { settingsLink }
        } detail: {
            // A plain trailing pane, not the native inspector. The native one
            // floats over the detail column instead of narrowing it, which
            // hides the right hand table columns.
            HStack(spacing: 0) {
                MainWindow(model: model)
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
        .frame(minWidth: minimumWindowWidth, minHeight: 416)
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

    /// Settings sit at the foot of the sidebar, not in the toolbar.
    private var settingsLink: some View {
        SettingsLink {
            Label("Einstellungen", systemImage: "gearshape")
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    @ViewBuilder private var inspectorPane: some View {
        if let buchung = model.selected {
            Inspector(model: model, buchung: buchung)
                .id(buchung.id)
        } else {
            VStack(spacing: 14) {
                Image("PfennigMark")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 120, height: 120)
                    .opacity(0.4)
                Text("Keine Buchung ausgewählt")
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
