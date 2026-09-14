import Analysis
import Database
import Domain
import Export
import SwiftUI
import Tax

/// The "Steuern" section of Start (spec `ustva-preparation.md`, "Aufgabe auf
/// Start"): the Voranmeldung that is due next, every earlier period that is
/// not marked submitted, and every submitted period whose values moved since.
///
/// The rows follow the ledger live, so a booking entered now changes the
/// Zahllast preview here without a reload.
struct UStVATaskSection: View {
    let onOpen: (UStVAPeriod) -> Void

    @Environment(AppModel.self) private var model
    @State private var rows: [UStVATasks.Summary] = []
    @State private var needsPeriodConfirmation = false

    private let today = LocalDate.today()

    var body: some View {
        Group {
            if !rows.isEmpty || needsPeriodConfirmation {
                VStack(alignment: .leading, spacing: 8) {
                    StartSectionTitle("Steuern", detail: "Umsatzsteuer-Voranmeldung")

                    if needsPeriodConfirmation {
                        periodConfirmation
                    }

                    ForEach(rows) { row in
                        UStVATaskRow(summary: row, today: today) { onOpen(row.period) }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .task { await observe() }
        .onAppear { needsPeriodConfirmation = Self.needsConfirmation(model) }
    }

    /// One-time prompt for the rhythm that used to be called "Jährlich".
    private var periodConfirmation: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: "questionmark.circle")
                .foregroundStyle(.orange)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text("Bitte UStVA-Rhythmus in den Einstellungen bestätigen")
                Text("„Jährlich“ heißt jetzt „Keine regelmäßigen Voranmeldungen“.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            SettingsLink {
                Text("Einstellungen")
            }
            Button("Bestätigen") {
                UStVAPreferences.setPeriodConfirmed(true, in: model.database)
                needsPeriodConfirmation = false
            }
        }
        .padding(.vertical, 7)
    }

    private static func needsConfirmation(_ model: AppModel) -> Bool {
        guard let profile = model.profile, profile.vatStatus == .taxable, profile.ustvaPeriod == .yearly else {
            return false
        }
        return !UStVAPreferences.periodIsConfirmed(in: model.database)
    }

    private func observe() async {
        guard let database = model.database, let profile = model.profile else {
            rows = []
            return
        }
        do {
            let observation = UStVATasks.startObservation(
                profile: profile,
                today: today,
                dauerfristverlaengerung: UStVAPreferences.dauerfristverlaengerung(in: database)
            )
            for try await value in observation.values(in: database.reader) {
                guard !Task.isCancelled else { return }
                rows = value
            }
        } catch {
            rows = []
        }
    }
}

private struct UStVATaskRow: View {
    let summary: UStVATasks.Summary
    let today: LocalDate
    let action: () -> Void

    private var isOverdue: Bool {
        !summary.isSubmitted && summary.dueDate < today
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: "building.columns")
                    .foregroundStyle(isOverdue ? Color.orange : Color.accentColor)
                    .frame(width: 20)

                VStack(alignment: .leading, spacing: 2) {
                    Text("UStVA \(UStVAPeriodText.title(summary.period))")
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

    private var detail: String {
        var parts = ["fällig \(Format.date(summary.dueDate))"]
        let label = summary.payableMinor < 0 ? "Erstattung" : "Zahllast"
        parts.append("\(label) \(Format.money(abs(summary.payableMinor), currency: .eur))")
        if summary.exceptionCount > 0 {
            parts.append(
                summary.exceptionCount == 1 ? "1 offener Fall" : "\(summary.exceptionCount) offene Fälle"
            )
        }
        return parts.joined(separator: " · ")
    }

    private var note: (text: String, tint: Color)? {
        if summary.changedSinceSubmission {
            return ("verändert seit Übermittlung", .orange)
        }
        if let submittedAt = summary.submittedAt {
            return ("übermittelt am \(Format.timestamp(submittedAt))", .secondary)
        }
        if isOverdue {
            return ("überfällig", .orange)
        }
        return nil
    }
}
