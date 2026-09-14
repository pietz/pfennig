import Database
import Domain
import SwiftUI

/// Records a payment by hand and allocates it to this transaction
/// (spec 17.13, 17.14). Partial payments are allowed: the allocated amount
/// may be smaller than the invoice.
///
/// A refund is the same payment in the opposite direction: money back from a
/// supplier, money returned to a customer. The choice appears only once there
/// is something to give back, because the settled amount may never fall below
/// zero.
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
                direction: transaction.settlingPaymentDirection,
                paymentDate: .today(),
                amountMinor: abs(transaction.openAmountMinor),
                currency: transaction.currency
            )
        )
    }

    private var isRefund: Bool {
        payment.direction != draft.settlingPaymentDirection
    }

    /// The most this payment can settle: what is still open, or - for a
    /// refund - what has been settled so far, because only what was paid can
    /// be given back.
    private var allocationLimitMinor: Int64 {
        abs(isRefund ? draft.netAllocatedMinor : draft.openAmountMinor)
    }

    /// A payment may be larger than what it settles: a bank fee, an exchange
    /// difference, one transfer for two invoices. The surplus is left
    /// unallocated instead of blocking the payment.
    private var allocatedMinor: Int64 {
        min(payment.amountMinor, allocationLimitMinor)
    }

    private var unallocatedMinor: Int64 {
        payment.amountMinor - allocatedMinor
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
                    if draft.canRefund {
                        LabeledContent("Art") {
                            Picker("Art", selection: $payment.direction) {
                                Text(label(for: draft.settlingPaymentDirection))
                                    .tag(draft.settlingPaymentDirection)
                                Text(label(for: draft.settlingPaymentDirection.opposite))
                                    .tag(draft.settlingPaymentDirection.opposite)
                            }
                            .pickerStyle(.segmented)
                            .labelsHidden()
                        }
                    }
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
                    } else if let surplusMessage {
                        IssueRow(severity: .warning, message: surplusMessage)
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

    /// Money moving this way, named from the transaction's point of view.
    private func label(for direction: PaymentDirection) -> LocalizedStringKey {
        let isRefund = direction.isRefund(of: draft.direction)
        if draft.direction == .income {
            return isRefund ? "Rückzahlung" : "Zahlungseingang"
        }
        return isRefund ? "Erstattung" : "Zahlung"
    }

    private var paymentAmountMessage: String? {
        guard amountIsValid else { return "Betrag ist ungültig. Bitte geben Sie eine Zahl ein." }
        guard payment.amountMinor > 0 else { return "Betrag muss größer als 0 sein." }
        guard allocationLimitMinor > 0 else {
            return isRefund
                ? "Für diesen Vorgang wurde noch nichts gezahlt, das erstattet werden könnte."
                : "Für diesen Vorgang ist nichts mehr offen."
        }
        return nil
    }

    /// Everything the transaction cannot absorb stays unallocated; the
    /// bookkeeping never settles more than the booking shows.
    private var surplusMessage: String? {
        guard unallocatedMinor > 0 else { return nil }
        return "Davon werden \(Format.money(allocatedMinor, currency: draft.currency)) diesem Vorgang"
            + " zugeordnet; \(Format.money(unallocatedMinor, currency: draft.currency)) bleiben ohne Zuordnung."
    }

    private var openAmountHint: String {
        if isRefund {
            return "Bisher gezahlt: \(Format.money(allocationLimitMinor, currency: draft.currency))."
                + " Die Erstattung wird gegengerechnet."
        }
        return "Offen: \(Format.money(abs(draft.openAmountMinor), currency: draft.currency))."
            + " Ein kleinerer Betrag wird als Teilzahlung gebucht."
    }

    private func save() {
        guard paymentAmountMessage == nil else { return }
        var updatedDraft = draft
        var payment = payment
        payment.allocatedMinor = allocatedMinor
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
