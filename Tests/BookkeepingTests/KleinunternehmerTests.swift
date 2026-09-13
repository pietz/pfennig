import AI
import Database
import Domain
import Foundation
import ImportPipeline
import Testing

@Suite("Kleinunternehmer tax core")
struct KleinunternehmerTests {
    private static let invoiceDate = LocalDate(year: 2026, month: 9, day: 5)

    @Test("VAT shown on small-business income remains visible and requires review")
    func domesticIncomeWithVATRequiresReview() {
        let profile = BusinessProfile(name: "Kleinbetrieb", vatStatus: .smallBusiness)
        var draft = domesticExpense(profile, allocationMinor: 10000)
        draft.direction = .income
        draft.allocations = [AllocationDraft(categoryId: "uncategorized", amountMinor: 10000)]

        let derived = BookkeepingEngine.derive(draft, profile: profile)

        #expect(derived.draft.assessment?.treatment == .smallBusiness)
        #expect(derived.draft.assessment?.reasoning?.contains("Kleinunternehmerregelung") == true)
        #expect(derived.draft.assessment?.vatShownMinor == 1900)
        #expect(derived.draft.assessment?.outputVatMinor == 1900)
        #expect(derived.softIssues.contains { $0.code == "TAX_RATE_UNUSUAL" })
    }

    @Test("Domestic supplier VAT remains shown but is not deductible")
    func domesticSupplierVATIsNotDeductible() {
        let profile = BusinessProfile(name: "Kleinbetrieb", vatStatus: .smallBusiness)
        let draft = domesticExpense(profile, allocationMinor: 11900)
        let derived = BookkeepingEngine.derive(draft, profile: profile)

        #expect(derived.draft.assessment?.treatment == .domesticVAT)
        #expect(derived.draft.assessment?.vatShownMinor == 1900)
        #expect(derived.draft.assessment?.deductibleInputVatMinor == 0)
        #expect(!derived.hardIssues.contains { $0.code == "ALLOCATION_SUM_MISMATCH" })

        var netAllocated = draft
        netAllocated.allocations = [AllocationDraft(categoryId: "telecom", amountMinor: 10000)]
        let invalid = BookkeepingEngine.derive(netAllocated, profile: profile)
        #expect(invalid.hardIssues.contains { $0.code == "ALLOCATION_SUM_MISMATCH" })
    }

    @Test("Reverse charge still self-assesses VAT without deductible input VAT")
    func reverseChargeIsNotDeductible() {
        let profile = BusinessProfile(name: "Kleinbetrieb", vatStatus: .smallBusiness)
        let draft = TransactionDraft(
            businessProfileId: profile.id,
            counterpartyName: "SaaS Ireland Ltd",
            counterpartyCountryCode: "IE",
            counterpartyVatId: "IE1234567A",
            direction: .expense,
            transactionType: .invoice,
            invoiceNumber: "IE-1",
            invoiceDate: Self.invoiceDate,
            netMinor: 7139,
            taxMinor: 0,
            grossMinor: 7139,
            supplyType: .digitalService,
            components: [TaxComponentDraft(kind: .reverseChargeNote, rate: "0", netMinor: 7139, taxMinor: 0)],
            allocations: [AllocationDraft(categoryId: "software_subscriptions", amountMinor: 7139)]
        )

        let assessment = BookkeepingEngine.derive(draft, profile: profile).draft.assessment
        #expect(assessment?.treatment == .reverseCharge)
        #expect(assessment?.selfAssessedVatMinor == 1356)
        #expect(assessment?.deductibleInputVatMinor == 0)
    }

