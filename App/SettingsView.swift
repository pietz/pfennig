import Agent
import Core
import SwiftUI

/// The standard settings window. The profile belongs to the bookkeeping and
/// lives in the database, the appearance is a preference of this Mac.
struct SettingsView: View {
    let model: AppModel

    var body: some View {
        TabView {
            Tab("Profil", systemImage: "person.text.rectangle") {
                ProfileSettings(model: model)
            }
            Tab("KI-Zugang", systemImage: "key") {
                AISettingsView(model: model)
            }
            Tab("Erscheinungsbild", systemImage: "paintpalette") {
                AppearanceSettings()
            }
        }
        .frame(width: 520, height: 420)
    }
}

private struct ProfileSettings: View {
    let model: AppModel
    @State private var profile = Profil()
    @State private var specialPaymentYear = LocalDate.today().jahr

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
            if profile.kleinunternehmer == false, profile.rhythmus == .monatlich,
               profile.dauerfristverlaengerung
            {
                Section("Sondervorauszahlung") {
                    Picker("Jahr", selection: $specialPaymentYear) {
                        ForEach((LocalDate.today().jahr - 3 ... LocalDate.today().jahr).reversed(), id: \.self) {
                            Text(String($0)).tag($0)
                        }
                    }
                    TextField(
                        "Festgesetzter Betrag",
                        value: specialPaymentAmount(for: specialPaymentYear),
                        format: .euro
                    )
                    .id(specialPaymentYear)
                    Text(
                        "Anrechnung im Dezember, keine Berechnung oder Anmeldung. Andere letzte Meldezeiträume bitte in ELSTER korrigieren."
                    )
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .onAppear { profile = model.profile() }
        .onChange(of: profile) { model.saveProfile(profile) }
    }

    private func specialPaymentAmount(for year: Int) -> Binding<Cent> {
        Binding(
            get: { profile.sondervorauszahlungen[year] ?? .null },
            set: { profile.sondervorauszahlungen[year] = $0 > .null ? $0 : nil }
        )
    }
}

/// The API key. The stored secret is never read here, only whether the item
/// exists; reading the secret itself is what makes macOS ask, and that belongs
/// to the agent run and not to a window that opens.
private struct AISettingsView: View {
    let model: AppModel
    @State private var ki = AISettings()
    @State private var input = ""
    @State private var hasKey = false
    @State private var checkResult: String?
    @State private var isConnected = false
    @State private var isChecking = false

    var body: some View {
        Form {
            SecureField(
                "API-Schlüssel",
                text: $input,
                prompt: Text(hasKey ? "Hinterlegt" : "sk-...")
            )
            .onSubmit(apply)
            state
            Text("Der Schlüssel liegt im Schlüsselbund dieses Macs und verlässt ihn nur für Anfragen an OpenAI.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            Picker("Modell", selection: $ki.model) {
                ForEach(Model.allCases) { Text($0.name).tag($0) }
            }
            Picker("Denkaufwand", selection: $ki.effort) {
                ForEach(ReasoningEffort.allCases) { Text($0.name).tag($0) }
            }
            Toggle("Fast Mode", isOn: $ki.fast)
        }
        .formStyle(.grouped)
        .onAppear {
            hasKey = Keychain.exists
            ki = model.aiSettings()
        }
        .onChange(of: ki) { model.saveAISettings(ki) }
    }

    /// Whether a key is stored, and what the last check said about it.
    private var state: some View {
        HStack(spacing: 6) {
            if isChecking {
                ProgressView().controlSize(.small)
                Text("Verbindung wird geprüft …")
                    .foregroundStyle(.secondary)
            } else if let checkResult {
                Label(checkResult, systemImage: isConnected ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .foregroundStyle(isConnected ? Color.green : Color.red)
                    .lineLimit(3)
            } else {
                Text(hasKey ? "Schlüssel hinterlegt" : "Kein Schlüssel")
                    .foregroundStyle(.secondary)
            }
        }
        .font(.callout)
    }

    /// Committing the field is the whole interaction: a key is stored and
    /// checked at once, an empty field removes the one that is there.
    private func apply() {
        let key = input.trimmingCharacters(in: .whitespacesAndNewlines)
        input = ""
        checkResult = nil
        guard key.isEmpty == false else {
            guard hasKey else { return }
            Keychain.remove()
            hasKey = false
            return
        }
        hasKey = Keychain.write(key)
        guard hasKey else {
            isConnected = false
            checkResult = "Der Schlüssel ließ sich nicht im Schlüsselbund speichern."
            return
        }
        test()
    }

    /// One tiny request, so a wrong key shows up here and not on the first
    /// document.
    private func test() {
        isChecking = true
        checkResult = nil
        Task {
            do {
                try await Responses.testConnection()
                isConnected = true
                checkResult = "Verbindung funktioniert"
            } catch {
                isConnected = false
                checkResult = error.localizedDescription
            }
            isChecking = false
        }
    }
}

private struct AppearanceSettings: View {
    @AppStorage("appearance") private var appearance = Appearance.system

    var body: some View {
        Form {
            Picker("Erscheinungsbild", selection: $appearance) {
                ForEach(Appearance.allCases) { Text($0.name).tag($0) }
            }
        }
        .formStyle(.grouped)
    }
}
