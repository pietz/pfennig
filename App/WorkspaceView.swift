import SwiftUI

/// The app's two deliberately small destinations: the live ledger and its
/// isolated visual comparison.
struct WorkspaceView: View {
    @Bindable var modell: AppModel
    @State private var page = WorkspacePage.buchungen

    var body: some View {
        NavigationSplitView {
            List(selection: $page) {
                ForEach(WorkspacePage.allCases, id: \.self) { page in
                    Label(page.title, systemImage: page.symbol)
                        .tag(page)
                }
            }
            .navigationTitle("Pfennig")
            .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 220)
        } detail: {
            switch page {
            case .buchungen:
                MainWindow(modell: modell)
            case .designvorschau:
                DesignPreview()
            }
        }
        // Keep the single live observation and inbox lifecycle at window scope;
        // changing the detail page must not restart or duplicate it.
        .task { await modell.observe() }
        .frame(minWidth: 1100, minHeight: 520)
    }
}

enum WorkspacePage: CaseIterable, Hashable {
    case buchungen
    case designvorschau

    var title: String {
        switch self {
        case .buchungen: "Buchungen"
        case .designvorschau: "Designvorschau"
        }
    }

    var symbol: String {
        switch self {
        case .buchungen: "list.bullet"
        case .designvorschau: "checkmark.rectangle"
        }
    }
}
