#if DEBUG
    import Domain
    import Foundation
    import GRDB

    public extension AppDatabase {
        /// Three sample transactions - paid, partially paid, unpaid - written once
        /// into a freshly created archive. Debug builds only.
        func seedSampleData(businessProfileID: String) throws {
            try writer.write { db in
                guard try TransactionRecord.fetchCount(db) == 0 else { return }
                try SampleData.insert(db, businessProfileID: businessProfileID)
            }
        }
    }

    enum SampleData {
        static func insert(_ db: Database, businessProfileID: String) throws {
            let account = Account(
                businessProfileId: businessProfileID,
                name: "Geschäftskonto",
                kind: .bank,
                iban: "DE02120300000000202051"
            )
            try account.insert(db)

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
            try adobeTransaction.insert(db)
            try BookkeepingAllocation(
                transactionId: adobeTransaction.id,
                categoryId: "software_subscriptions",
                amountMinor: 7139,
                description: "Creative Cloud All Apps"
            ).insert(db)
            try TaxAssessment(
                transactionId: adobeTransaction.id,
                treatment: .reverseCharge,
                taxCountry: "DE",
                customerType: .b2b,
                supplyType: .digitalService,
                taxableBaseMinor: 7139,
                vatShownMinor: 0,
                selfAssessedVatMinor: 1356,
                deductibleInputVatMinor: 1356,
                inputVatDate: LocalDate(year: 2026, month: 8, day: 31),
                status: .confirmed,
                reasoning: "Irischer Anbieter, deutsche USt-IdNr. auf der Rechnung"
            ).insert(db)
            try pay(
                db,
                account: account,
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
            try invoice.insert(db)
            try BookkeepingAllocation(
                transactionId: invoice.id,
                categoryId: "revenue_services",
                amountMinor: 200_000
            ).insert(db)
            try TaxAssessment(
                transactionId: invoice.id,
                treatment: .domesticVAT,
                taxCountry: "DE",
                customerType: .b2b,
                supplyType: .service,
                customerVatId: "DE123456789",
                taxableBaseMinor: 200_000,
                vatShownMinor: 38000,
                outputVatMinor: 38000,
                outputVatDate: LocalDate(year: 2026, month: 9, day: 10),
                status: .proposed
            ).insert(db)
            try pay(
                db,
                account: account,
                transaction: invoice,
                amountMinor: 100_000,
                date: LocalDate(year: 2026, month: 9, day: 10),
                direction: .inflow,
                counterparty: "Muster GmbH"
            )

            // 3 - unpaid expense invoice
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
                originalNetMinor: 4197, originalTaxMinor: 798, originalGrossMinor: 4995,
                bookedNetMinor: 4197, bookedTaxMinor: 798, bookedGrossMinor: 4995,
                reviewStatus: .needsReview
            )
            try telekomTransaction.insert(db)
            try BookkeepingAllocation(
                transactionId: telekomTransaction.id,
                categoryId: "telecom",
                amountMinor: 4197
            ).insert(db)
            try TaxAssessment(
                transactionId: telekomTransaction.id,
                treatment: .domesticVAT,
                taxCountry: "DE",
                supplyType: .service,
                taxableBaseMinor: 4197,
                vatShownMinor: 798,
                deductibleInputVatMinor: 798,
                inputVatDate: LocalDate(year: 2026, month: 9, day: 5),
                status: .proposed
            ).insert(db)
        }

        private static func pay(
            _ db: Database,
            account: Account,
            transaction: TransactionRecord,
            amountMinor: Int64,
            date: LocalDate,
            direction: PaymentDirection,
            counterparty: String
        ) throws {
            let payment = Payment(
                accountId: account.id,
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
        }
    }
#endif
