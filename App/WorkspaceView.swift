import SwiftUI

/// The pages of the window: the overview and the live bookings ledger.
enum Workspace: String, CaseIterable, Identifiable {
    case start
    case buchungen
    case chat

    var id: String {
        rawValue
    }

    var name: String {
        switch self {
        case .start: "Start"
        case .buchungen: "Buchungen"
        case .chat: "Chat"
        }
    }

    var symbol: String {
        switch self {
        case .start: "house"
        case .buchungen: "list.bullet"
        case .chat: "bubble.left.and.bubble.right"
        }
    }
}

struct WorkspaceView: View {
    @Bindable var model: AppModel
    /// The app opens on the overview.
    @State private var workspace: Workspace = .start
    /// True while a drag hangs over the window.
    @State private var isDropTarget = false

    @ViewBuilder private var detail: some View {
        switch workspace {
        case .start:
            StartView(model: model, workspace: $workspace)
        case .buchungen:
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
        case .chat:
            ChatView(model: model)
        }
    }

    var body: some View {
        NavigationSplitView {
            List(Workspace.allCases, selection: $workspace) { item in
                Label(item.name, systemImage: item.symbol).tag(item)
            }
            .listStyle(.sidebar)
            .navigationTitle("Pfennig")
            // A fixed width: the few entries need no more and no less.
            .navigationSplitViewColumnWidth(WorkspaceView.sidebarWidth)
            // The sidebar always stays: there is nothing to reveal by hiding it.
            .toolbar(removing: .sidebarToggle)
            .safeAreaInset(edge: .bottom, spacing: 0) { settingsLink }
        } detail: {
            detail
                .overlay {
                    if isDropTarget {
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(Color.accentColor, lineWidth: 3)
                            .padding(3)
                            .allowsHitTesting(false)
                    }
                }
        }
        // Drag and drop counts for the whole window, on Start as well.
        .dropDestination(for: URL.self) { urls, _ in
            model.acceptFiles(urls)
            return true
        } isTargeted: { isDropTarget = $0 }
        // Export is reachable from both pages, so the sheet sits at window scope.
        .sheet(isPresented: $model.exportVisible) {
            ExportSheet(model: model, preselected: model.exportPeriod)
        }
        // Keep the single live observation and inbox lifecycle at window scope.
        .task { await model.observe() }
        // The window is never narrower than the parts the current page shows.
        .frame(minWidth: minimumWindowWidth, minHeight: 416)
    }

    /// The fixed sidebar width, the fixed inspector width, the smallest table
    /// width the columns need and the smallest width the two start columns need.
    static let sidebarWidth: CGFloat = 160
    static let inspectorWidth: CGFloat = 280
    static let tableMinimumWidth: CGFloat = 560
    static let startMinimumWidth: CGFloat = 640

    static let defaultWidth = sidebarWidth + tableMinimumWidth + inspectorWidth + 1

    private var minimumWindowWidth: CGFloat {
        switch workspace {
        case .start, .chat:
            Self.sidebarWidth + Self.startMinimumWidth
        case .buchungen:
            model.inspectorVisible ? Self.defaultWidth : Self.sidebarWidth + Self.tableMinimumWidth
        }
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
        } else if model.selection.isEmpty == false {
            Text("\(model.selection.count) Buchungen ausgewählt")
                .font(.body)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
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
