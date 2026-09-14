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
        .onSubmit { modell.profilSpeichern(profil) }
        .onChange(of: profil.kleinunternehmer) { modell.profilSpeichern(profil) }
        .onChange(of: profil.rhythmus) { modell.profilSpeichern(profil) }
        .onChange(of: profil.dauerfristverlaengerung) { modell.profilSpeichern(profil) }
        .onDisappear { modell.profilSpeichern(profil) }
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
