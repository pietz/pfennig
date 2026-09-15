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
            .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 220)
        } detail: {
            MainWindow(modell: model)
        }
        // Keep the single live observation and inbox lifecycle at window scope.
        .task { await model.observe() }
        .frame(minWidth: 1100, minHeight: 520)
    }
}
