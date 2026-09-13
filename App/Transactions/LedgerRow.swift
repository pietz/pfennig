import Database
import Domain
import SwiftUI

/// One line of the main table (spec 6.2). Committed transactions and pending
/// proposals share it, so a proposal appears in the ledger the moment the
/// analysis finishes (spec 7.2, 14.3).
struct LedgerRow: Identifiable, Hashable {
    var id: String
    var isProposal: Bool
    var name: String
    var subtitle: String?
    var date: LocalDate?
    var dateOrigin: String
    var amount: Money?
    var secondaryAmount: Money?
    var paymentStatus: PaymentStatus?
    var status: DisplayStatus

    init(_ item: TransactionListItem) {
        id = item.id
        isProposal = false
        name = item.displayName
        subtitle = item.counterpartyName != nil ? item.title : nil
        date = item.relevantDate
        dateOrigin = item.relevantDateOrigin
        amount = item.bookedAmount
        secondaryAmount = item.originalAmount
        paymentStatus = item.paymentStatus
        status = item.displayStatus
    }

    init(_ proposal: ProposalRecord) {
        let summary = proposal.summary
        id = proposal.id
        isProposal = true
        name = summary?.counterpartyName ?? "Unbekannte Firma"
        subtitle = summary?.categoryName
        date = summary?.invoiceDate
        dateOrigin = "Rechnung"
        amount = summary?.amount
        secondaryAmount = nil
        paymentStatus = nil
        status = proposal.policyDecision == .blocked
            ? DisplayStatus(label: "Konflikt", symbol: "xmark.octagon", tint: .red)
            : DisplayStatus(label: "Vorschlag", symbol: "sparkles", tint: .orange)
    }
}

/// One compact status per row, derived from the stored review status and the
/// derived payment status (spec 19).
struct DisplayStatus: Hashable {
    let label: String
    let symbol: String
    let tint: Color
}
