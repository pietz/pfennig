import AI
import Domain
import Testing

@Suite("Kleinunternehmer-Schnittstelle")
struct KleinunternehmerSurfaceTests {
    @Test("Der Extraktionskontext unterstützt Kleinunternehmer")
    func contextIncludesSmallBusiness() {
        let context = ExtractionContext(
            business: .init(name: "Mara Beispiel", vatStatus: .smallBusiness),
            categories: []
        )

        #expect(context.treatments.contains(.smallBusiness))
    }

    @Test("Der Prompt verlangt einen ausdrücklichen Beleg für §19")
    func promptRequiresDocumentEvidence() {
        let prompt = ExtractionPrompt.render(
            ExtractionContext(
                business: .init(name: "Mara Beispiel", vatStatus: .smallBusiness),
                categories: []
            )
        )

        #expect(prompt.contains("Use `smallBusiness` only when this document"))
        #expect(prompt.contains("Never use"))
        #expect(prompt.contains("merely because the owner's profile"))
        #expect(prompt.contains("does not show that this document uses §19 UStG"))
    }
}
