import Database
import Domain
import SwiftUI

/// Records a payment by hand and allocates it to this transaction
/// (spec 17.13, 17.14). Partial payments are allowed: the allocated amount
/// may be smaller than the invoice.
struct PaymentEditor: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    @Binding private var draft: TransactionDraft
    let onSave: (TransactionDraft) -> Void
    @State private var payment: PaymentDraft
    @State private var accounts: [Account] = []
    @State private var amountIsValid = true
    @State private var saveError: String?

    init(
        draft: Binding<TransactionDraft>,
        onSave: @escaping (TransactionDraft) -> Void = { _ in }
    ) {
        _draft = draft
        self.onSave = onSave
        let transaction = draft.wrappedValue
        let open = (transaction.grossMinor ?? 0) - transaction.payments.reduce(0) { $0 + $1.allocated }
        _payment = State(
            initialValue: PaymentDraft(
                direction: transaction.direction == .income ? .inflow : .outflow,
                paymentDate: .today(),
                amountMinor: max(open, 0),
                currency: transaction.currency,
                counterpartyNameRaw: transaction.counterpartyName.isEmpty ? nil : transaction.counterpartyName,
                reference: transaction.invoiceNumber
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
                        currency: payment.currency,
                        onUserEdit: { saveError = nil },
                        onValidityChange: { amountIsValid = $0 }
                    )
                    if let paymentAmountMessage {
                        IssueRow(severity: .error, message: paymentAmountMessage)
                    }
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
                if let saveError {
                    Section {
                        IssueRow(severity: .error, message: saveError)
                    }
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
                    .disabled(paymentAmountMessage != nil)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
        .frame(width: 460, height: 380)
        .task { accounts = (try? model.database?.accounts()) ?? [] }
    }

    private var paymentAmountMessage: String? {
        guard amountIsValid else { return "Betrag ist ungültig. Bitte geben Sie eine Zahl ein." }
        guard payment.amountMinor > 0 else { return "Betrag muss größer als 0 sein." }
        return nil
    }

    private var openAmountHint: String {
        let open = (draft.grossMinor ?? 0) - draft.payments.reduce(0) { $0 + $1.allocated }
        return "Offen: \(Format.money(open, currency: draft.currency)). Ein kleinerer Betrag wird als Teilzahlung gebucht."
    }

    private func save() {
        guard paymentAmountMessage == nil else { return }
        var updatedDraft = draft
        updatedDraft.payments.append(payment)
        guard model.save(updatedDraft) != nil else {
            saveError = "Zahlung konnte nicht gespeichert werden. Ihre Eingaben bleiben erhalten."
            return
        }
        draft = updatedDraft
        onSave(updatedDraft)
        dismiss()
    }
}
