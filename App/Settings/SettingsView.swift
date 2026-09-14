import AI
import AppKit
import Database
import Domain
import SwiftUI

/// Settings. The API key lives in the Keychain; model and reasoning effort
/// live in the `settings` table (spec 10.5).
struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @State private var apiKeyInput = ""
    @State private var hasAPIKey = APIKeyStore.hasKey
    @State private var selectedModel = OpenAIModel.default
    @State private var selectedEffort = ReasoningEffort.default
    @State private var business = BusinessSettingsDraft()
    @State private var savedBusiness = BusinessSettingsDraft()
    @State private var businessWasSaved = false
    @State private var businessError: String?
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

            Section {
                TextField("Name", text: $business.name)
                TextField("Unternehmensname", text: $business.legalName, prompt: Text("optional"))
                Picker("Unternehmensform", selection: $business.businessType) {
                    Text("Freiberufler").tag(BusinessType.freelancer)
                    Text("Einzelunternehmer").tag(BusinessType.soleProprietor)
                }
                TextField("Steuernummer", text: $business.taxNumber, prompt: Text("optional"))
                TextField("USt-IdNr.", text: $business.vatID, prompt: Text("optional"))
                Picker("Umsatzsteuer", selection: $business.vatStatus) {
                    Text("Umsatzsteuerpflichtig").tag(VATStatus.taxable)
                    Text("Kleinunternehmer (§19 UStG)").tag(VATStatus.smallBusiness)
                }
                LabeledContent(
                    "Besteuerung",
                    value: model.profile?.vatAccountingMethod == .accrual
                        ? "Soll-Versteuerung (nicht unterstützt)"
                        : "Ist-Versteuerung"
                )
                if business.vatStatus == .taxable {
                    Picker("UStVA-Zeitraum", selection: $business.ustvaPeriod) {
                        Text("Monatlich").tag(UStVAPeriodicity.monthly)
                        Text("Quartalsweise").tag(UStVAPeriodicity.quarterly)
                        // The stored value stays `yearly`; only the wording changes,
                        // because the setting expresses "no regular Voranmeldungen"
                        // rather than a yearly UStVA (spec ustva-preparation).
                        Text("Keine regelmäßigen Voranmeldungen").tag(UStVAPeriodicity.yearly)
                    }
                    if business.ustvaPeriod != .yearly {
                        Toggle("Dauerfristverlängerung", isOn: $business.dauerfristverlaengerung)
                    }
                }
                HStack {
                    if businessHasChanges {
                        Text("Nicht gesichert").foregroundStyle(.secondary)
                    } else if businessWasSaved {
                        Label("Gesichert", systemImage: "checkmark").foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Änderungen sichern", action: saveBusinessSettings)
                        .disabled(!businessHasChanges || business.trimmedName.isEmpty)
                }
            } header: {
                Text("Betrieb")
            } footer: {
                VStack(alignment: .leading, spacing: 6) {
                    Text(
                        "Änderungen gelten für neue und künftig bearbeitete Buchungen. Bestehende Buchungen werden nicht neu berechnet."
                    )
                    Text(
                        """
                        Pfennig stellt nicht fest, ob und wie oft Sie abgeben müssen. Das legt das Finanzamt fest; \
                        die Angaben hier steuern nur Aufgaben und Fristen in Pfennig. Auch als Kleinunternehmer \
                        erscheint eine UStVA-Aufgabe, wenn Steuer nach §13b UStG entsteht, etwa bei ausländischen \
                        Onlinediensten.
                        """
                    )
                }
            }

            Section("Über Pfennig") {
                LabeledContent("Version", value: AppModel.appVersion)
                Link("Quellcode und Lizenz (GPLv3)", destination: URL(string: "https://github.com/pietz/pfennig")!)
                Text("Freie Software ohne Gewährleistung.")
                    .foregroundStyle(.secondary)
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
                Text("Der Schlüssel wird im Schlüsselbund gespeichert und nur für die Belegerkennung verwendet.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Einstellungen")
        .frame(width: 620, height: 620)
        .alert(
            "Betrieb konnte nicht gespeichert werden",
            isPresented: Binding(
                get: { businessError != nil },
                set: {
                    if !$0 {
                        businessError = nil
                    }
                }
            )
        ) {
            Button("OK") { businessError = nil }
        } message: {
            Text(businessError ?? "Unbekannter Fehler")
        }
        .task {
            loadBusinessSettings()
            loadAISettings()
        }
        .onChange(of: selectedModel) { _, newValue in
            try? model.database?.setSetting(newValue, forKey: AIConfiguration.modelSettingKey)
        }
        .onChange(of: selectedEffort) { _, newValue in
            try? model.database?.setSetting(newValue, forKey: AIConfiguration.reasoningEffortSettingKey)
        }
    }

    private var businessHasChanges: Bool {
        business != savedBusiness
    }

    private func loadBusinessSettings() {
        guard let profile = model.profile else { return }
        var draft = BusinessSettingsDraft(profile)
        draft.dauerfristverlaengerung = UStVAPreferences.dauerfristverlaengerung(in: model.database)
        business = draft
        savedBusiness = draft
    }

    private func saveBusinessSettings() {
        guard let profile = model.profile else { return }
        let updated = business.applying(to: profile)
        guard model.updateProfile(updated) else {
            businessError = model.errorMessage ?? "Die Änderungen konnten nicht gespeichert werden."
            model.errorMessage = nil
            return
        }
        UStVAPreferences.setDauerfristverlaengerung(business.dauerfristverlaengerung, in: model.database)
        var saved = BusinessSettingsDraft(model.profile ?? updated)
        saved.dauerfristverlaengerung = business.dauerfristverlaengerung
        savedBusiness = saved
        business = saved
        businessWasSaved = true
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

private struct BusinessSettingsDraft: Equatable {
    var name = ""
    var legalName = ""
    var taxNumber = ""
    var vatID = ""
    var vatStatus = VATStatus.taxable
    var ustvaPeriod = UStVAPeriodicity.quarterly
    var businessType = BusinessType.freelancer
    /// Not a profile column: stored in the `settings` table under
    /// `UStVAPreferences.dauerfristverlaengerungKey` (spec 10.5).
    var dauerfristverlaengerung = false

    init() {}

    init(_ profile: BusinessProfile) {
        name = profile.name
        legalName = profile.legalName ?? ""
        taxNumber = profile.taxNumber ?? ""
        vatID = profile.vatId ?? ""
        vatStatus = profile.vatStatus
        ustvaPeriod = profile.ustvaPeriod
        businessType = profile.businessType
    }

    var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func applying(to profile: BusinessProfile) -> BusinessProfile {
        var updated = profile
        updated.name = trimmedName
        updated.legalName = optional(legalName)
        updated.taxNumber = optional(taxNumber)
        updated.vatId = optional(vatID)
        updated.vatStatus = vatStatus
        updated.ustvaPeriod = ustvaPeriod
        updated.businessType = businessType
        return updated
    }

    private func optional(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
