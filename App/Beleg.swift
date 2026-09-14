import AppKit
import Kern
import PDFKit
import SwiftUI

/// The receipt section of the inspector: a preview of the first file, the
/// names of all of them and three actions per file. The section is missing
/// when the booking has no receipt; an empty section is left out, not
/// collapsed.
struct BelegAbschnitt: View {
    let modell: AppModell
    let buchung: Buchung
    @State private var dateien: [Datei] = []
    @State private var gross: Datei?

    var body: some View {
        Section("Beleg") {
            if let erste = dateien.first {
                Belegvorschau(url: modell.pfad.original(erste))
                    .frame(height: 220)
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            ForEach(dateien, id: \.sha256) { datei in
                HStack(spacing: 4) {
                    Text(datei.dateiname)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                    Button("Vorschau", systemImage: "eye") { gross = datei }
                    Button("Original öffnen", systemImage: "arrow.up.forward.square") {
                        NSWorkspace.shared.open(modell.pfad.original(datei))
                    }
                    Button("Vom Beleg nehmen", systemImage: "xmark") {
                        guard let id = buchung.id else { return }
                        modell.belegEntfernen(datei.sha256, von: id)
                    }
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
            }
        }
        .onAppear(perform: laden)
        .onChange(of: buchung.belege) { laden() }
        .sheet(item: $gross) { datei in
            VStack(spacing: 0) {
                Belegvorschau(url: modell.pfad.original(datei))
                Divider()
                HStack {
                    Text(datei.dateiname).foregroundStyle(.secondary)
                    Spacer()
                    Button("Fertig") { gross = nil }
                        .keyboardShortcut(.defaultAction)
                }
                .padding(12)
            }
            .frame(width: 720, height: 800)
        }
    }

    private func laden() {
        dateien = (try? modell.repository.dateien(zu: buchung.belege)) ?? []
    }
}

/// A page for PDFs, the picture itself for images.
private struct Belegvorschau: View {
    let url: URL

    var body: some View {
        if url.pathExtension == "pdf" {
            PdfAnsicht(url: url)
        } else if let bild = NSImage(contentsOf: url) {
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
