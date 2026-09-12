import Database
import Domain
import SwiftUI

/// German number and date formatting for the whole UI (spec 6.1).
enum Format {
    static let german = Locale(identifier: "de_DE")

    /// "1234,56" - what a user types into an amount field.
    static func amount(_ minor: Int64?, currency: CurrencyCode) -> String {
        guard let minor else { return "" }
        return Money(minorUnits: minor, currency: currency).decimal
            .formatted(.number.precision(.fractionLength(currency.exponent)).grouping(.never).locale(german))
    }

    static func money(_ minor: Int64?, currency: CurrencyCode) -> String {
        guard let minor else { return "–" }
        return Money(minorUnits: minor, currency: currency).formatted(locale: german)
    }

    static func date(_ date: LocalDate?) -> String {
        date?.formattedShort ?? "–"
    }

    static func timestamp(_ iso: String) -> String {
        guard let date = Timestamp.date(iso) else { return iso }
        return date.formatted(.dateTime.day(.twoDigits).month(.twoDigits).year().hour().minute().locale(german))
    }
}

/// An amount in minor units, entered in German or English notation and
/// parsed by `Money` (spec 15.2). While the field has focus it is the source
/// of truth, so automatic completion never overwrites what is being typed.
struct MoneyField: View {
    let label: LocalizedStringKey
    @Binding var minor: Int64?
    var currency: CurrencyCode = .eur
    var onUserEdit: (() -> Void)?

    @State private var text = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        TextField(label, text: $text, prompt: Text("0,00"))
            .multilineTextAlignment(.trailing)
            .monospacedDigit()
            .focused($isFocused)
            .onAppear { text = Format.amount(minor, currency: currency) }
            .onChange(of: text) { _, new in
                guard isFocused else { return }
                let trimmed = new.trimmingCharacters(in: .whitespaces)
                minor = trimmed.isEmpty ? nil : (try? Money.fromDecimalString(trimmed, currency: currency))?
                    .minorUnits ?? minor
                onUserEdit?()
            }
            .onChange(of: minor) { _, new in
                guard !isFocused else { return }
                text = Format.amount(new, currency: currency)
            }
    }
}

extension Binding where Value == String? {
    /// A non-optional text binding; an empty field means "not set".
    var orEmpty: Binding<String> {
        Binding<String>(
            get: { self.wrappedValue ?? "" },
            set: { (newValue: String) in self.wrappedValue = newValue.isEmpty ? nil : newValue }
        )
    }
}

/// A calendar date that may be absent (spec 23).
struct OptionalDateField: View {
    let label: LocalizedStringKey
    @Binding var date: LocalDate?

    var body: some View {
        LabeledContent(label) {
            HStack(spacing: 4) {
                DatePicker(
                    "",
                    selection: Binding(
                        get: { (date ?? .today()).date() },
                        set: { date = LocalDate($0) }
                    ),
                    displayedComponents: .date
                )
                .labelsHidden()
                .environment(\.locale, Format.german)
                Button {
                    date = nil
                } label: {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .help("Datum entfernen")
                .opacity(date == nil ? 0 : 1)
                .disabled(date == nil)
            }
        }
    }
}

/// Where a value came from (spec 8.3), shown next to the field it belongs to.
/// `help` carries the model's evidence snippet when there is one.
struct ProvenanceBadge: View {
    let provenance: Provenance?
    var help: String?

    var body: some View {
        if let provenance {
            Text(label(provenance))
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 1)
                .background(.quaternary, in: Capsule())
                .help(help ?? "Herkunft: \(label(provenance))")
        }
    }

    private func label(_ provenance: Provenance) -> String {
        switch provenance {
        case .document: "Beleg"
        case .agent: "KI"
        case .calculated: "Berechnet"
        case .manual: "Manuell"
        case .imported: "Import"
        case .rule: "Regel"
        }
    }
}

