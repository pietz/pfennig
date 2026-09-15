import Combine
import Sparkle
import SwiftUI

/// Sparkle's standard command mirrors the updater's native canCheckForUpdates
/// state, including while a check or installation is in progress.
@MainActor
struct UpdateCommand: View {
    private let updater: SPUUpdater
    @State private var kannPruefen: Bool

    init(updater: SPUUpdater) {
        self.updater = updater
        _kannPruefen = State(initialValue: updater.canCheckForUpdates)
    }

    var body: some View {
        Button("Nach Updates suchen") {
            updater.checkForUpdates()
        }
        .disabled(!kannPruefen)
        .onReceive(updater.publisher(for: \.canCheckForUpdates)) { kannPruefen = $0 }
    }
}
