import SwiftUI

/// The app's deliberately small destinations: the live ledger and two
/// isolated visual comparisons.
struct WorkspaceView: View {
    @Bindable var model: AppModel
    @State private var page = WorkspacePage.bookings

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
            case .bookings:
                MainWindow(modell: model)
            case .designPreview:
                DesignPreview()
                    .id(WorkspacePage.designPreview)
            case .refinedBookings:
                DesignPreview(variant: .refined)
                    .id(WorkspacePage.refinedBookings)
            }
        }
        // Keep the single live observation and inbox lifecycle at window scope;
        // changing the detail page must not restart or duplicate it.
        .task { await model.observe() }
        .frame(minWidth: 1100, minHeight: 520)
    }
}

enum WorkspacePage: CaseIterable, Hashable {
    case bookings
    case designPreview
    case refinedBookings

    var title: String {
        switch self {
        case .bookings: "Buchungen"
        case .designPreview: "Designvorschau"
        case .refinedBookings: "Buchungen · verfeinert"
        }
    }

    var symbol: String {
        switch self {
        case .bookings: "list.bullet"
        case .designPreview: "checkmark.rectangle"
        case .refinedBookings: "list.bullet.rectangle"
        }
    }
}
