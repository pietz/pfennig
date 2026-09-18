import Core
import SwiftUI

/// The start page: the running year in three numbers, the work still to do and
/// the deadlines still running. Every row leads into the ledger or the export.
struct StartView: View {
    @Bindable var model: AppModel
    @Binding var workspace: Workspace
    /// Read once when the page appears; the deadlines depend on the rhythm.
    @State private var profil = Profil()
    /// Only the three tiles follow this; To Dos and deadlines are about today.
    @State private var jahr = LocalDate.today().jahr

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                YearTiles(werte: Start.jahreswerte(model.buchungen, jahr: jahr))
                HStack(alignment: .top, spacing: 16) {
                    aufgabenCard
                    fristenCard
                }
            }
            .padding(20)
        }
        .task { profil = model.profile() }
        .toolbar { toolbarItems }
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text(StartView.greeting(name: profil.name))
                    .font(.largeTitle)
                    .fontWeight(.bold)
                Text(Date.now.formatted(date: .complete, time: .omitted))
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Picker("Jahr", selection: $jahr) {
                ForEach(Start.jahre(model.buchungen), id: \.self) { Text(String($0)).tag($0) }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .fixedSize()
            .padding(.top, 6)
        }
        .padding(.bottom, 4)
    }

    /// Morning, day or evening by the clock. Without a name in the profile the
    /// greeting stands on its own rather than addressing nobody.
    static func greeting(name: String) -> String {
        let tageszeit = switch Calendar.current.component(.hour, from: .now) {
        case ..<11: "Guten Morgen"
        case ..<18: "Guten Tag"
        default: "Guten Abend"
        }
        let kurz = name.split(separator: " ").first.map(String.init) ?? ""
        return kurz.isEmpty ? "\(tageszeit)!" : "\(tageszeit), \(kurz)!"
    }

    // MARK: Cards

    private var aufgabenCard: some View {
        Card("To Dos") {
            CardRows(Start.aufgaben(model.buchungen)) { aufgabe in
                Button { open(aufgabe) } label: { TaskRow(aufgabe: aufgabe) }
                    .disabled(aufgabe.erledigt)
            }
        }
    }

    /// Only the three most pressing deadlines. More would bury the card, and
    /// what is further out is not something to act on today.
    private static let maxFristen = 3

    private var fristenCard: some View {
        Card("Fristen") {
            let fristen = Array(
                Start.fristen(model.buchungen, exportiert: model.exportedPeriods, profil: profil)
                    .prefix(StartView.maxFristen)
            )
            if fristen.isEmpty {
                CardEmptyState(text: "Alles abgegeben.")
            } else {
                CardRows(fristen) { frist in
                    Button { open(frist) } label: { DeadlineRow(frist: frist) }
                }
            }
        }
    }

    // MARK: Actions

    /// The row opens the ledger on exactly the bookings it counted.
    private func open(_ aufgabe: Start.Aufgabe) {
        model.filter = .alle
        model.search = ""
        model.reviewFilter = aufgabe.art.filter
        workspace = .buchungen
    }

    private func open(_ frist: Start.Frist) {
        model.exportPeriod = frist.zeitraum
        model.exportVisible = true
    }

    // MARK: Toolbar

    /// Filters, search and the inspector belong to the table and stay away.
    /// What remains are the two actions that concern the whole window, plus the
    /// intake indicator.
    @ToolbarContentBuilder private var toolbarItems: some ToolbarContent {
        if model.progress.visible {
            ToolbarItem(placement: .primaryAction) {
                ProgressView().controlSize(.small)
            }
        }
        ToolbarItem(placement: .primaryAction) {
            Button("Neue Buchung", systemImage: "plus") {
                model.createBooking()
                workspace = .buchungen
            }
        }
        ToolbarItem(placement: .primaryAction) {
            Button("Export", systemImage: "square.and.arrow.up") {
                model.exportPeriod = nil
                model.exportVisible = true
            }
        }
    }
}

// MARK: - Tiles

/// The three numbers of the running year. They are the three the ledger footer
/// shows for the visible rows, here for the year and counted by payment date.
private struct YearTiles: View {
    let werte: Totals

    var body: some View {
        HStack(spacing: 0) {
            tile("Einnahmen", werte.einnahmen, "arrow.down.circle", .green)
            Divider().frame(height: 34)
            tile("Ausgaben", werte.ausgaben, "arrow.up.circle", .primary)
            Divider().frame(height: 34)
            tile("Saldo", werte.saldo, "equal.circle", werte.saldo < .null ? .red : .green)
        }
        .padding(.vertical, 12)
        .cardBackground()
    }

