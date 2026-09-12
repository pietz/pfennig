import AppKit
import SwiftUI

/// Settings. The API key field is a placeholder until the Keychain and the
/// OpenAI client arrive with milestone M4 (spec 10.5).
struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @AppStorage("ai.model") private var selectedModel = "gpt-5"
    @State private var apiKey = ""

    var body: some View {
        Form {
            Section("Archiv") {
                LabeledContent("Ordner") {
                    Text(model.archive?.rootURL.path(percentEncoded: false) ?? "–")
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                HStack {
                    Button("Im Finder zeigen") {
                        if let url = model.archive?.rootURL {
                            NSWorkspace.shared.activateFileViewerSelecting([url])
                        }
                    }
                    .disabled(model.archive == nil)
                    Spacer()
                    Button("Archiv wechseln …", action: model.closeArchive)
                }
            }

            Section("Betrieb") {
                LabeledContent("Name", value: model.profile?.name ?? "–")
                LabeledContent("USt-IdNr.", value: model.profile?.vatId ?? "–")
            }

            Section {
                SecureField("API-Schlüssel", text: $apiKey, prompt: Text("sk-…"))
                    .disabled(true)
                Picker("Modell", selection: $selectedModel) {
                    Text("GPT-5").tag("gpt-5")
                    Text("GPT-5 mini").tag("gpt-5-mini")
                }
            } header: {
                Text("Künstliche Intelligenz")
            } footer: {
                Text(
                    "Noch ohne Funktion. Ab Meilenstein M4 wird der Schlüssel im Schlüsselbund gespeichert und für die Belegerkennung verwendet."
                )
                .font(.callout)
                .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Einstellungen")
    }
}
