import Database
import Domain
import SwiftUI

/// Records a payment by hand and allocates it to this transaction
/// (spec 17.13, 17.14). Partial payments are allowed: the allocated amount
/// may be smaller than the invoice.
struct PaymentEditor: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    let detail: TransactionDetail
    @State private var payment: PaymentDraft
    @State private var accounts: [Account] = []

    init(detail: TransactionDetail) {
        self.detail = detail
        let currency = CurrencyCode(detail.transaction.bookedCurrency)
        let open = (detail.transaction.bookedGrossMinor ?? 0) - detail.totalAllocatedMinor
        _payment = State(
            initialValue: PaymentDraft(
                direction: detail.transaction.direction == .income ? .inflow : .outflow,
                paymentDate: .today(),
                amountMinor: max(open, 0),
                currency: currency,
                counterpartyNameRaw: detail.counterparty?.displayName,
                reference: detail.transaction.invoiceNumber
            )
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Zahlung hinzufügen").font(.headline)
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            Divider()
            Form {
                Section {
                    LabeledContent("Datum") {
                        DatePicker(
                            "",
                            selection: Binding(
                                get: { payment.paymentDate.date() },
                                set: { payment.paymentDate = LocalDate($0) }
                            ),
                            displayedComponents: .date
                        )
                        .labelsHidden()
                        .environment(\.locale, Format.german)
                    }
                    MoneyField(
                        label: "Betrag",
                        minor: Binding(
                            get: { payment.amountMinor },
                            set: { payment.amountMinor = $0 ?? 0 }
                        ),
                        currency: payment.currency
                    )
                    Picker("Konto", selection: $payment.accountId) {
                        Text("Ohne Konto").tag(String?.none)
                        ForEach(accounts) { Text($0.name).tag(String?.some($0.id)) }
                    }
                    Picker("Methode", selection: $payment.paymentMethod) {
                        ForEach(PaymentMethod.allCases, id: \.self) { Text($0.label).tag(PaymentMethod?.some($0)) }
                    }
                    TextField("Referenz", text: $payment.reference.orEmpty, prompt: Text("optional"))
                } footer: {
                    Text(openAmountHint)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
            Divider()
            HStack {
                Spacer()
                Button("Abbrechen", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Sichern", action: save)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(payment.amountMinor == 0)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
        .frame(width: 460, height: 380)
        .task { accounts = (try? model.database?.accounts()) ?? [] }
    }

    private var openAmountHint: String {
        let open = (detail.transaction.bookedGrossMinor ?? 0) - detail.totalAllocatedMinor
        let currency = CurrencyCode(detail.transaction.bookedCurrency)
        return "Offen: \(Format.money(open, currency: currency)). Ein kleinerer Betrag wird als Teilzahlung gebucht."
    }

    private func save() {
        var draft = detail.draft
        draft.payments.append(payment)
        guard model.save(draft) != nil else { return }
        dismiss()
    }
}
