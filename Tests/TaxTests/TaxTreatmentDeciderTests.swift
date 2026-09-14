import Domain
@testable import Tax
import Testing

@Suite("TaxTreatmentDecider - rule branches")
struct TaxTreatmentDeciderTests {
    static let profile = ProfileFacts(countryCode: "DE", vatStatus: .taxable, accountingMethod: .cash)

    @Test("Domestic counterparty with VAT shown -> domesticVAT")
    func domesticWithVAT() {
        let decision = TaxTreatmentDecider.decide(TaxTreatmentDecisionInput(
            profile: Self.profile, direction: .expense,
            counterparty: CounterpartyTaxFacts(countryCode: "DE", hasVATId: true),
            supplyType: .goods, document: DocumentTaxFacts(taxShown: true, rateComponents: ["19"])
        ))
        #expect(decision.treatment == .domesticVAT)
    }

    @Test("EU counterparty, expense, service, no VAT shown -> reverseCharge")
    func euExpenseServiceNoVAT() {
        let decision = TaxTreatmentDecider.decide(TaxTreatmentDecisionInput(
            profile: Self.profile, direction: .expense,
            counterparty: CounterpartyTaxFacts(countryCode: "IE", hasVATId: true),
            supplyType: .service, document: DocumentTaxFacts(
                taxShown: false,
                reverseChargeNotePresent: true,
                rateComponents: ["0"]
            )
        ))
        #expect(decision.treatment == .reverseCharge)
    }

    @Test("EU counterparty, expense, goods, no VAT shown -> intraCommunityAcquisition")
    func euExpenseGoodsNoVAT() {
        let decision = TaxTreatmentDecider.decide(TaxTreatmentDecisionInput(
            profile: Self.profile, direction: .expense,
            counterparty: CounterpartyTaxFacts(countryCode: "FR", hasVATId: true),
            supplyType: .goods, document: DocumentTaxFacts(taxShown: false, rateComponents: ["0"])
        ))
        #expect(decision.treatment == .intraCommunityAcquisition)
    }

    @Test("Third-country expense service, no VAT shown -> reverseCharge regardless of origin")
    func thirdCountryExpenseServiceNoVAT() {
        let decision = TaxTreatmentDecider.decide(TaxTreatmentDecisionInput(
            profile: Self.profile, direction: .expense,
            counterparty: CounterpartyTaxFacts(countryCode: "US", hasVATId: false),
            supplyType: .digitalService, document: DocumentTaxFacts(taxShown: false, rateComponents: ["0"])
        ))
        #expect(decision.treatment == .reverseCharge)
    }

    @Test("Income to EU B2B with VAT ID and no VAT -> reverseCharge")
    func incomeEUB2BWithVATId() {
        let decision = TaxTreatmentDecider.decide(TaxTreatmentDecisionInput(
            profile: Self.profile, direction: .income,
            counterparty: CounterpartyTaxFacts(countryCode: "FR", hasVATId: true),
            supplyType: .service, document: DocumentTaxFacts(
                taxShown: false,
                reverseChargeNotePresent: true,
                rateComponents: ["0"]
            )
        ))
        #expect(decision.treatment == .reverseCharge)
        #expect(!decision.softIssues.contains(.missingCustomerVATIdOnReverseChargeIncome))
    }

    @Test("Income to EU B2B service without VAT ID still decides reverseCharge but warns")
    func incomeEUB2BMissingVATId() {
        let decision = TaxTreatmentDecider.decide(TaxTreatmentDecisionInput(
            profile: Self.profile, direction: .income,
            counterparty: CounterpartyTaxFacts(countryCode: "FR", hasVATId: false),
            supplyType: .service, document: DocumentTaxFacts(taxShown: false, rateComponents: ["0"])
        ))
        #expect(decision.treatment == .reverseCharge)
        #expect(decision.softIssues.contains(.missingCustomerVATIdOnReverseChargeIncome))
    }

    @Test("Income to third country without VAT -> export")
    func incomeThirdCountryNoVAT() {
        let decision = TaxTreatmentDecider.decide(TaxTreatmentDecisionInput(
            profile: Self.profile, direction: .income,
            counterparty: CounterpartyTaxFacts(countryCode: "US", hasVATId: false),
            supplyType: .service, document: DocumentTaxFacts(taxShown: false, rateComponents: ["0"])
        ))
        #expect(decision.treatment == .export)
    }

    @Test("Small-business profile domestic income without VAT -> smallBusiness")
    func smallBusinessDomesticIncomeWithoutVAT() {
        let decision = TaxTreatmentDecider.decide(TaxTreatmentDecisionInput(
            profile: ProfileFacts(countryCode: "DE", vatStatus: .smallBusiness, accountingMethod: .cash),
            direction: .income,
            counterparty: CounterpartyTaxFacts(countryCode: "DE", hasVATId: false),
            supplyType: .service,
            document: DocumentTaxFacts(taxShown: false, rateComponents: ["0"])
        ))
        #expect(decision.treatment == .smallBusiness)
    }

    @Test("Explicit small-business hint may decide a domestic zero-tax supplier invoice")
    func smallBusinessHintForDomesticSupplier() {
        let decision = TaxTreatmentDecider.decide(TaxTreatmentDecisionInput(
            profile: Self.profile,
            direction: .expense,
            counterparty: CounterpartyTaxFacts(countryCode: "DE", hasVATId: false),
            supplyType: .service,
            document: DocumentTaxFacts(taxShown: false, rateComponents: ["0"]),
            modelHint: ModelTreatmentHint(treatment: .smallBusiness)
        ))
        #expect(decision.treatment == .smallBusiness)
        #expect(!decision.softIssues.contains(.hintDisagreesWithFacts))
    }