    @Test("EU goods remain unresolved because the acquisition threshold is out of scope")
    func intraCommunityAcquisitionRequiresReview() {
        let profile = BusinessProfile(name: "Kleinbetrieb", vatStatus: .smallBusiness)
        let draft = TransactionDraft(
            businessProfileId: profile.id,
            counterpartyName: "Hardware France SAS",
            counterpartyCountryCode: "FR",
            counterpartyVatId: "FR12345678901",
            direction: .expense,
            transactionType: .invoice,
            invoiceNumber: "FR-1",
            invoiceDate: Self.invoiceDate,
            netMinor: 10000,
            taxMinor: 0,
            grossMinor: 10000,
            supplyType: .goods,
            components: [TaxComponentDraft(kind: .zero, rate: "0", netMinor: 10000, taxMinor: 0)],
            allocations: [AllocationDraft(categoryId: "hardware", amountMinor: 10000)]
        )

        let assessment = BookkeepingEngine.derive(draft, profile: profile).draft.assessment
        #expect(assessment?.treatment == .unknown)
        #expect(assessment?.selfAssessedVatMinor == nil)
        #expect(assessment?.deductibleInputVatMinor == 0)
    }

    @Test("Taxable domestic expense keeps deductible VAT and net allocation")
    func taxableProfileRemainsUnchanged() {
        let profile = BusinessProfile(name: "Regelbesteuerter Betrieb", vatStatus: .taxable)
        let derived = BookkeepingEngine.derive(domesticExpense(profile, allocationMinor: 10000), profile: profile)

        #expect(derived.draft.assessment?.deductibleInputVatMinor == 1900)
        #expect(!derived.hardIssues.contains { $0.code == "ALLOCATION_SUM_MISMATCH" })
    }

    @Test("Small-business import allocations use gross supplier amounts")
    func importAllocationsUseGross() throws {
        let profile = BusinessProfile(name: "Kleinbetrieb", vatStatus: .smallBusiness)
        let extraction = try JSONDecoder().decode(DocumentExtraction.self, from: Data("""
        {
          "documentType": "invoice",
          "direction": "expense",
          "counterparty": {"name": "Lieferant GmbH", "countryCode": "DE", "vatId": "DE123456789", "street": null, "postalCode": null, "city": null},
          "invoice": {"invoiceNumber": "DE-1", "invoiceDate": "2026-09-05", "serviceDate": "2026-09-05", "servicePeriodStart": null, "servicePeriodEnd": null, "currency": "EUR", "netAmount": "100.00", "taxAmount": "19.00", "grossAmount": "119.00", "statedEurEquivalent": null},
          "taxComponents": [{"rate": "19", "netAmount": "100.00", "taxAmount": "19.00", "kind": "standard"}],
          "taxTreatmentHint": {"treatment": "domesticVAT", "confidence": 0.99, "reasoning": "VAT shown"},
          "lineItems": [{"description": "Lieferung", "netAmount": "100.00", "categoryHint": "uncategorized", "assetCandidate": false}],
          "paymentInfo": {"paymentMethodHint": null, "paidIndicator": "unknown", "paymentDate": null, "iban": null, "reference": null},
          "missingFields": [],
          "warnings": []
        }
        """.utf8))

        let result = try ExtractionNormalizer.normalize(
            extraction,
            document: nil,
            profile: profile,
            categoryIDs: ["uncategorized"]
        )
        #expect(result.draft.allocations.count == 1)
        #expect(result.draft.allocations[0].amountMinor == 11900)
    }

    private func domesticExpense(_ profile: BusinessProfile, allocationMinor: Int64) -> TransactionDraft {
        TransactionDraft(
            businessProfileId: profile.id,
            counterpartyName: "Lieferant GmbH",
            counterpartyCountryCode: "DE",
            counterpartyVatId: "DE123456789",
            direction: .expense,
            transactionType: .invoice,
            invoiceNumber: "DE-1",
            invoiceDate: Self.invoiceDate,
            serviceDate: Self.invoiceDate,
            netMinor: 10000,
            taxMinor: 1900,
            grossMinor: 11900,
            supplyType: .service,
            components: [TaxComponentDraft(kind: .standard, rate: "19", netMinor: 10000, taxMinor: 1900)],
            allocations: [AllocationDraft(categoryId: "telecom", amountMinor: allocationMinor)]
        )
    }
}
