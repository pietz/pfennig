import Database
import Domain
import ImportPipeline
import Testing

@Suite("Counterparty resolution")
struct CounterpartyResolutionTests {
    @Test("A new transaction matching an existing counterparty compares before mutation")
    func matchedCounterpartyIsNotFalselyChanged() throws {
        let (database, profile) = try Fixture.database()
        let first = Fixture.domesticExpense(profile)
        _ = try Fixture.save(first, in: database, profile: profile)

        var second = Fixture.domesticExpense(profile)
        second.title = "Mobilfunk Oktober"
        let derived = try BookkeepingEngine.derive(second, profile: profile, categories: database.categories())
        let id = try BookkeepingRepository(database).save(derived.draft, issues: derived.issues, actor: .agent)

        #expect(id != first.id)
        #expect(try database.transactionList().count == 2)
    }

    @Test("A new manual transaction does not erase metadata on a matched counterparty")
    func newManualTransactionPreservesCounterpartyMetadata() throws {
        let (database, profile) = try Fixture.database()
        let first = Fixture.domesticExpense(profile)
        _ = try Fixture.save(first, in: database, profile: profile)

        var second = Fixture.domesticExpense(profile)
        second.counterpartyCountryCode = nil
        second.counterpartyVatId = nil
        second.title = "Mobilfunk Oktober"
        let id = try Fixture.save(second, in: database, profile: profile)
        let detail = try #require(try BookkeepingRepository(database).detail(id: id))

        #expect(detail.counterparty?.countryCode == "DE")
    }
}