/// One validation finding: always icon plus text, never colour alone (spec 14.3).
struct IssueRow: View {
    let severity: IssueSeverity
    let message: String
    var action: (() -> Void)?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: symbol)
                .foregroundStyle(tint)
            Text(message)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            if let action {
                Button("Ignorieren", action: action)
                    .buttonStyle(.link)
                    .font(.callout)
            }
        }
    }

    private var symbol: String {
        switch severity {
        case .error: "xmark.octagon.fill"
        case .warning: "exclamationmark.triangle.fill"
        case .info: "info.circle"
        }
    }

    private var tint: Color {
        switch severity {
        case .error: .red
        case .warning: .orange
        case .info: .secondary
        }
    }
}

extension TransactionType {
    var label: LocalizedStringKey {
        switch self {
        case .invoice: "Rechnung"
        case .receipt: "Beleg / Quittung"
        case .creditNote: "Gutschrift"
        case .refund: "Erstattung"
        case .paymentOnly: "Nur Zahlung"
        case .taxPayment: "Steuerzahlung"
        case .other: "Sonstiges"
        }
    }
}

extension PaymentMethod {
    var label: LocalizedStringKey {
        switch self {
        case .bankTransfer: "Überweisung"
        case .card: "Karte"
        case .paypal: "PayPal"
        case .directDebit: "Lastschrift"
        case .cash: "Bar"
        case .other: "Sonstiges"
        case .unknown: "Unbekannt"
        }
    }
}

extension TaxComponentKind {
    var label: LocalizedStringKey {
        switch self {
        case .standard: "Regelsatz"
        case .reduced: "Ermäßigt"
        case .zero: "Ohne Steuer"
        case .reverseChargeNote: "Reverse-Charge-Hinweis"
        case .exempt: "Steuerfrei"
        case .fee: "Gebühr"
        case .deposit: "Pfand"
        case .other: "Sonstiges"
        }
    }
}

extension TaxAssessmentStatus {
    var label: LocalizedStringKey {
        switch self {
        case .proposed: "Vorgeschlagen"
        case .confirmed: "Bestätigt"
        case .manualOverride: "Manuell gesetzt"
        }
    }
}

// MARK: - Plain German strings for interpolation

extension Direction {
    var text: String {
        switch self {
        case .income: "Einnahme"
        case .expense: "Ausgabe"
        case .unknown: "Unbekannt"
        }
    }
}

extension PaymentMethod {
    var text: String {
        switch self {
        case .bankTransfer: "Überweisung"
        case .card: "Karte"
        case .paypal: "PayPal"
        case .directDebit: "Lastschrift"
        case .cash: "Bar"
        case .other: "Sonstiges"
        case .unknown: "Unbekannt"
        }
    }
}

extension TaxAssessmentStatus {
    var text: String {
        switch self {
        case .proposed: "Vorgeschlagen"
        case .confirmed: "Bestätigt"
        case .manualOverride: "Manuell gesetzt"
        }
    }
}

extension TaxTreatment {
    var text: String {
        switch self {
        case .domesticVAT: "Umsatzsteuer (DE)"
        case .reverseCharge: "Reverse Charge"
        case .intraCommunityAcquisition: "Innergem. Erwerb"
        case .intraCommunitySupply: "Innergem. Lieferung"
        case .export: "Ausfuhr"
        case .importVAT: "Einfuhrumsatzsteuer"
        case .nonTaxable: "Nicht steuerbar"
        case .exempt: "Steuerfrei"
        case .smallBusiness: "Kleinunternehmer"
        case .unknown: "Unbekannt"
        }
    }
}

extension AuditAction {
    var text: String {
        switch self {
        case .create: "Angelegt"
        case .update: "Geändert"
        case .delete: "Gelöscht"
        case .link: "Verknüpft"
        case .unlink: "Getrennt"
        case .confirm: "Bestätigt"
        case .correct: "Korrigiert"
        case .lock: "Gesperrt"
        case .unlock: "Entsperrt"
        }
    }
}

extension AuditActor {
    var text: String {
        switch self {
        case .user: "Benutzer"
        case .agent: "KI"
        case .system: "System"
        case .import: "Import"
        }
    }
}
