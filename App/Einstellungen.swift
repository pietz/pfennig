import Agent
import Kern
import SwiftUI

/// The standard settings window. The profile belongs to the bookkeeping and
/// lives in the database, the appearance is a preference of this Mac.
struct Einstellungen: View {
    let modell: AppModell

    var body: some View {
        TabView {
            Tab("Profil", systemImage: "person.text.rectangle") {
                ProfilEinstellungen(modell: modell)
            }
            Tab("KI-Zugang", systemImage: "key") {
                ZugangEinstellungen()
            }
            Tab("Erscheinungsbild", systemImage: "paintpalette") {
                ErscheinungsbildEinstellungen()
            }
        }
        .frame(width: 460, height: 260)
    }
}

private struct ProfilEinstellungen: View {
    let modell: AppModell
    @State private var profil = Profil()

    var body: some View {
        Form {
            TextField("Steuernummer", text: $profil.steuernummer)
            TextField("USt-IdNr.", text: $profil.ustid)
            Toggle("Kleinunternehmer", isOn: $profil.kleinunternehmer)
            Picker("UStVA-Rhythmus", selection: $profil.rhythmus) {
                Text("Monatlich").tag(Rhythmus.monatlich)
                Text("Vierteljährlich").tag(Rhythmus.vierteljaehrlich)
            }
            Toggle("Dauerfristverlängerung", isOn: $profil.dauerfristverlaengerung)
        }
        .formStyle(.grouped)
        .onAppear { profil = modell.profil() }
        .onChange(of: profil) { modell.profilSpeichern(profil) }
    }
}

/// The API key. The stored secret is never read here, only whether the item
/// exists; reading the secret itself is what makes macOS ask, and that belongs
/// to the agent run and not to a window that opens.
private struct ZugangEinstellungen: View {
    @State private var eingabe = ""
    @State private var hinterlegt = false

    var body: some View {
        Form {
            LabeledContent("Status") {
                Label(
                    hinterlegt ? "Schlüssel hinterlegt" : "Kein Schlüssel",
                    systemImage: hinterlegt ? "checkmark.circle.fill" : "exclamationmark.circle"
                )
                .foregroundStyle(hinterlegt ? Color.green : .secondary)
            }
            SecureField("API-Schlüssel", text: $eingabe, prompt: Text("sk-..."))
            HStack {
                Spacer()
                Button("Entfernen", role: .destructive) {
                    Schluesselbund.entfernen()
                    eingabe = ""
                    hinterlegt = false
                }
                .disabled(hinterlegt == false)
                Button("Sichern") {
                    Schluesselbund.schreiben(eingabe.trimmingCharacters(in: .whitespacesAndNewlines))
                    eingabe = ""
                    hinterlegt = Schluesselbund.vorhanden
                }
                .keyboardShortcut(.defaultAction)
                .disabled(eingabe.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            Text("Der Schlüssel liegt im Schlüsselbund dieses Macs und verlässt ihn nur für Anfragen an OpenAI.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
        .onAppear { hinterlegt = Schluesselbund.vorhanden }
    }
}

private struct ErscheinungsbildEinstellungen: View {
    @AppStorage("erscheinungsbild") private var erscheinungsbild = Erscheinungsbild.system

    var body: some View {
        Form {
            Picker("Erscheinungsbild", selection: $erscheinungsbild) {
                ForEach(Erscheinungsbild.allCases) { Text($0.name).tag($0) }
            }
        }
        .formStyle(.grouped)
    }
}
