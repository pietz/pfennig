import Database
import Domain
import ImportPipeline
import Testing

@Suite("Manual provenance protection")
struct ManualProtectionTests {
    @Test("An agent recalculation preserves a manual tax treatment")
    func agentRecalculationPreservesManualTreatment() throws {
        let (database, profile) = try Fixture.database()
        var original = Fixture.reverseChargeExpense(profile)
        original.treatmentOverride = .reverseCharge
        let transactionID = try Fixture.save(original, in: database, profile: profile)

        let repository = BookkeepingRepository(database)
        let saved = try #require(try repository.detail(id: transactionID))
        var recalculated = saved.draft
        recalculated.treatmentOverride = nil
        recalculated.assessment?.status = .confirmed
        _ = try repository.save(recalculated, actor: .agent)

        let updated = try #require(try repository.detail(id: transactionID))
        #expect(updated.draft.treatmentOverride == .reverseCharge)
    }
}
