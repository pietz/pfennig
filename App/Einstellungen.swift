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
                ZugangEinstellungen(modell: modell)
            }
            Tab("Erscheinungsbild", systemImage: "paintpalette") {
                ErscheinungsbildEinstellungen()
            }
        }
        .frame(width: 520, height: 420)
    }
}

private struct ProfilEinstellungen: View {
    let modell: AppModell
    @State private var profil = Profil()

    var body: some View {
        Form {
            TextField("Name", text: $profil.name)
            TextField("Adresse", text: $profil.adresse, axis: .vertical)
                .lineLimit(2 ... 3)
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
    let modell: AppModell
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
            .onSubmit(uebernehmen)
            stand
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
            hinterlegt = Schluesselbund.vorhanden
            ki = modell.kiEinstellungen()
        }
        .onChange(of: ki) { modell.kiEinstellungenSpeichern(ki) }
    }

    /// Whether a key is stored, and what the last check said about it.
    private var stand: some View {
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
    private func uebernehmen() {
        let schluessel = eingabe.trimmingCharacters(in: .whitespacesAndNewlines)
        eingabe = ""
        pruefung = nil
        guard schluessel.isEmpty == false else {
            guard hinterlegt else { return }
            Schluesselbund.entfernen()
            hinterlegt = false
            return
        }
        Schluesselbund.schreiben(schluessel)
        hinterlegt = true
        testen()
    }

    /// One tiny request, so a wrong key shows up here and not on the first
    /// document.
    private func testen() {
        prueft = true
        pruefung = nil
        Task {
            do {
                try await Responses.verbindungPruefen()
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
