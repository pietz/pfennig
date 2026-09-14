import Analysis
import Database
import Domain
import GRDB
import SwiftUI

struct StartView: View {
    @Environment(AppModel.self) private var model
    @State private var selectedYear = Calendar.current.component(.year, from: Date())
    @State private var overview: StartOverview?
    @State private var observationError = false
    @State private var reloadToken = 0

    let onNavigate: (StartDestination) -> Void

    init(onNavigate: @escaping (StartDestination) -> Void = { _ in }) {
        self.onNavigate = onNavigate
    }

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    header

                    if let overview {
                        metrics(overview, isCompact: proxy.size.width < 760)
                        UStVATaskSection { period in
                            onNavigate(.ustva(period))
                        }
                        openSection(overview)
                    } else if observationError {
                        loadError
                    } else {
                        ProgressView()
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(28)
                .frame(maxWidth: 980, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .navigationTitle("Start")
        .navigationSubtitle(Text("Erfasste Buchungen"))
        .task(id: StartObservationKey(year: selectedYear, reloadToken: reloadToken)) {
            await observeOverview(year: selectedYear, reloadToken: reloadToken)
        }
        .onChange(of: selectedYear) { _, _ in
            overview = nil
            observationError = false
        }
    }

    private var loadError: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Startseite konnte nicht geladen werden", systemImage: "exclamationmark.triangle")
                .foregroundStyle(.orange)
            Button("Erneut laden") {
                observationError = false
                reloadToken += 1
            }
            .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Start")
                    .font(.title2.weight(.semibold))
                Text("Erfasst · inkl. Umsatzsteuer")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 12)

            Menu {
                ForEach(overview?.availableYears ?? [selectedYear], id: \.self) { year in
                    Button {
                        selectedYear = year
                    } label: {
                        if year == selectedYear {
                            Label(String(year), systemImage: "checkmark")
                        } else {
                            Text(String(year))
                        }
                    }
                }
            } label: {
                Label(String(selectedYear), systemImage: "calendar")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
    }

    @ViewBuilder
    private func metrics(_ overview: StartOverview, isCompact: Bool) -> some View {
        let content = Group {
            StartMetricCard(
                label: "Einnahmen",
                value: money(overview.incomeMinor),
                tint: .green
            ) {
                onNavigate(.transactions(TransactionListFilter(year: selectedYear, direction: .income)))
            }
            StartMetricCard(
                label: "Ausgaben",
                value: money(overview.expenseMinor),
                tint: .orange
            ) {
                onNavigate(.transactions(TransactionListFilter(year: selectedYear, direction: .expense)))
            }
            StartMetricCard(
                label: "Ergebnis",
                value: money(overview.resultMinor),
                tint: .accentColor
            ) {
                onNavigate(.transactions(TransactionListFilter(year: selectedYear)))
            }
        }

        VStack(alignment: .leading, spacing: 8) {
            if isCompact {
                VStack(spacing: 12) {
                    content
                }
            } else {
                HStack(spacing: 12) {
                    content
                }
            }

            if overview.incompleteEurAmountCount > 0 {
                Label(
                    incompleteAmountMessage(overview.incompleteEurAmountCount),
                    systemImage: "exclamationmark.triangle"
                )
                .font(.caption)
                .foregroundStyle(.orange)
            }
        }
    }

    private func openSection(_ overview: StartOverview) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            StartSectionTitle("Offen", detail: "alle Jahre")

            if overview.openItems.transactionsToReview > 0 {
                StartRow(
                    title: "Buchungen prüfen",
                    detail: "Ungeprüft oder Konflikt",
                    count: overview.openItems.transactionsToReview,
                    symbol: "checkmark.seal",
                    tint: .accentColor
                ) {
                    onNavigate(.transactions(TransactionListFilter(needsAttention: true)))
                }
            }

            if overview.openItems.documentsToAdd > 0 {
                StartRow(
                    title: "Belege ergänzen",
                    detail: "Belege fehlen",
                    count: overview.openItems.documentsToAdd,
                    symbol: "doc.badge.plus",
                    tint: .orange
                ) {
                    onNavigate(.transactions(TransactionListFilter(missingDocumentsOnly: true)))
                }
            }

            if overview.openItems.importProposals > 0 {
                StartRow(
                    title: "Importvorschläge",
                    detail: "Vorschläge offen",
                    count: overview.openItems.importProposals,
                    symbol: "tray.and.arrow.down",
                    tint: .secondary
                ) {
                    onNavigate(.review)
                }
            }

            if overview.openItems.isEmpty {
                Label("Alles erledigt", systemImage: "checkmark.circle")
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 8)
            }

            if overview.recordedBookingCount == 0 {
                Label("Noch keine Buchungen für dieses Jahr", systemImage: "tray")
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 8)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func money(_ minor: Int64?) -> String {
        guard let minor else { return "–" }
        return Money(minorUnits: minor, currency: .eur).formatted(locale: Format.german)
    }

    private func incompleteAmountMessage(_ count: Int) -> String {
        if count == 1 {
            return "1 Buchung ist nicht in den Summen enthalten. Betrag oder Richtung fehlt."
        }
        return "\(count) Buchungen sind nicht in den Summen enthalten. Betrag oder Richtung prüfen."
    }

    private func observeOverview(year: Int, reloadToken: Int) async {
        guard let database = model.database else {
            guard !Task.isCancelled else { return }
            overview = nil
            observationError = true
            return
        }

        do {
            let observation = StartOverviewQuery.observation(
                year: year,
                currentYear: Calendar.current.component(.year, from: Date())
            )
            for try await value in observation.values(in: database.reader) {
                guard !Task.isCancelled, year == selectedYear, reloadToken == self.reloadToken else { return }
                overview = value
                observationError = false
            }
        } catch {
            guard !Task.isCancelled, year == selectedYear, reloadToken == self.reloadToken else { return }
            overview = nil
            observationError = true
        }
    }
}

private struct StartObservationKey: Equatable {
    let year: Int
    let reloadToken: Int
}

private struct StartMetricCard: View {
    let label: String
    let value: String
    let tint: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Text(label)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
                Text(value)
                    .font(.title3.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(tint)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
    }
}

struct StartSectionTitle: View {
    let title: String
    let detail: String

    init(_ title: String, detail: String) {
        self.title = title
        self.detail = detail
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title)
                .font(.headline)
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer(minLength: 8)
        }
    }
}

/// One actionable line of a Start section: symbol, title, a caption, an
/// optional second caption for a state worth colouring, and either a count or
/// nothing on the right. Shared by "Offen" and "Steuern" so both read alike.
struct StartRow: View {
    let title: String
    let detail: String
    var note: (text: String, tint: Color)?
    var count: Int?
    let symbol: String
    let tint: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: symbol)
                    .foregroundStyle(tint)
                    .frame(width: 20)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    if let note {
                        Text(note.text)
                            .font(.caption)
                            .foregroundStyle(note.tint)
                    }
                }

                Spacer(minLength: 8)

                if let count {
                    Text(String(count))
                        .font(.title3.weight(.semibold))
                        .monospacedDigit()
                }

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
            .padding(.vertical, 7)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
