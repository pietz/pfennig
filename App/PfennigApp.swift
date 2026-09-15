import AppKit
import Sparkle
import SwiftUI

@main
struct PfennigApp: App {
    @State private var modell = AppModell()
    private let updaterController: SPUStandardUpdaterController

    init() {
        updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
    }

    var body: some Scene {
        WindowGroup {
            Fenster(modell: modell)
                .modifier(Erscheinung())
        }
        .defaultSize(width: 1100, height: 700)
        .commands {
            CommandGroup(after: .appInfo) {
                AktualisierungsBefehl(updater: updaterController.updater)
            }
        }

        Settings {
            Einstellungen(modell: modell)
                .modifier(Erscheinung())
        }
    }
}

/// The appearance is a preference of the window, not bookkeeping, so it lives
/// in the user defaults and not in `einstellungen`.
enum Erscheinungsbild: String, CaseIterable, Identifiable {
    case system
    case hell
    case dunkel

    var id: String {
        rawValue
    }

    var name: String {
        switch self {
        case .system: "System"
        case .hell: "Hell"
        case .dunkel: "Dunkel"
        }
    }

    /// The whole app, window chrome and toolbar included. A
    /// `preferredColorScheme` only reaches the view tree and leaves the
    /// toolbar behind, which is what made "System" look half dark.
    var aussehen: NSAppearance? {
        switch self {
        case .system: nil
        case .hell: NSAppearance(named: .aqua)
        case .dunkel: NSAppearance(named: .darkAqua)
        }
    }
}

/// Puts the chosen appearance on the application, from whichever window is on
/// screen first.
struct Erscheinung: ViewModifier {
    @AppStorage("erscheinungsbild") private var erscheinungsbild = Erscheinungsbild.system

    func body(content: Content) -> some View {
        content
            .onAppear { NSApp.appearance = erscheinungsbild.aussehen }
            .onChange(of: erscheinungsbild) { NSApp.appearance = erscheinungsbild.aussehen }
    }
}
