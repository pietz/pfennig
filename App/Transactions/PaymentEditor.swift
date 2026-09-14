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
    @State private var amountIsValid = true
    @State private var saveError: String?

    init(
        draft: Binding<TransactionDraft>,
        onSave: @escaping (TransactionDraft) -> Void = { _ in }
    ) {
        _draft = draft
        self.onSave = onSave
        let transaction = draft.wrappedValue
        // Datum and Betrag are the only two facts a manual payment needs; the
        // open remainder and today are almost always the right answer.
        _payment = State(
            initialValue: PaymentDraft(
                direction: transaction.direction == .income ? .inflow : .outflow,
                paymentDate: .today(),
                amountMinor: transaction.openAmountMinor,
                currency: transaction.currency
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
                        DateField(
                            label: "Datum",
                            date: Binding(
                                get: { payment.paymentDate },
                                set: { payment.paymentDate = $0 ?? payment.paymentDate }
                            )
                        )
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
        .frame(width: 420, height: 280)
    }

    private var paymentAmountMessage: String? {
        guard amountIsValid else { return "Betrag ist ungültig. Bitte geben Sie eine Zahl ein." }
        guard payment.amountMinor > 0 else { return "Betrag muss größer als 0 sein." }
        return nil
    }

    private var openAmountHint: String {
        "Offen: \(Format.money(draft.openAmountMinor, currency: draft.currency))."
            + " Ein kleinerer Betrag wird als Teilzahlung gebucht."
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