    private func tile(_ titel: String, _ betrag: Cent, _ symbol: String, _ color: Color) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 20, weight: .regular))
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 1) {
                Text(titel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(betrag.formatted)
                    .font(.title3)
                    .fontWeight(.semibold)
                    .monospacedDigit()
                    .foregroundStyle(color)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
    }
}

// MARK: - Rows

/// One kind of work: how many bookings need it, or a check when there are none.
/// The row stays in the list when it is done, so the card keeps its shape and
/// finishing something is visible.
private struct TaskRow: View {
    let aufgabe: Start.Aufgabe

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: aufgabe.art.symbol)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(aufgabe.erledigt ? AnyShapeStyle(.tertiary) : AnyShapeStyle(aufgabe.art.color))
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 1) {
                Text(aufgabe.art.titel)
                    .fontWeight(.semibold)
                    .foregroundStyle(aufgabe.erledigt ? .secondary : .primary)
                Text(aufgabe.erledigt ? "Alles erledigt" : aufgabe.art.erklaerung)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 12)
            if aufgabe.erledigt {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(.green)
            } else {
                Text("\(aufgabe.anzahl)")
                    .font(.callout)
                    .fontWeight(.semibold)
                    .monospacedDigit()
                    .foregroundStyle(aufgabe.art.color)
                    .frame(minWidth: 22)
                    .padding(.vertical, 3)
                    .background(aufgabe.art.color.opacity(0.15), in: .capsule)
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
    }
}

private extension Start.Aufgabenart {
    var symbol: String {
        switch self {
        case .pruefen: "doc.text.magnifyingglass"
        case .belege: "paperclip"
        case .ueberfaellig: "clock.badge.exclamationmark"
        }
    }

    var color: Color {
        switch self {
        case .pruefen: .yellow
        case .belege: .red
        case .ueberfaellig: .orange
        }
    }
}

/// One tax deadline: a short name, the date, and how much time is left. How far
/// the bookings in that period are reviewed belongs to the task card and is not
/// repeated here.
private struct DeadlineRow: View {
    let frist: Start.Frist

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: frist.symbol)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(frist.color)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 1) {
                Text(frist.titel)
                    .fontWeight(.semibold)
                    .lineLimit(1)
                Text("Fällig am \(frist.faellig.formatted)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 12)
            Text(frist.restText)
                .font(.caption)
                .fontWeight(.semibold)
                .monospacedDigit()
                .foregroundStyle(frist.color)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(frist.color.opacity(0.15), in: .capsule)
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }
}

private extension Start.Frist {
    var symbol: String {
        zeitraum.art == .ustva ? "percent" : "doc.text"
    }

    /// Red once the deadline has passed, yellow in the last three days before
    /// it, green while there is still room.
    var color: Color {
        switch tage {
        case ..<0: .red
        case ...3: .yellow
        default: .green
        }
    }

    var restText: String {
        switch tage {
        case ..<0: "Überfällig"
        case 0: "Heute"
        case 1: "In 1 Tag"
        default: "In \(tage) Tagen"
        }
    }
}

// MARK: - Card shell

/// A titled card. The shell of both columns, so they keep the same rhythm.
private struct Card<Content: View>: View {
    let titel: String
    @ViewBuilder let content: Content

    init(_ titel: String, @ViewBuilder content: () -> Content) {
        self.titel = titel
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(titel)
                .font(.headline)
                .padding(.horizontal, 14)
                .padding(.top, 12)
                .padding(.bottom, 8)
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardBackground()
    }
}

private extension View {
    /// The one surface of the page: a quiet panel against the window background.
    func cardBackground() -> some View {
        background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(Color(nsColor: .separatorColor))
        )
    }
}

/// The rows inside a card, separated by an inset divider. Each row brings its
/// own button; the shell only gives it the padding and the quiet highlight.
private struct CardRows<Item: Identifiable, Row: View>: View {
    let items: [Item]
    @ViewBuilder let row: (Item) -> Row

    init(_ items: [Item], @ViewBuilder row: @escaping (Item) -> Row) {
        self.items = items
        self.row = row
    }

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                if index > 0 {
                    Divider().padding(.leading, 48)
                }
                row(item)
                    .buttonStyle(CardRowButtonStyle())
            }
        }
        .padding(.bottom, 4)
    }
}

/// No button chrome, just a quiet highlight under the pointer.
private struct CardRowButtonStyle: ButtonStyle {
    @State private var hovering = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.primary)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .contentShape(.rect)
            .background(hovering ? Color.primary.opacity(0.05) : .clear)
            .onHover { hovering = $0 }
    }
}

private struct CardEmptyState: View {
    let text: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
            Text(text).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.bottom, 14)
    }
}