    @Test("Small-business hint cannot reclassify taxable-profile income")
    func smallBusinessHintDoesNotReclassifyTaxableIncome() {
        let decision = TaxTreatmentDecider.decide(TaxTreatmentDecisionInput(
            profile: Self.profile,
            direction: .income,
            counterparty: CounterpartyTaxFacts(countryCode: "DE", hasVATId: false),
            supplyType: .service,
            document: DocumentTaxFacts(taxShown: false, rateComponents: ["0"]),
            modelHint: ModelTreatmentHint(treatment: .smallBusiness)
        ))
        #expect(decision.treatment == .unknown)
    }

    @Test("Shown domestic VAT remains domesticVAT for a small-business profile")
    func smallBusinessProfilePreservesShownVAT() {
        let decision = TaxTreatmentDecider.decide(TaxTreatmentDecisionInput(
            profile: ProfileFacts(countryCode: "DE", vatStatus: .smallBusiness, accountingMethod: .cash),
            direction: .expense,
            counterparty: CounterpartyTaxFacts(countryCode: "DE", hasVATId: true),
            supplyType: .goods,
            document: DocumentTaxFacts(taxShown: true, rateComponents: ["19"])
        ))
        #expect(decision.treatment == .domesticVAT)
    }

    @Test("Explicit hint of nonTaxable is accepted when no VAT shown")
    func hintNonTaxableAccepted() {
        let decision = TaxTreatmentDecider.decide(TaxTreatmentDecisionInput(
            profile: Self.profile, direction: .expense,
            counterparty: CounterpartyTaxFacts(countryCode: "DE", hasVATId: false),
            supplyType: .service, document: DocumentTaxFacts(taxShown: false, rateComponents: []),
            modelHint: ModelTreatmentHint(treatment: .nonTaxable)
        ))
        #expect(decision.treatment == .nonTaxable)
    }

    @Test("Explicit hint of exempt is accepted when no VAT shown")
    func hintExemptAccepted() {
        let decision = TaxTreatmentDecider.decide(TaxTreatmentDecisionInput(
            profile: Self.profile, direction: .expense,
            counterparty: CounterpartyTaxFacts(countryCode: "DE", hasVATId: false),
            supplyType: .service, document: DocumentTaxFacts(taxShown: false, rateComponents: []),
            modelHint: ModelTreatmentHint(treatment: .exempt)
        ))
        #expect(decision.treatment == .exempt)
    }

    @Test("A hint of nonTaxable is rejected when VAT is shown - falls through to unknown")
    func hintRejectedWhenVATShown() {
        let decision = TaxTreatmentDecider.decide(TaxTreatmentDecisionInput(
            profile: Self.profile, direction: .expense,
            counterparty: CounterpartyTaxFacts(countryCode: "DE", hasVATId: false),
            supplyType: .service, document: DocumentTaxFacts(taxShown: true, rateComponents: ["19"]),
            modelHint: ModelTreatmentHint(treatment: .nonTaxable)
        ))
        // Domestic + tax shown always wins first.
        #expect(decision.treatment == .domesticVAT)
    }

    @Test("Otherwise falls back to unknown")
    func fallsBackToUnknown() {
        let decision = TaxTreatmentDecider.decide(TaxTreatmentDecisionInput(
            profile: Self.profile, direction: .expense,
            counterparty: CounterpartyTaxFacts(countryCode: "US", hasVATId: false),
            supplyType: .goods, document: DocumentTaxFacts(taxShown: false, rateComponents: ["0"])
        ))
        #expect(decision.treatment == .unknown)
    }

    @Test("Hint disagreeing with the decided facts is flagged as a soft issue")
    func hintDisagreementFlagged() {
        let decision = TaxTreatmentDecider.decide(TaxTreatmentDecisionInput(
            profile: Self.profile, direction: .expense,
            counterparty: CounterpartyTaxFacts(countryCode: "DE", hasVATId: false),
            supplyType: .goods, document: DocumentTaxFacts(taxShown: true, rateComponents: ["19"]),
            modelHint: ModelTreatmentHint(treatment: .reverseCharge)
        ))
        #expect(decision.treatment == .domesticVAT)
        #expect(decision.softIssues.contains(.hintDisagreesWithFacts))
    }

    @Test("EU counterparty with domestic VAT shown is flagged as a soft issue")
    func euCounterpartyWithDomesticVATFlagged() {
        let decision = TaxTreatmentDecider.decide(TaxTreatmentDecisionInput(
            profile: Self.profile, direction: .expense,
            counterparty: CounterpartyTaxFacts(countryCode: "FR", hasVATId: true),
            supplyType: .service, document: DocumentTaxFacts(taxShown: true, rateComponents: ["19"])
        ))
        #expect(decision.softIssues.contains(.euCounterpartyWithDomesticVATShown))
    }

    @Test("EU member state set includes core member states and excludes DE, UK, US, CH")
    func euMemberStateSet() {
        #expect(TaxTreatmentDecider.euMemberStates.contains("IE"))
        #expect(TaxTreatmentDecider.euMemberStates.contains("FR"))
        #expect(!TaxTreatmentDecider.euMemberStates.contains("DE"))
        #expect(!TaxTreatmentDecider.euMemberStates.contains("GB"))
        #expect(!TaxTreatmentDecider.euMemberStates.contains("US"))
        #expect(!TaxTreatmentDecider.euMemberStates.contains("CH"))
    }
}
