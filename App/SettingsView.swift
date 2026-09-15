import Agent
import Core
import SwiftUI

/// The standard settings window. The profile belongs to the bookkeeping and
/// lives in the database, the appearance is a preference of this Mac.
struct SettingsView: View {
    let modell: AppModel

    var body: some View {
        TabView {
            Tab("Profil", systemImage: "person.text.rectangle") {
                ProfileSettings(modell: modell)
            }
            Tab("KI-Zugang", systemImage: "key") {
                AISettingsView(modell: modell)
            }
            Tab("Erscheinungsbild", systemImage: "paintpalette") {
                AppearanceSettings()
            }
        }
        .frame(width: 520, height: 420)
    }
}

private struct ProfileSettings: View {
    let modell: AppModel
    @State private var profile = Profil()

    var body: some View {
        Form {
            TextField("Name", text: $profile.name)
            TextField("Adresse", text: $profile.adresse, axis: .vertical)
                .lineLimit(2 ... 3)
            TextField("Steuernummer", text: $profile.steuernummer)
            TextField("USt-IdNr.", text: $profile.ustid)
            Toggle("Kleinunternehmer", isOn: $profile.kleinunternehmer)
            Picker("UStVA-Rhythmus", selection: $profile.rhythmus) {
                Text("Monatlich").tag(Rhythmus.monatlich)
                Text("Vierteljährlich").tag(Rhythmus.vierteljaehrlich)
            }
            Toggle("Dauerfristverlängerung", isOn: $profile.dauerfristverlaengerung)
        }
        .formStyle(.grouped)
        .onAppear { profile = modell.profile() }
        .onChange(of: profile) { modell.saveProfile(profile) }
    }
}

/// The API key. The stored secret is never read here, only whether the item
/// exists; reading the secret itself is what makes macOS ask, and that belongs
/// to the agent run and not to a window that opens.
private struct AISettingsView: View {
    let modell: AppModel
    @State private var ki = KiEinstellungen()
    @State private var eingabe = ""
    @State private var hinterlegt = false
    @State private var pruefung: String?
    @State private var verbunden = false
    @State private var prueft = false

    var body: some View {
        Form {
            SecureField(
                "API-Schlüssel",
                text: $eingabe,
                prompt: Text(hinterlegt ? "Hinterlegt" : "sk-...")
            )
            .onSubmit(apply)
            state
            Text("Der Schlüssel liegt im Schlüsselbund dieses Macs und verlässt ihn nur für Anfragen an OpenAI.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            Picker("Modell", selection: $ki.modell) {
                ForEach(Modell.allCases) { Text($0.name).tag($0) }
            }
            Picker("Denkaufwand", selection: $ki.aufwand) {
                ForEach(Denkaufwand.allCases) { Text($0.name).tag($0) }
            }
            Toggle("Fast Mode", isOn: $ki.schnell)
        }
        .formStyle(.grouped)
        .onAppear {
            hinterlegt = Keychain.exists
            ki = modell.aiSettings()
        }
        .onChange(of: ki) { modell.saveAISettings(ki) }
    }

    /// Whether a key is stored, and what the last check said about it.
    private var state: some View {
        HStack(spacing: 6) {
            if prueft {
                ProgressView().controlSize(.small)
                Text("Verbindung wird geprüft …")
                    .foregroundStyle(.secondary)
            } else if let pruefung {
                Label(pruefung, systemImage: verbunden ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .foregroundStyle(verbunden ? Color.green : Color.red)
                    .lineLimit(3)
            } else {
                Text(hinterlegt ? "Schlüssel hinterlegt" : "Kein Schlüssel")
                    .foregroundStyle(.secondary)
            }
        }
        .font(.callout)
    }

    /// Committing the field is the whole interaction: a key is stored and
    /// checked at once, an empty field removes the one that is there.
    private func apply() {
        let key = eingabe.trimmingCharacters(in: .whitespacesAndNewlines)
        eingabe = ""
        pruefung = nil
        guard key.isEmpty == false else {
            guard hinterlegt else { return }
            Keychain.remove()
            hinterlegt = false
            return
        }
        Keychain.write(key)
        hinterlegt = true
        test()
    }

    /// One tiny request, so a wrong key shows up here and not on the first
    /// document.
    private func test() {
        prueft = true
        pruefung = nil
        Task {
            do {
                try await Responses.testConnection()
                verbunden = true
                pruefung = "Verbindung funktioniert"
            } catch {
                verbunden = false
                pruefung = error.localizedDescription
            }
            prueft = false
        }
    }
}

private struct AppearanceSettings: View {
    @AppStorage("erscheinungsbild") private var erscheinungsbild = Appearance.system

    var body: some View {
        Form {
            Picker("Erscheinungsbild", selection: $erscheinungsbild) {
                ForEach(Appearance.allCases) { Text($0.name).tag($0) }
            }
        }
        .formStyle(.grouped)
    }
}
