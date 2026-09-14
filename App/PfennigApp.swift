import SwiftUI

@main
struct PfennigApp: App {
    @State private var modell = AppModell()
    @AppStorage("erscheinungsbild") private var erscheinungsbild = Erscheinungsbild.system

    var body: some Scene {
        WindowGroup {
            Fenster(modell: modell)
                .preferredColorScheme(erscheinungsbild.schema)
        }
        .defaultSize(width: 1100, height: 700)

        Settings {
            Einstellungen(modell: modell)
                .preferredColorScheme(erscheinungsbild.schema)
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

    var schema: ColorScheme? {
        switch self {
        case .system: nil
        case .hell: .light
        case .dunkel: .dark
        }
    }
}
