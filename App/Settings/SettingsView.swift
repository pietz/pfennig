import AI
import AppKit
import SwiftUI

/// Settings. The API key lives in the Keychain; model and reasoning effort
/// live in the `settings` table. The OpenAI client itself arrives with
/// milestone M4 (spec 10.5).
struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @State private var apiKeyInput = ""
    @State private var hasAPIKey = APIKeyStore.hasKey
    @State private var selectedModel = OpenAIModel.default
    @State private var selectedEffort = ReasoningEffort.default
    @AppStorage(AppearancePreference.storageKey) private var appearancePreferenceRawValue = AppearancePreference.system
        .rawValue

    var body: some View {
        Form {
            Section("Darstellung") {
                Picker("Erscheinungsbild", selection: $appearancePreferenceRawValue) {
                    ForEach(AppearancePreference.allCases) { preference in
                        Text(preference.title)
                            .tag(preference.rawValue)
                    }
                }
            }

            Section("Archiv") {
                LabeledContent("Ordner") {
                    Text(model.archive?.rootURL.path(percentEncoded: false) ?? "–")
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Button("Im Finder zeigen") {
                    if let url = model.archive?.rootURL {
                        NSWorkspace.shared.activateFileViewerSelecting([url])
                    }
                }
                .disabled(model.archive == nil)
            }

            Section("Betrieb") {
                LabeledContent("Name", value: model.profile?.name ?? "–")
                LabeledContent("USt-IdNr.", value: model.profile?.vatId ?? "–")
            }

            Section {
                SecureField("OpenAI API-Schlüssel", text: $apiKeyInput, prompt: Text("sk-…"))
                    .onSubmit(saveAPIKey)
                HStack {
                    Text(hasAPIKey ? "Schlüssel gespeichert" : "Kein Schlüssel hinterlegt")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Entfernen", role: .destructive, action: removeAPIKey)
                        .disabled(!hasAPIKey)
                }
                Picker("Modell", selection: $selectedModel) {
                    ForEach(OpenAIModel.allCases, id: \.self) { model in
                        Text(model.displayName).tag(model)
                    }
                }
                Picker("Denkaufwand", selection: $selectedEffort) {
                    ForEach(ReasoningEffort.allCases, id: \.self) { effort in
                        Text(effort.displayName).tag(effort)
                    }
                }
            } header: {
                Text("KI")
            } footer: {
                Text(
                    "Der Schlüssel wird im Schlüsselbund gespeichert. Ab Meilenstein M4 wird er für die Belegerkennung verwendet."
                )
                .font(.callout)
                .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Einstellungen")
        .frame(width: 620, height: 560)
        .task { loadAISettings() }
        .onChange(of: selectedModel) { _, newValue in
            try? model.database?.setSetting(newValue, forKey: AIConfiguration.modelSettingKey)
        }
        .onChange(of: selectedEffort) { _, newValue in
            try? model.database?.setSetting(newValue, forKey: AIConfiguration.reasoningEffortSettingKey)
        }
    }

    private func loadAISettings() {
        guard let database = model.database else { return }
        selectedModel = (try? database.setting(OpenAIModel.self, forKey: AIConfiguration.modelSettingKey))
            ?? .default
        selectedEffort = (try? database.setting(
            ReasoningEffort.self,
            forKey: AIConfiguration.reasoningEffortSettingKey
        ))
            ?? .default
    }

    private func saveAPIKey() {
        let trimmed = apiKeyInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        APIKeyStore.save(trimmed)
        apiKeyInput = ""
        hasAPIKey = true
    }

    private func removeAPIKey() {
        APIKeyStore.remove()
        apiKeyInput = ""
        hasAPIKey = false
    }
}
