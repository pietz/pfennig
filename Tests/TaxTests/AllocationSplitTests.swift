import Domain
@testable import Tax
import Testing

@Suite("Anteilige Aufteilung von Zahlungen")
struct AllocationSplitTests {
    private func component(_ rate: String?, net: Int64, tax: Int64) -> AllocationSplitter.Component {
        AllocationSplitter.Component(rate: rate, netMinor: net, taxMinor: tax)
    }

    @Test("Zwei Teilzahlungen einer 19-%-Rechnung ergeben zusammen exakt den Vorgang")
    func partialPaymentsSumExactly() {
        let components = [component("19", net: 100_000, tax: 19000)]
        let slices = AllocationSplitter.split(components: components, allocations: [50000, 69000])

        #expect(slices[0][0].baseMinor == 42017)
        #expect(slices[0][0].taxMinor == 7983)
        #expect(slices[0][0].grossMinor == 50000)
        #expect(slices[1][0].grossMinor == 69000)
        #expect(slices[0][0].baseMinor + slices[1][0].baseMinor == 100_000)
        #expect(slices[0][0].taxMinor + slices[1][0].taxMinor == 19000)
    }

    @Test("Mischbeleg 7 %/19 % verteilt centgenau")
    func mixedRatesAreCentExact() {
        let components = [component("19", net: 10000, tax: 1900), component("7", net: 5000, tax: 350)]
        let slices = AllocationSplitter.split(components: components, allocations: [10000, 7250])

        #expect(slices[0].reduce(Int64(0)) { $0 + $1.grossMinor } == 10000)
        #expect(slices[1].reduce(Int64(0)) { $0 + $1.grossMinor } == 7250)

        #expect(slices[0][0].baseMinor + slices[1][0].baseMinor == 10000)
        #expect(slices[0][0].taxMinor + slices[1][0].taxMinor == 1900)
        #expect(slices[0][1].baseMinor + slices[1][1].baseMinor == 5000)
        #expect(slices[0][1].taxMinor + slices[1][1].taxMinor == 350)
    }

    @Test("Der Restcent geht an den Anteil mit dem größten Rundungsrest")
    func largestRemainderWinsTheLeftoverCent() {
        // 1 cent over two equal buckets: the earlier bucket wins the tie.
        #expect(AllocationSplitter.apportion(total: 1, weights: [50, 50]) == [1, 0])
        // 2 cents over three equal buckets: the first two, in order.
        #expect(AllocationSplitter.apportion(total: 2, weights: [10, 10, 10]) == [1, 1, 0])
        // The bucket that lost the most to truncation is served first.
        #expect(AllocationSplitter.apportion(total: 10, weights: [1, 2, 97]) == [0, 0, 10])
        // The full amount always reproduces the weights exactly.
        #expect(AllocationSplitter.apportion(total: 119_000, weights: [100_000, 19000]) == [100_000, 19000])
    }

    @Test("Jede Aufteilung summiert auf den zugeteilten Betrag")
    func everySplitSumsToItsAllocation() {
        let components = [
            component("19", net: 3333, tax: 633),
            component("7", net: 1111, tax: 78),
            component("0", net: 7, tax: 0)
        ]
        let gross = AllocationSplitter.grossMinor(of: components)
        for allocation in stride(from: Int64(0), through: gross, by: 1) {
            let slices = AllocationSplitter.split(components: components, allocations: [allocation])
            #expect(slices[0].reduce(Int64(0)) { $0 + $1.grossMinor } == allocation)
        }
    }

    @Test("Viele Teilzahlungen summieren exakt auf die Steuerkomponenten")
    func manyInstalmentsStayExact() {
        let components = [component("19", net: 3333, tax: 633), component("7", net: 1111, tax: 78)]
        let gross = AllocationSplitter.grossMinor(of: components)
        var allocations = [Int64](repeating: 7, count: Int(gross / 7))
        allocations.append(gross - allocations.reduce(Int64(0), +))

        let slices = AllocationSplitter.split(components: components, allocations: allocations)
        let base19 = slices.reduce(Int64(0)) { $0 + $1[0].baseMinor }
        let tax19 = slices.reduce(Int64(0)) { $0 + $1[0].taxMinor }
        let base7 = slices.reduce(Int64(0)) { $0 + $1[1].baseMinor }
        let tax7 = slices.reduce(Int64(0)) { $0 + $1[1].taxMinor }
        #expect(base19 == 3333)
        #expect(tax19 == 633)
        #expect(base7 == 1111)
        #expect(tax7 == 78)
    }

    @Test("Gutschriften spiegeln die Aufteilung der Rechnung")
    func creditNotesMirrorTheInvoice() {
        let invoice = [component("19", net: 100_000, tax: 19000)]
        let creditNote = [component("19", net: -100_000, tax: -19000)]
        let paid = AllocationSplitter.split(components: invoice, allocations: [50000])
        let refunded = AllocationSplitter.split(components: creditNote, allocations: [-50000])
        #expect(refunded[0][0].baseMinor == -paid[0][0].baseMinor)
        #expect(refunded[0][0].taxMinor == -paid[0][0].taxMinor)
    }

    @Test("Ein Vorgang ohne Betrag verliert die Zahlung nicht")
    func zeroWeightKeepsTheAmount() {
        let slices = AllocationSplitter.split(
            components: [component(nil, net: 0, tax: 0)],
            allocations: [1234]
        )
        #expect(slices[0][0].grossMinor == 1234)
    }

    @Test("Steuersätze werden auf eine kanonische Form gebracht")
    func normalizesRates() {
        #expect(AllocationSplitter.normalizedRate("19") == "19")
        #expect(AllocationSplitter.normalizedRate("19.0") == "19")
        #expect(AllocationSplitter.normalizedRate("19,00") == "19")
        #expect(AllocationSplitter.normalizedRate(" 7 % ") == "7")
        #expect(AllocationSplitter.normalizedRate("0") == "0")
        #expect(AllocationSplitter.normalizedRate(nil) == nil)
        #expect(AllocationSplitter.normalizedRate("") == nil)
        #expect(AllocationSplitter.normalizedRate("regulär") == nil)
    }
}
