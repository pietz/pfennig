import Analysis
import AppKit
import Database
import Domain
import Export
import SwiftUI
import Tax
import UniformTypeIdentifiers

/// The UStVA task window (spec `ustva-preparation.md`, "Aufgabe auf Start und
/// Aufgabenfenster"): period picker, open exceptions, the form values with
/// their single contributions, and the three handoff actions.
///
/// It is a window of its own so the ledger stays open next to it: the
/// exception list sends the user into Buchungen, and the values follow every
/// correction made there without being reopened.
///
/// Pfennig does not transmit. "Als übermittelt markieren" only remembers what
/// the user filed themselves in Mein ELSTER; it locks nothing.
struct UStVATaskWindow: View {
    static let windowID = "ustva-task"

    @Environment(AppModel.self) private var model

    @State private var kind: UStVAPeriod.Kind = .quarterly
    @State private var year = Calendar.current.component(.year, from: Date())
    @State private var index = 1
    @State private var detail: UStVATasks.TaskDetail?
    @State private var loadFailed = false
    @State private var note: FooterNote?
    @State private var isResolved = false

    private struct FooterNote {
        var symbol: String
        var tint: Color
        var lines: [String]
    }

    private var period: UStVAPeriod {
        switch kind {
        case .monthly: UStVAPeriod(year: year, month: index)
        case .quarterly: UStVAPeriod(year: year, quarter: index)
        }
    }

    private var periodKey: String {
        "\(year)-\(kind == .monthly ? "m" : "q")-\(index)"
    }

    private var dueDate: LocalDate {
        period.dueDate(
            dauerfristverlaengerung: UStVAPreferences.dauerfristverlaengerung(in: model.database)
        )
    }

    var body: some View {
        Group {
            if model.profile == nil {
                ContentUnavailableView(
                    "Kein Betrieb eingerichtet",
                    systemImage: "building.columns",
                    description: Text("Die Voranmeldung braucht einen Betrieb mit Steuernummer.")
                )
            } else {
                content
            }
        }
        .navigationTitle("UStVA \(UStVAPeriodText.title(period))")
        .frame(minWidth: 620, minHeight: 460)
        .onAppear(perform: resolvePeriod)
        .onChange(of: model.ustvaTaskRequest) { _, request in
            guard let request else { return }
            show(request.period)
        }
        .task(id: periodKey) { await observe() }
        .onChange(of: periodKey) { _, _ in note = nil }
    }

