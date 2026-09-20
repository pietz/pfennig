import AppKit
import Sparkle
import SwiftUI

/// Receives Finder and Launch Services document-open events. AppKit may send
/// them before the SwiftUI window exists, so early files wait for its model.
@MainActor
final class ApplicationDelegate: NSObject, NSApplicationDelegate {
    private var model: AppModel?
    private var pendingFiles: [URL] = []

    func connect(to model: AppModel) {
        self.model = model
        guard pendingFiles.isEmpty == false else { return }
        model.acceptFiles(pendingFiles)
        pendingFiles = []
    }

    func application(_ sender: NSApplication, openFiles filenames: [String]) {
        let files = filenames.map { URL(filePath: $0) }
        if let model {
            model.acceptFiles(files)
        } else {
            pendingFiles.append(contentsOf: files)
        }
        sender.reply(toOpenOrPrint: .success)
    }
}

@main
struct PfennigApp: App {
    @NSApplicationDelegateAdaptor(ApplicationDelegate.self) private var applicationDelegate
    @State private var model: AppModel
    private let updaterController: SPUStandardUpdaterController

    init() {
        let model = AppModel()
        _model = State(initialValue: model)
        updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        applicationDelegate.connect(to: model)
    }

    var body: some Scene {
        WindowGroup {
            WorkspaceView(model: model)
                .modifier(AppearanceModifier())
        }
        .defaultSize(width: 840, height: 500)
        .commands {
            CommandGroup(after: .appInfo) {
                UpdateCommand(updater: updaterController.updater)
            }
        }

        Settings {
            SettingsView(model: model)
                .modifier(AppearanceModifier())
        }
    }
}

/// The appearance is a preference of the window, not bookkeeping, so it lives
/// in the user defaults and not in `einstellungen`.
enum Appearance: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String {
        rawValue
    }

    var name: String {
        switch self {
        case .system: "System"
        case .light: "Hell"
        case .dark: "Dunkel"
        }
    }

    /// The whole app, window chrome and toolbar included. A
    /// `preferredColorScheme` only reaches the view tree and leaves the
    /// toolbar behind, which is what made "System" look half dark.
    var nsAppearance: NSAppearance? {
        switch self {
        case .system: nil
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        }
    }
}

/// Puts the chosen appearance on the application, from whichever window is on
/// screen first.
struct AppearanceModifier: ViewModifier {
    @AppStorage("appearance") private var appearance = Appearance.system

    func body(content: Content) -> some View {
        content
            .onAppear { NSApp.appearance = appearance.nsAppearance }
            .onChange(of: appearance) { NSApp.appearance = appearance.nsAppearance }
    }
}
