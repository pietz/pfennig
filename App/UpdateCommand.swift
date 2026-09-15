import Combine
import Sparkle
import SwiftUI

/// Sparkle's standard command mirrors the updater's native canCheckForUpdates
/// state, including while a check or installation is in progress.
@MainActor
struct UpdateCommand: View {
    private let updater: SPUUpdater
    @State private var canCheck: Bool

    init(updater: SPUUpdater) {
        self.updater = updater
        _canCheck = State(initialValue: updater.canCheckForUpdates)
    }

    var body: some View {
        Button("Nach Updates suchen") {
            updater.checkForUpdates()
        }
        .disabled(!canCheck)
        .onReceive(updater.publisher(for: \.canCheckForUpdates)) { canCheck = $0 }
    }
}