    private var content: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    periodPicker
                    if let detail {
                        status(detail)
                        if !detail.result.exceptions.isEmpty {
                            exceptions(detail)
                        }
                        values(detail.result)
                    } else if loadFailed {
                        Label("Die Werte konnten nicht berechnet werden.", systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                    } else {
                        ProgressView()
                    }
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Divider()
            footer
        }
    }

    // MARK: - Period

    private var periodPicker: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Picker("Zeitraum", selection: $year) {
                ForEach(years, id: \.self) { year in
                    Text(String(year)).tag(year)
                }
            }
            .labelsHidden()
            .fixedSize()

            Picker("Abschnitt", selection: $index) {
                ForEach(indices, id: \.self) { index in
                    Text(name(of: index)).tag(index)
                }
            }
            .labelsHidden()
            .fixedSize()

            Text("fällig \(Format.date(dueDate))")
                .foregroundStyle(.secondary)

            Spacer(minLength: 8)
        }
    }

    private var years: [Int] {
        let current = Calendar.current.component(.year, from: Date())
        return Array(min(current - 2, year) ... max(current, year))
    }

    private var indices: [Int] {
        kind == .monthly ? Array(1 ... 12) : Array(1 ... 4)
    }

    private func name(of index: Int) -> String {
        kind == .monthly ? UStVAPeriodText.monthName(index) : "Q\(index)"
    }

    /// Takes the period Start asked for, or the one the calendar makes
    /// current. The rhythm always follows the business profile.
    private func resolvePeriod() {
        guard !isResolved, let profile = model.profile else { return }
        show(
            model.ustvaTaskRequest?.period
                ?? UStVATasks.period(containing: .today(), kind: UStVATasks.periodKind(for: profile))
        )
        isResolved = true
    }

    private func show(_ period: UStVAPeriod) {
        kind = period.kind
        year = period.year
        index = period.index
    }

    // MARK: - Status

    @ViewBuilder
    private func status(_ detail: UStVATasks.TaskDetail) -> some View {
        let result = detail.result
        VStack(alignment: .leading, spacing: 6) {
            if result.isDraft {
                Label(draftText(result.exceptions.count), systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
            }
            if detail.changedSinceSubmission {
                Label("Verändert seit Übermittlung", systemImage: "arrow.triangle.2.circlepath")
                    .foregroundStyle(.orange)
            } else if let submittedAt = detail.submittedAt {
                Label("Übermittelt am \(Format.timestamp(submittedAt))", systemImage: "checkmark.circle")
                    .foregroundStyle(.secondary)
            }
            if result.isSmallBusiness {
                Text("Kleinunternehmer (§19 UStG): gemeldet wird nur die nach §13b geschuldete Steuer.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func draftText(_ count: Int) -> String {
        count == 1 ? "Entwurf, 1 offener Fall" : "Entwurf, \(count) offene Fälle"
    }

    // MARK: - Exceptions

    private func exceptions(_ detail: UStVATasks.TaskDetail) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Ausnahmen")
                .font(.headline)

            ForEach(detail.result.exceptions) { exception in
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                        .frame(width: 16)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(exception.message)
                            .fixedSize(horizontal: false, vertical: true)
                        if let subject = exception.transactionID.flatMap({ detail.subjects[$0] }) {
                            Text(subjectLine(subject))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Spacer(minLength: 8)

                    if let id = exception.transactionID {
                        Button("In Buchungen öffnen") { model.showTransaction(id) }
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }

    private func subjectLine(_ subject: UStVATasks.ExceptionSubject) -> String {
        [subject.displayName, subject.amount?.formatted(locale: Format.german)]
            .compactMap(\.self)
            .joined(separator: " · ")
    }

    // MARK: - Form values

    private func values(_ result: UStVAReturn) -> some View {
        // Kz 83 is not a reported line: it is the Zahllast the form derives,
        // shown as its own row below.
        let lines = result.lines.filter { $0.kennzahl != 83 }
        return VStack(alignment: .leading, spacing: 4) {
            Text("Formularwerte")
                .font(.headline)

            HStack(spacing: 8) {
                Text("Zeile").frame(width: 44, alignment: .leading)
                Text("Kennzahl").frame(width: 64, alignment: .leading)
                Text("Bezeichnung")
                Spacer(minLength: 8)
                Text("Betrag")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.bottom, 2)

            if lines.isEmpty {
                Text("Keine meldepflichtigen Werte in diesem Zeitraum.")
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 6)
            }

            ForEach(lines) { line in
                if line.contributions.isEmpty {
                    lineLabel(line)
                        .padding(.leading, 18)
                        .padding(.vertical, 3)
                } else {
                    DisclosureGroup {
                        VStack(alignment: .leading, spacing: 2) {
                            ForEach(line.contributions) { contribution in
                                contributionRow(contribution)
                            }
                        }
                        .padding(.leading, 4)
                        .padding(.vertical, 2)
                    } label: {
                        lineLabel(line)
                            .padding(.vertical, 3)
                    }
                }
                Divider()
            }

            payableRow(result)
        }
    }

    private func lineLabel(_ line: UStVAReturn.Line) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(String(UStVA_2026.formLine(line.kennzahl)))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 44, alignment: .leading)
            Text("Kz \(line.kennzahl)")
                .monospacedDigit()
                .frame(width: 64, alignment: .leading)
            VStack(alignment: .leading, spacing: 1) {
                Text(line.title)
                    .fixedSize(horizontal: false, vertical: true)
                if !line.isVerified {
                    Text("ungeprüft")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
            Spacer(minLength: 8)
            Text(amountText(line))
                .monospacedDigit()
        }
        .contentShape(Rectangle())
    }

    private func contributionRow(_ contribution: UStVAReturn.Contribution) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(Format.date(contribution.date))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 84, alignment: .leading)

            Image(systemName: contribution.paymentID == nil ? "doc.text" : "creditcard")
                .foregroundStyle(.secondary)
                .help(Text(contribution.paymentID == nil ? "Mit dem Rechnungsdatum" : "Mit der Zahlung"))

            VStack(alignment: .leading, spacing: 1) {
                Text(contribution.counterpartyName ?? contribution.description)
                if let name = contribution.counterpartyName, name != contribution.description {
                    Text(contribution.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 8)

            Text(Format.money(contribution.amountMinor, currency: .eur))
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
        .font(.callout)
    }

    private func payableRow(_ result: UStVAReturn) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(String(UStVA_2026.formLine(83)))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 44, alignment: .leading)
            Text("Kz 83")
                .monospacedDigit()
                .frame(width: 64, alignment: .leading)
            Text(
                result.payableMinor < 0
                    ? "Verbleibender Überschuss (Erstattung)"
                    : "Verbleibende Vorauszahlung (Zahllast)"
            )
            Spacer(minLength: 8)
            Text(Format.money(abs(result.payableMinor), currency: .eur))
                .monospacedDigit()
        }
        .fontWeight(.semibold)
        .padding(.top, 6)
        .padding(.leading, 18)
    }

    /// Bemessungsgrundlagen carry whole euros as the form does; Steuer
    /// Kennzahlen carry cents.
    private func amountText(_ line: UStVAReturn.Line) -> String {
        guard line.isBase else { return Format.money(line.amountMinor, currency: .eur) }
        let euros = UStVA_2026.wholeEuros(line.amountMinor)
        return "\(euros.formatted(.number.locale(Format.german))) €"
    }

    // MARK: - Footer

    private var footer: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Button("Werte kopieren", action: copyValues)

                Button("XML exportieren…", action: exportXML)
                Text("experimentell")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .help(Text("Das Uploadformat ist nicht offiziell dokumentiert und noch nicht getestet."))

                Spacer(minLength: 12)

                Button(detail?.isSubmitted == true ? "Übermittlung zurücknehmen" : "Als übermittelt markieren",
                       action: toggleSubmission)
            }
            .disabled(detail == nil)

            if let note {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Image(systemName: note.symbol)
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(note.lines, id: \.self) { line in
                            Text(line).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .font(.caption)
                .foregroundStyle(note.tint)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.bar)
    }

    // MARK: - Actions

    private func copyValues() {
        guard let result = detail?.result else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(UStVAValueList.text(for: result), forType: .string)
        note = FooterNote(
            symbol: "doc.on.clipboard",
            tint: .secondary,
            lines: ["Die Werte liegen in der Zwischenablage."]
        )
    }

    private func exportXML() {
        guard let result = detail?.result else { return }
        let export = UStVAXMLExporter.export(result)
        let panel = NSSavePanel()
        panel.nameFieldStringValue = export.filename
        panel.allowedContentTypes = [.xml]
        panel.message = "XML-Datei für den Upload in Mein ELSTER sichern. Pfennig übermittelt nicht."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try export.data.write(to: url)
            note = FooterNote(
                symbol: export.warnings.isEmpty ? "checkmark.circle" : "exclamationmark.triangle",
                tint: export.warnings.isEmpty ? .secondary : .orange,
                lines: ["Gesichert als \(url.lastPathComponent)."] + export.warnings
            )
        } catch {
            note = FooterNote(
                symbol: "exclamationmark.triangle",
                tint: .orange,
                lines: ["Die Datei konnte nicht gesichert werden: \(error.localizedDescription)"]
            )
        }
    }

    private func toggleSubmission() {
        guard let database = model.database, let profile = model.profile, let detail else { return }
        do {
            if detail.isSubmitted {
                try SubmittedReturnRepository.unmark(database, profileID: profile.id, period: period)
                note = FooterNote(
                    symbol: "arrow.uturn.backward",
                    tint: .secondary,
                    lines: ["Die Übermittlung ist zurückgenommen. An den Buchungen ändert das nichts."]
                )
            } else {
                try SubmittedReturnRepository.markSubmitted(
                    database,
                    profileID: profile.id,
                    result: detail.result
                )
                note = FooterNote(
                    symbol: "checkmark.circle",
                    tint: .secondary,
                    lines: ["Als übermittelt vermerkt. Buchungen bleiben änderbar."]
                )
            }
        } catch {
            note = FooterNote(
                symbol: "exclamationmark.triangle",
                tint: .orange,
                lines: [error.localizedDescription]
            )
        }
    }

    // MARK: - Observation

    private func observe() async {
        guard let database = model.database, let profile = model.profile else {
            detail = nil
            loadFailed = true
            return
        }
        let period = period
        do {
            let observation = UStVATasks.detailObservation(period: period, profile: profile)
            for try await value in observation.values(in: database.reader) {
                guard !Task.isCancelled else { return }
                detail = value
                loadFailed = false
            }
        } catch {
            guard !Task.isCancelled else { return }
            detail = nil
            loadFailed = true
        }
    }
}
