import SwiftUI

/// The window has one native workspace: the live bookings ledger.
struct WorkspaceView: View {
    @Bindable var model: AppModel

    var body: some View {
        NavigationSplitView {
            VStack(alignment: .leading, spacing: 0) {
                Text("Pfennig")
                    .font(.headline)
                    .padding(.horizontal, 16)
                    .padding(.top, 10)
                    .padding(.bottom, 8)
                List {
                    Label("Buchungen", systemImage: "list.bullet")
                }
                .listStyle(.sidebar)
            }
            .navigationSplitViewColumnWidth(min: 160, ideal: 160, max: 160)
        } detail: {
            MainWindow(modell: model)
        }
        // Keep the single live observation and inbox lifecycle at window scope.
        .task { await model.observe() }
        .frame(minWidth: 1100, minHeight: 520)
    }
}
