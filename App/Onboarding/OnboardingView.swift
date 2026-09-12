import AppKit
import Database
import Domain
import SwiftUI

/// First launch: choose or create an archive folder, then describe the
/// business (spec 20 and 17.1).
struct OnboardingView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 24) {
            switch model.stage {
            case .welcome:
                welcome
            case .profile:
                BusinessProfileForm()
            case .ready:
                EmptyView()
            }
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // Let the content run into the title bar: no toolbar, no divider.
        .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
        .navigationTitle("")
    }

    private var welcome: some View {
        VStack(spacing: 20) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.largeTitle)
                .foregroundStyle(.tint)
            VStack(spacing: 6) {
                Text("Willkommen bei Ziffer")
                    .font(.largeTitle.weight(.semibold))
                Text("Buchhaltung für Selbstständige. Alle Daten bleiben in einem Ordner auf diesem Mac.")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            HStack {
                Button("Archiv öffnen …", action: openArchive)
                Button("Archiv erstellen …", action: createArchive)
                    .buttonStyle(.borderedProminent)
            }
        }
        .frame(maxWidth: 460)
    }

    private func createArchive() {
        let panel = NSSavePanel()
        panel.title = String(localized: "Neues Ziffer-Archiv")
        panel.prompt = String(localized: "Erstellen")
        panel.nameFieldStringValue = "Ziffer"
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        model.createArchive(at: url)
    }

    private func openArchive() {
        let panel = NSOpenPanel()
        panel.title = String(localized: "Ziffer-Archiv öffnen")
        panel.prompt = String(localized: "Öffnen")
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        model.openArchive(at: url)
    }
}

/// The single business profile of V1.
struct BusinessProfileForm: View {
    @Environment(AppModel.self) private var model

    @State private var name = ""
    @State private var legalName = ""
    @State private var taxNumber = ""
    @State private var vatId = ""
    @State private var vatStatus: VATStatus = .taxable
    @State private var accountingMethod: VATAccountingMethod = .cash
    @State private var ustvaPeriod: UStVAPeriodicity = .quarterly
    @State private var businessType: BusinessType = .freelancer

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Betrieb einrichten").font(.title2.weight(.semibold))
                Text(
                    "Diese Angaben bestimmen, wie Ziffer Umsatzsteuer und Fristen berechnet. Sie lassen sich später ändern."
                )
                .foregroundStyle(.secondary)
            }
            Form {
                Section {
                    TextField("Name", text: $name, prompt: Text("Vor- und Nachname oder Firma"))
                    TextField("Rechtlicher Name", text: $legalName, prompt: Text("optional"))
                    Picker("Betriebsart", selection: $businessType) {
                        Text("Freiberuflich").tag(BusinessType.freelancer)
                        Text("Einzelunternehmen").tag(BusinessType.soleProprietor)
                    }
                }
                Section {
                    TextField("Steuernummer", text: $taxNumber, prompt: Text("optional"))
                    TextField("USt-IdNr.", text: $vatId, prompt: Text("z. B. DE123456789"))
                    Picker("Umsatzsteuer", selection: $vatStatus) {
                        Text("Regelbesteuert").tag(VATStatus.taxable)
                        Text("Kleinunternehmer (§ 19 UStG)").tag(VATStatus.smallBusiness)
                    }
                    Picker("Versteuerung", selection: $accountingMethod) {
                        Text("Ist-Versteuerung (§ 20 UStG)").tag(VATAccountingMethod.cash)
                        Text("Soll-Versteuerung").tag(VATAccountingMethod.accrual)
                    }
                    Picker("Voranmeldung", selection: $ustvaPeriod) {
                        Text("Monatlich").tag(UStVAPeriodicity.monthly)
                        Text("Vierteljährlich").tag(UStVAPeriodicity.quarterly)
                        Text("Jährlich").tag(UStVAPeriodicity.yearly)
                    }
                }
            }
            .formStyle(.grouped)
            HStack {
                if let archive = model.archive {
                    Label(archive.rootURL.path(percentEncoded: false), systemImage: "folder")
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer()
                Button("Fertig", action: save)
                    .buttonStyle(.borderedProminent)
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .frame(maxWidth: 560)
    }

    private func save() {
        model.saveProfile(
            BusinessProfile(
                name: name.trimmingCharacters(in: .whitespaces),
                legalName: legalName.isEmpty ? nil : legalName,
                taxNumber: taxNumber.isEmpty ? nil : taxNumber,
                vatId: vatId.isEmpty ? nil : vatId,
                vatStatus: vatStatus,
                vatAccountingMethod: accountingMethod,
                ustvaPeriod: ustvaPeriod,
                businessType: businessType
            )
        )
    }
}
