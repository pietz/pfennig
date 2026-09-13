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
struct ZifferApp: App {
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

        Settings {
            SettingsView()
                .environment(model)
                .preferredColorScheme(appearancePreference.colorScheme)
        }
    }
}
