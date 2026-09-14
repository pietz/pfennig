import SwiftUI

enum AppearancePreference: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    static let storageKey = "appearancePreference"

    var id: String {
        rawValue
    }

    var title: LocalizedStringResource {
        switch self {
        case .system: "System"
        case .light: "Hell"
        case .dark: "Dunkel"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

@main
struct PfennigApp: App {
    @State private var model = AppModel()
    @AppStorage(AppearancePreference.storageKey) private var appearancePreferenceRawValue = AppearancePreference.system
        .rawValue

    private var appearancePreference: AppearancePreference {
        AppearancePreference(rawValue: appearancePreferenceRawValue) ?? .system
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .preferredColorScheme(appearancePreference.colorScheme)
                .frame(minWidth: 700, minHeight: 420)
        }
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }

        // The UStVA task runs next to the ledger, not on top of it: a single
        // window the user can leave open while correcting bookings
        // (spec ustva-preparation.md, "Aufgabe auf Start und Aufgabenfenster").
        Window("UStVA", id: UStVATaskWindow.windowID) {
            UStVATaskWindow()
                .environment(model)
                .preferredColorScheme(appearancePreference.colorScheme)
        }
        .defaultSize(width: 760, height: 620)

        Settings {
            SettingsView()
                .environment(model)
                .preferredColorScheme(appearancePreference.colorScheme)
        }
    }
}
