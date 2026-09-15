import Core
import SwiftUI

/// A native-only comparison page. These rows are intentionally local and never
/// cross into AppModel, Repository, or the persisted bookkeeping data.
enum DesignPreviewVariant: Equatable {
    case original
    case refined
}

struct DesignPreview: View {
    private let variant: DesignPreviewVariant
    @State private var bookings = PreviewBooking.samples
    @State private var direction = PreviewDirectionFilter.alle
    @State private var review = PreviewReviewFilter.alle
    @State private var search = ""
    @State private var selection: Int?
    @State private var inspectorVisible = true
    @State private var sortOrder = [KeyPathComparator(\PreviewBooking.date, order: .reverse)]

    init(variant: DesignPreviewVariant = .original) {
        self.variant = variant
    }

    private var visibleBookings: [PreviewBooking] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return bookings
            .filter { booking in
                direction.includes(booking) && review.includes(booking)
            }
            .filter { booking in
                guard query.isEmpty == false else { return true }
                return [booking.company, booking.title, booking.category]
                    .contains { $0.lowercased().contains(query) }
            }
            .sorted(using: sortOrder)
    }

    private var income: Cent {
        visibleBookings
            .filter { $0.direction == .income }
            .reduce(.null) { $0 + $1.amount }
    }

    private var expenses: Cent {
        visibleBookings
            .filter { $0.direction == .expense }
            .reduce(.null) { $0 + $1.amount }
    }

    private var selectedBooking: PreviewBooking? {
        guard let selection else { return nil }
        return bookings.first { $0.id == selection }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text(variant == .refined ? "Buchungen · verfeinert · Beispieldaten" : "Designvorschau · Beispieldaten")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(countLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            .padding(.horizontal, 18)
            .padding(.top, 16)
            .padding(.bottom, 8)

            HStack(spacing: 12) {
                Picker("Prüfung", selection: $review) {
                    ForEach(PreviewReviewFilter.allCases, id: \.self) { filter in
                        Text(filter.title).tag(filter)
                    }
                }
                .pickerStyle(.segmented)
                .fixedSize()
                Spacer()
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 8)

            Table(visibleBookings, selection: $selection, sortOrder: $sortOrder) {
                TableColumn("Firma", value: \.company) { booking in
                    HStack(spacing: variant == .refined ? 8 : 10) {
                        if variant == .original {
                            Image(systemName: booking.icon)
                                .foregroundStyle(.secondary)
                                .frame(width: 30, height: 30)
                                .background(.quaternary, in: RoundedRectangle(cornerRadius: 7))
                        } else {
                            Image(systemName: booking.icon)
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(.secondary)
                                .frame(width: 22, height: 22)
                        }
                        VStack(alignment: .leading, spacing: 1) {
                            Text(booking.company)
                                .fontWeight(.semibold)
                                .lineLimit(1)
                            Text(booking.title)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(minHeight: variant == .refined ? 40 : 56, alignment: .leading)
                }
                .width(min: 190, ideal: 270)

                TableColumn("Datum", value: \.date) { booking in
                    Text(booking.date.formatted)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .frame(minHeight: variant == .refined ? 40 : 56, alignment: .leading)
                }
                .width(90)

                TableColumn("Betrag", value: \.signedAmount) { booking in
                    Group {
                        if variant == .refined {
                            Text(booking.signedAmount.formatted)
                                .foregroundStyle(booking.direction == .income ? Color.green : Color.primary)
                        } else {
                            Text(booking.signedAmount.formatted)
                                .foregroundStyle(booking.direction == .income ? .primary : .secondary)
                        }
                    }
                    .monospacedDigit()
                    .frame(maxWidth: .infinity, minHeight: variant == .refined ? 40 : 56, alignment: .trailing)
                }
                .width(min: 100, ideal: 115)
                .alignment(.trailing)

                TableColumn("Bezahlt") { booking in
                    PreviewPaymentLabel(payment: booking.payment)
                        .frame(minHeight: variant == .refined ? 40 : 56, alignment: .leading)
                }
                .width(min: 100, ideal: 115)

                TableColumn("Status") { booking in
                    PreviewStatusLabel(status: booking.status, quiet: variant == .refined)
                        .frame(minHeight: variant == .refined ? 40 : 56, alignment: .leading)
                }
                .width(min: 100, ideal: 115)
            }
            .padding(.horizontal, variant == .refined ? 0 : 18)

            Divider()
            HStack(spacing: 24) {
                Spacer()
                summary("Einnahmen", income)
                summary("Ausgaben", expenses)
                summary("Saldo", income - expenses)
            }
            .font(.callout)
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
        }
        .searchable(text: $search, prompt: "Suchen")
        .toolbar { toolbar }
        .inspector(isPresented: $inspectorVisible) {
            PreviewInspector(booking: selectedBooking, confirm: confirmSelection)
                .inspectorColumnWidth(min: 280, ideal: 340, max: 460)
        }
        .onChange(of: visibleBookings.map(\.id)) { _, ids in
            guard let selection, ids.contains(selection) == false else { return }
            self.selection = ids.first
        }
        .onAppear {
            if selection == nil {
                selection = visibleBookings.first?.id
            }
        }
    }

    private var countLabel: String {
        "\(visibleBookings.count) \(visibleBookings.count == 1 ? "Buchung" : "Buchungen")"
    }

    private func summary(_ title: String, _ amount: Cent) -> some View {
        HStack(spacing: 6) {
            Text(title).foregroundStyle(.secondary)
            Text(amount.formatted).monospacedDigit()
        }
    }

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Picker("Richtung", selection: $direction) {
                ForEach(PreviewDirectionFilter.allCases, id: \.self) { filter in
                    Text(filter.title).tag(filter)
                }
            }
            .pickerStyle(.segmented)
            .fixedSize()
        }
        ToolbarItem(placement: .primaryAction) {
            Button("Inspector", systemImage: "sidebar.trailing") {
                inspectorVisible.toggle()
            }
        }
    }

    private func confirmSelection() {
        guard let selection,
              let index = bookings.firstIndex(where: { $0.id == selection }),
              bookings[index].status == .zuPruefen
        else { return }
        bookings[index].status = .geprueft
    }
}

