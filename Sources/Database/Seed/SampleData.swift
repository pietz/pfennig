#if DEBUG
    import Domain
    import Foundation
    import GRDB

    public extension AppDatabase {
        /// Four sample transactions - paid, partially paid, unpaid and a
        /// second reverse-charge case - written once into a freshly created
        /// archive. Debug builds only.
        func seedSampleData(businessProfileID: String) throws {
            try writer.write { db in
                guard try TransactionRecord.fetchCount(db) == 0 else { return }
                try SampleData.insert(db, businessProfileID: businessProfileID)
            }
        }
    }

    enum SampleData {
        static func insert(_ db: Database, businessProfileID: String) throws {
            // 1 - paid expense, reverse charge (the worked example of spec 4.1)
            let adobe = Counterparty(
                displayName: "Adobe Systems Software Ireland Ltd",
                countryCode: "IE",
                vatId: "IE6364992H"
            )
            try adobe.insert(db)
            let adobeTransaction = TransactionRecord(
                businessProfileId: businessProfileID,
                counterpartyId: adobe.id,
                direction: .expense,
                transactionType: .invoice,
                title: "Creative Cloud All Apps",
                invoiceNumber: "IEIN123456",
                invoiceDate: LocalDate(year: 2026, month: 8, day: 31),
                servicePeriodStart: LocalDate(year: 2026, month: 8, day: 1),
                servicePeriodEnd: LocalDate(year: 2026, month: 8, day: 31),
                originalNetMinor: 7139, originalTaxMinor: 0, originalGrossMinor: 7139,
                bookedNetMinor: 7139, bookedTaxMinor: 0, bookedGrossMinor: 7139,
                reviewStatus: .confirmed
            )
            try book(
                db,
                transaction: adobeTransaction,
                category: "software_subscriptions",
                description: "Creative Cloud All Apps",
                components: [(.reverseChargeNote, "0", 7139, 0)],
                assessment: TaxAssessment(
                    transactionId: adobeTransaction.id,
                    treatment: .reverseCharge,
                    customerType: .b2b,
                    supplyType: .digitalService,
                    taxableBaseMinor: 7139,
                    vatShownMinor: 0,
                    selfAssessedVatMinor: 1356,
                    deductibleInputVatMinor: 1356,
                    status: .confirmed
                )
            )
            try pay(
                db,
                transaction: adobeTransaction,
                amountMinor: 7139,
                date: LocalDate(year: 2026, month: 9, day: 2),
                direction: .outflow,
                counterparty: "ADOBE SYSTEMS SOFTWARE IRELAND"
            )

            // 2 - partially paid income invoice
            let client = Counterparty(displayName: "Muster GmbH", countryCode: "DE", vatId: "DE123456789")
            try client.insert(db)
            let invoice = TransactionRecord(
                businessProfileId: businessProfileID,
                counterpartyId: client.id,
                direction: .income,
                transactionType: .invoice,
                title: "Beratung September",
                invoiceNumber: "2026-014",
                invoiceDate: LocalDate(year: 2026, month: 9, day: 1),
                serviceDate: LocalDate(year: 2026, month: 8, day: 28),
                originalNetMinor: 200_000, originalTaxMinor: 38000, originalGrossMinor: 238_000,
                bookedNetMinor: 200_000, bookedTaxMinor: 38000, bookedGrossMinor: 238_000,
                reviewStatus: .unreviewed
            )
            try book(
                db,
                transaction: invoice,
                category: "revenue_services",
                components: [(.standard, "19", 200_000, 38000)],
                assessment: TaxAssessment(
                    transactionId: invoice.id,
                    treatment: .domesticVAT,
                    customerType: .b2b,
                    supplyType: .service,
                    customerVatId: "DE123456789",
                    taxableBaseMinor: 200_000,
                    vatShownMinor: 38000,
                    outputVatMinor: 38000,
                    status: .proposed
                )
            )
            try pay(
                db,
                transaction: invoice,
                amountMinor: 100_000,
                date: LocalDate(year: 2026, month: 9, day: 10),
                direction: .inflow,
                counterparty: "Muster GmbH"
            )

            // 3 - unpaid expense invoice, domestic VAT with two rates
            let telekom = Counterparty(displayName: "Telekom Deutschland GmbH", countryCode: "DE", vatId: "DE122797249")
            try telekom.insert(db)
            let telekomTransaction = TransactionRecord(
                businessProfileId: businessProfileID,
                counterpartyId: telekom.id,
                direction: .expense,
                transactionType: .invoice,
                title: "Mobilfunk September",
                invoiceNumber: "R-2026-9912",
                invoiceDate: LocalDate(year: 2026, month: 9, day: 5),
                serviceDate: LocalDate(year: 2026, month: 9, day: 5),
                originalNetMinor: 4197, originalTaxMinor: 798, originalGrossMinor: 4995,
                bookedNetMinor: 4197, bookedTaxMinor: 798, bookedGrossMinor: 4995,
                reviewStatus: .needsReview
            )
            try book(
                db,
                transaction: telekomTransaction,
                category: "telecom",
                components: [(.standard, "19", 4197, 798)],
                assessment: TaxAssessment(
                    transactionId: telekomTransaction.id,
                    treatment: .domesticVAT,
                    supplyType: .service,
                    taxableBaseMinor: 4197,
                    vatShownMinor: 798,
                    deductibleInputVatMinor: 798,
                    status: .proposed
                )
            )

            // 4 - third-country SaaS, §13b reverse charge with self-assessed VAT (spec 5.4)
            let vercel = Counterparty(displayName: "Vercel Inc.", countryCode: "US")
            try vercel.insert(db)
            let hosting = TransactionRecord(
                businessProfileId: businessProfileID,
                counterpartyId: vercel.id,
                direction: .expense,
                transactionType: .invoice,
                title: "Pro Plan September",
                invoiceNumber: "INV-2026-4471",
                invoiceDate: LocalDate(year: 2026, month: 9, day: 1),
                servicePeriodStart: LocalDate(year: 2026, month: 9, day: 1),
                servicePeriodEnd: LocalDate(year: 2026, month: 9, day: 30),
                originalNetMinor: 2000, originalTaxMinor: 0, originalGrossMinor: 2000,
                bookedNetMinor: 2000, bookedTaxMinor: 0, bookedGrossMinor: 2000,
                reviewStatus: .unreviewed
            )
            try book(
                db,
                transaction: hosting,
                category: "hosting_cloud",
                description: "Vercel Pro",
                components: [(.reverseChargeNote, "0", 2000, 0)],
                assessment: TaxAssessment(
                    transactionId: hosting.id,
                    treatment: .reverseCharge,
                    customerType: .b2b,
                    supplyType: .digitalService,
                    taxableBaseMinor: 2000,
                    vatShownMinor: 0,
                    selfAssessedVatMinor: 380,
                    deductibleInputVatMinor: 380,
                    status: .proposed
                )
            )
            try pay(
                db,
                transaction: hosting,
                amountMinor: 2000,
                date: LocalDate(year: 2026, month: 9, day: 3),
                direction: .outflow,
                counterparty: "VERCEL INC"
            )
        }

        /// Writes one transaction with its allocation, tax components, current
        /// assessment, provenance and the audit event that created it.
        private static func book(
            _ db: Database,
            transaction: TransactionRecord,
            category: String,
            description: String? = nil,
            components: [(TaxComponentKind, String?, Int64, Int64)],
            assessment: TaxAssessment
        ) throws {
            try transaction.insert(db)
            try BookkeepingAllocation(
                transactionId: transaction.id,
                categoryId: category,
                amountMinor: transaction.bookedNetMinor ?? 0,
                description: description
            ).insert(db)
            for (index, component) in components.enumerated() {
                try TaxComponent(
                    transactionId: transaction.id,
                    kind: component.0,
                    rate: component.1,
                    netMinor: component.2,
                    taxMinor: component.3,
                    sortOrder: index
                ).insert(db)
            }
            try assessment.insert(db)
            for field in ["counterpartyId", "invoiceDate", "invoiceNumber", "netAmount", "taxAmount", "grossAmount"] {
                try FieldProvenance(
                    entityType: FieldProvenance.Entity.transaction,
                    entityId: transaction.id,
                    fieldName: field,
                    provenance: .document
                ).insert(db)
            }
            for field in ["treatment", "selfAssessedVat", "deductibleInputVat"] {
                try FieldProvenance(
                    entityType: FieldProvenance.Entity.taxAssessment,
                    entityId: assessment.id,
                    fieldName: field,
                    provenance: .calculated
                ).insert(db)
            }
            try AuditEvent(entityId: transaction.id, action: .create, actor: .import).insert(db)
        }

        private static func pay(
            _ db: Database,
            transaction: TransactionRecord,
            amountMinor: Int64,
            date: LocalDate,
            direction: PaymentDirection,
            counterparty: String
        ) throws {
            let payment = Payment(
                direction: direction,
                paymentDate: date,
                originalAmountMinor: amountMinor,
                bookedAmountMinor: amountMinor,
                counterpartyNameRaw: counterparty,
                reference: transaction.invoiceNumber,
                paymentMethod: .bankTransfer,
                source: .statementLine
            )
            try payment.insert(db)
            try PaymentAllocation(
                paymentId: payment.id,
                transactionId: transaction.id,
                allocatedMinor: amountMinor,
                matchMethod: .exact
            ).insert(db)
            try AuditEvent(entityId: transaction.id, action: .link, actor: .import).insert(db)
        }
    }
#endif
