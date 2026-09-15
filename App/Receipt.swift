import AppKit
import Core
import PDFKit
import SwiftUI

/// The receipt section of the inspector: a preview of the first file, the
/// names of all of them and three actions per file. The section is missing
/// when the booking has no receipt; an empty section is left out, not
/// collapsed.
struct ReceiptSection: View {
    let model: AppModel
    let buchung: Buchung
    @State private var files: [Datei] = []
    @State private var gross: Datei?

    var body: some View {
        Section("Beleg") {
            if let first = files.first {
                ReceiptPreview(url: model.path.original(first))
                    .frame(height: 220)
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            ForEach(files, id: \.sha256) { file in
                HStack(spacing: 4) {
                    Text(file.dateiname)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                    Button("Vorschau", systemImage: "eye") { gross = file }
                    Button("Original öffnen", systemImage: "arrow.up.forward.square") {
                        NSWorkspace.shared.open(model.path.original(file))
                    }
                    Button("Vom Beleg nehmen", systemImage: "xmark") {
                        guard let id = buchung.id else { return }
                        model.removeReceipt(file.sha256, from: id)
                    }
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
            }
        }
        .onAppear(perform: load)
        .onChange(of: buchung.belege) { load() }
        .sheet(item: $gross) { file in
            VStack(spacing: 0) {
                ReceiptPreview(url: model.path.original(file))
                Divider()
                HStack {
                    Text(file.dateiname).foregroundStyle(.secondary)
                    Spacer()
                    Button("Fertig") { gross = nil }
                        .keyboardShortcut(.defaultAction)
                }
                .padding(12)
            }
            .frame(width: 720, height: 800)
        }
    }

    private func load() {
        files = (try? model.repository.files(for: buchung.belege)) ?? []
    }
}

/// A page for PDFs, the picture itself for images.
private struct ReceiptPreview: View {
    let url: URL

    var body: some View {
        if url.pathExtension == "pdf" {
            PDFPreview(url: url)
        } else if let bild = NSImage(contentsOf: url) {
            Image(nsImage: bild)
                .resizable()
                .scaledToFit()
        } else {
            ContentUnavailableView("Keine Vorschau", systemImage: "doc.questionmark")
        }
    }
}

private struct PDFPreview: NSViewRepresentable {
    let url: URL

    func makeNSView(context _: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePage
        view.document = PDFDocument(url: url)
        return view
    }

    func updateNSView(_ view: PDFView, context _: Context) {
        if view.document?.documentURL != url {
            view.document = PDFDocument(url: url)
        }
    }
}
