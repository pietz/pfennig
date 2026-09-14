import AppKit
import Kern
import PDFKit
import SwiftUI

/// The receipt section of the inspector: the file names behind the hashes and
/// a preview of the first one. The section is missing when the booking has no
/// receipt; an empty section is left out, not collapsed.
struct BelegAbschnitt: View {
    let modell: AppModell
    let buchung: Buchung
    @State private var dateien: [Datei] = []

    var body: some View {
        Section("Beleg") {
            ForEach(dateien, id: \.sha256) { datei in
                HStack {
                    Label(datei.dateiname, systemImage: "doc")
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                    Button("Original öffnen") { NSWorkspace.shared.open(Belegdatei.pfad(datei)) }
                        .buttonStyle(.link)
                }
            }
            if let erste = dateien.first {
                Belegvorschau(datei: erste)
                    .frame(height: 220)
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }
        }
        .onAppear(perform: laden)
        .onChange(of: buchung.belege) { laden() }
    }

    private func laden() {
        dateien = (try? modell.repository.dateien(zu: buchung.belege)) ?? []
    }
}

enum Belegdatei {
    static func pfad(_ datei: Datei) -> URL {
        Archivpfad.archiv.appending(path: "\(datei.sha256).\(datei.endung)")
    }
}

/// A page for PDFs, the picture itself for images.
private struct Belegvorschau: View {
    let datei: Datei

    var body: some View {
        if datei.endung == "pdf" {
            PdfAnsicht(url: Belegdatei.pfad(datei))
        } else if let bild = NSImage(contentsOf: Belegdatei.pfad(datei)) {
            Image(nsImage: bild)
                .resizable()
                .scaledToFit()
        } else {
            ContentUnavailableView("Keine Vorschau", systemImage: "doc.questionmark")
        }
    }
}

private struct PdfAnsicht: NSViewRepresentable {
    let url: URL

    func makeNSView(context _: Context) -> PDFView {
        let ansicht = PDFView()
        ansicht.autoScales = true
        ansicht.displayMode = .singlePage
        ansicht.document = PDFDocument(url: url)
        return ansicht
    }

    func updateNSView(_ ansicht: PDFView, context _: Context) {
        if ansicht.document?.documentURL != url {
            ansicht.document = PDFDocument(url: url)
        }
    }
}