private struct PreviewInspector: View {
    let booking: PreviewBooking?
    let confirm: () -> Void

    var body: some View {
        Form {
            if let booking {
                Section("Beleg") {
                    HStack(spacing: 10) {
                        Image(systemName: "doc.text")
                            .font(.title2)
                            .foregroundStyle(.secondary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(booking.receipt ?? "Kein Beleg")
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Text(booking
                                .receipt == nil ? "Für diese Beispieldaten nicht vorhanden" : "Fiktive Belegangaben")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    LabeledContent("Rechnungsnummer", value: booking.receiptNumber)
                    LabeledContent("Belegdatum", value: booking.date.formatted)
                }

                Section("Grunddaten") {
                    LabeledContent("Firma", value: booking.company)
                    LabeledContent("Titel", value: booking.title)
                    LabeledContent("Kategorie", value: booking.category)
                    LabeledContent("Datum", value: booking.date.formatted)
                    LabeledContent("Betrag", value: booking.signedAmount.formatted)
                    LabeledContent("Richtung", value: booking.direction.title)
                }

                Section("Zahlung und Prüfung") {
                    LabeledContent("Zahlungsstand", value: booking.payment.title)
                    PreviewStatusLabel(status: booking.status)
                    if booking.status != .geprueft {
                        Button("Bestätigen", systemImage: "checkmark") {
                            confirm()
                        }
                        .disabled(booking.status == .belegFehlt)
                        if booking.status == .belegFehlt {
                            Text("Ohne Beleg nicht bestätigbar")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Section("Steuer") {
                    LabeledContent("Behandlung", value: "Inland")
                    LabeledContent("Steuersatz", value: booking.taxRate)
                }

                if let note = booking.note {
                    Section("Notizen") {
                        Text(note)
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
                ContentUnavailableView("Keine Buchung ausgewählt", systemImage: "list.bullet.rectangle")
            }
        }
        .formStyle(.grouped)
    }
}

private struct PreviewPaymentLabel: View {
    let payment: PreviewPayment

    var body: some View {
        Label(payment.title, systemImage: payment.symbol)
            .foregroundStyle(.secondary)
            .lineLimit(1)
    }
}

private struct PreviewStatusLabel: View {
    let status: PreviewReviewStatus
    var quiet = false

    var body: some View {
        if quiet {
            label
        } else {
            label
                .padding(.horizontal, 7)
                .padding(.vertical, 4)
                .background(status.color.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
        }
    }

    private var label: some View {
        Label(status.title, systemImage: status.symbol)
            .foregroundStyle(.primary)
            .labelStyle(StatusLabelStyle(color: status.color))
            .lineLimit(1)
    }
}

private struct StatusLabelStyle: LabelStyle {
    let color: Color

    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 5) {
            configuration.icon.foregroundStyle(color)
            configuration.title.foregroundStyle(.primary)
        }
    }
}

private struct PreviewBooking: Identifiable, Hashable {
    let id: Int
    let direction: PreviewDirection
    let icon: String
    let company: String
    let title: String
    let date: LocalDate
    let amount: Cent
    let payment: PreviewPayment
    var status: PreviewReviewStatus
    let receipt: String?
    let receiptNumber: String
    let category: String
    let taxRate: String
    let note: String?

    var signedAmount: Cent {
        direction == .income ? amount : -amount
    }

    static let samples: [PreviewBooking] = [
        PreviewBooking(
            id: 1, direction: .expense, icon: "desktopcomputer", company: "Nordlicht Bürobedarf",
            title: "Monitor und Dockingstation", date: LocalDate(jahr: 2026, monat: 6, tag: 12), amount: Cent(42800),
            payment: .paid, status: .zuPruefen, receipt: "Rechnung_Nordlicht.pdf", receiptNumber: "NB-2026-0612",
            category: "Bürobedarf", taxRate: "19 %", note: "Beleg vorhanden, Zuordnung bitte prüfen."
        ),
        PreviewBooking(
            id: 2, direction: .expense, icon: "cloud", company: "Wolkenwerk Hosting",
            title: "Server und Speicher · Juni", date: LocalDate(jahr: 2026, monat: 6, tag: 8), amount: Cent(5980),
            payment: .paid, status: .geprueft, receipt: "Wolkenwerk_06.pdf", receiptNumber: "WW-0608",
            category: "Telefon / Internet", taxRate: "19 %", note: nil
        ),
        PreviewBooking(
            id: 3, direction: .income, icon: "building.2", company: "Klarraum Studio",
            title: "Projektphase 2 · Interface", date: LocalDate(jahr: 2026, monat: 6, tag: 3), amount: Cent(245_000),
            payment: .open, status: .geprueft, receipt: "Rechnung_Klarraum.pdf", receiptNumber: "KS-2026-02",
            category: "Betriebseinnahmen", taxRate: "19 %", note: nil
        ),
        PreviewBooking(
            id: 4, direction: .expense, icon: "airplane", company: "Hafenblick Bahn",
            title: "Fahrt zum Kundentermin", date: LocalDate(jahr: 2026, monat: 5, tag: 29), amount: Cent(8740),
            payment: .paid, status: .geprueft, receipt: "Bahn_2905.pdf", receiptNumber: "HB-0529",
            category: "Reisekosten", taxRate: "19 %", note: nil
        ),
        PreviewBooking(
            id: 5, direction: .expense, icon: "fork.knife", company: "Tisch 17",
            title: "Arbeitsessen mit Kundin", date: LocalDate(jahr: 2026, monat: 5, tag: 24), amount: Cent(6720),
            payment: .partial, status: .belegFehlt, receipt: nil, receiptNumber: "Nicht vorhanden",
            category: "Bewirtung", taxRate: "19 %", note: "Originalbeleg fehlt."
        ),
        PreviewBooking(
            id: 6, direction: .income, icon: "book.closed", company: "Atelier Hain",
            title: "Workshop · Mai", date: LocalDate(jahr: 2026, monat: 5, tag: 18), amount: Cent(98000),
            payment: .paid, status: .zuPruefen, receipt: "Atelier_Hain.pdf", receiptNumber: "AH-0518",
            category: "Betriebseinnahmen", taxRate: "19 %", note: nil
        ),
        PreviewBooking(
            id: 7, direction: .expense, icon: "phone", company: "Funkfeld Mobil",
            title: "Mobilfunk · Mai", date: LocalDate(jahr: 2026, monat: 5, tag: 11), amount: Cent(2990),
            payment: .paid, status: .geprueft, receipt: "Funkfeld_Mai.pdf", receiptNumber: "FM-0511",
            category: "Telefon / Internet", taxRate: "19 %", note: nil
        ),
        PreviewBooking(
            id: 8, direction: .expense, icon: "tshirt", company: "Leinen & Form",
            title: "Arbeitskleidung", date: LocalDate(jahr: 2026, monat: 5, tag: 2), amount: Cent(11900),
            payment: .open, status: .zuPruefen, receipt: "Leinen_Form.pdf", receiptNumber: "LF-0502",
            category: "Arbeitsmittel", taxRate: "19 %", note: nil
        ),
        PreviewBooking(
            id: 9, direction: .expense, icon: "wrench.and.screwdriver", company: "Werkraum Service",
            title: "Reparatur Werkzeug", date: LocalDate(jahr: 2026, monat: 4, tag: 26), amount: Cent(18600),
            payment: .paid, status: .geprueft, receipt: "Werkraum_Repair.pdf", receiptNumber: "WS-0426",
            category: "Arbeitsmittel", taxRate: "19 %", note: nil
        ),
        PreviewBooking(
            id: 10, direction: .income, icon: "building.2", company: "Studio Morgen",
            title: "Konzeption und Beratung", date: LocalDate(jahr: 2026, monat: 4, tag: 14), amount: Cent(165_000),
            payment: .paid, status: .geprueft, receipt: "Studio_Morgen.pdf", receiptNumber: "SM-0414",
            category: "Betriebseinnahmen", taxRate: "19 %", note: nil
        )
    ]
}

private enum PreviewDirection {
    case income
    case expense

    var title: String {
        switch self {
        case .income: "Einnahme"
        case .expense: "Ausgabe"
        }
    }
}

private enum PreviewDirectionFilter: CaseIterable, Hashable {
    case alle
    case einnahmen
    case ausgaben

    var title: String {
        switch self {
        case .alle: "Alle"
        case .einnahmen: "Einnahmen"
        case .ausgaben: "Ausgaben"
        }
    }

    func includes(_ booking: PreviewBooking) -> Bool {
        switch self {
        case .alle: true
        case .einnahmen: booking.direction == .income
        case .ausgaben: booking.direction == .expense
        }
    }
}

private enum PreviewReviewFilter: CaseIterable, Hashable {
    case alle
    case zuPruefen
    case ohneBeleg

    var title: String {
        switch self {
        case .alle: "Alle"
        case .zuPruefen: "Zu prüfen"
        case .ohneBeleg: "Ohne Beleg"
        }
    }

    func includes(_ booking: PreviewBooking) -> Bool {
        switch self {
        case .alle: true
        case .zuPruefen: booking.status == .zuPruefen
        case .ohneBeleg: booking.status == .belegFehlt
        }
    }
}

private enum PreviewPayment: Hashable {
    case paid
    case partial
    case open

    var title: String {
        switch self {
        case .paid: "Bezahlt"
        case .partial: "Teilbezahlt"
        case .open: "Offen"
        }
    }

    var symbol: String {
        switch self {
        case .paid: "checkmark.circle"
        case .partial: "circle.lefthalf.filled"
        case .open: "circle"
        }
    }
}

private enum PreviewReviewStatus: Hashable {
    case geprueft
    case zuPruefen
    case belegFehlt

    var title: String {
        switch self {
        case .geprueft: "Geprüft"
        case .zuPruefen: "Zu prüfen"
        case .belegFehlt: "Beleg fehlt"
        }
    }

    var symbol: String {
        switch self {
        case .geprueft: "checkmark.circle.fill"
        case .zuPruefen: "exclamationmark.circle.fill"
        case .belegFehlt: "xmark.circle.fill"
        }
    }

    var color: Color {
        switch self {
        case .geprueft: .green
        case .zuPruefen: .yellow
        case .belegFehlt: .red
        }
    }
}
