import Database
import Domain
import SwiftUI

/// First launch: describe the business, straight after the archive at its
/// fixed location has been created (spec 20 and 17.1).
struct OnboardingView: View {
    var body: some View {
        VStack(spacing: 24) {
            BusinessProfileForm()
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // Let the content run into the title bar: no toolbar, no divider.
        .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
        .navigationTitle("")
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
                    TextField("Unternehmensname", text: $legalName, prompt: Text("optional"))
                    Picker("Unternehmensform", selection: $businessType) {
                        Text("Freiberufler").tag(BusinessType.freelancer)
                        Text("Einzelunternehmer").tag(BusinessType.soleProprietor)
                    }
                }
                Section {
                    TextField("Steuernummer", text: $taxNumber, prompt: Text("optional"))
                    TextField("USt-IdNr.", text: $vatId, prompt: Text("z. B. DE123456789"))
                    Picker("Umsatzsteuer", selection: $vatStatus) {
                        Text("Umsatzsteuerpflichtig").tag(VATStatus.taxable)
                        Text("Kleinunternehmer (§19 UStG)").tag(VATStatus.smallBusiness)
                    }
                    Picker("Besteuerung", selection: $accountingMethod) {
                        Text("Ist-Versteuerung (§ 20 UStG)").tag(VATAccountingMethod.cash)
                        // Keep a saved future value represented, but never selectable.
                        if accountingMethod != .cash {
                            Text("Gespeicherter Modus – in V1 nicht unterstützt")
                                .tag(accountingMethod)
                                .disabled(true)
                        }
                    }
                    Picker("UStVA-Zeitraum", selection: $ustvaPeriod) {
                        Text("Monatlich").tag(UStVAPeriodicity.monthly)
                        Text("Quartalsweise").tag(UStVAPeriodicity.quarterly)
                        Text("Jährlich").tag(UStVAPeriodicity.yearly)
                    }
                    .disabled(vatStatus == .smallBusiness)
                } footer: {
                    if vatStatus == .smallBusiness {
                        Text(
                            "Kleinunternehmer geben grundsätzlich keine regelmäßige UStVA ab. Sonderfälle wie Reverse Charge werden gesondert behandelt."
                        )
                    } else {
                        Text("Ziffer unterstützt Ist-Versteuerung; Soll-Versteuerung ist noch nicht enthalten.")
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
