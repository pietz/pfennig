import Domain
import Foundation

/// The part of one payment allocation that falls on a single tax component.
public struct TaxSlice: Sendable, Equatable {
    /// Normalized decimal rate string of the component ("19", "7", "0"), or
    /// `nil` when the component carries no rate (reverse-charge notes, fees).
    public let rate: String?
    public let kind: TaxComponentKind
    /// Bemessungsgrundlage share, EUR minor units.
    public let baseMinor: Int64
    /// VAT share, EUR minor units.
    public let taxMinor: Int64

    public init(rate: String?, kind: TaxComponentKind, baseMinor: Int64, taxMinor: Int64) {
        self.rate = rate
        self.kind = kind
        self.baseMinor = baseMinor
        self.taxMinor = taxMinor
    }

    public var grossMinor: Int64 {
        baseMinor + taxMinor
    }
}

/// Splits payment allocations proportionally across a transaction's tax
/// components (spec `ustva-preparation.md`, "Fachliche Regeln").
///
/// ## Why this is not a plain per-allocation rounding
///
/// Under Ist-Versteuerung a partly paid invoice contributes to several
/// reporting periods. Each allocation must carry its proportional share of
/// every rate bucket, and the shares of all allocations of a fully paid
/// transaction must add up to the transaction's own component totals **to the
/// cent** - otherwise a 7 %/19 % receipt paid in two instalments would report
/// one cent too much or too little, permanently.
///
/// Rounding each allocation independently does not achieve that. Two 50 %
/// instalments of a 1000-cent transaction with two 500-cent components would
/// each round their own halves and can drift by a cent per allocation.
///
/// ## Method
///
/// The splitter therefore apportions **cumulatively** and reports differences:
///
/// 1. Allocations are processed in the caller's (deterministic) order.
/// 2. For a running total `x` of everything allocated up to and including the
///    current allocation, `x` is apportioned over the flattened bucket list
///    `[net₁, tax₁, net₂, tax₂, …]` using the **largest-remainder method**:
///    every bucket first gets `x · wᵢ / Σw` truncated toward zero, then the
///    leftover units go one at a time to the buckets with the largest
///    truncation remainder, ties broken by bucket order.
/// 3. The slice reported for an allocation is the apportionment of the new
///    running total minus the apportionment of the previous one.
///
/// Because step 3 telescopes, the slices of all allocations always sum to the
/// apportionment of the total allocated amount; and because the largest
/// remainder method is exact when `x == Σw` (every remainder is zero), a fully
/// paid transaction reproduces its component totals exactly. The method is
/// deterministic: no floating point, no dictionary iteration order, and ties
/// always resolve to the earlier component.
///
/// Negative transactions (credit notes, refunds) are mirrored: the whole
/// apportionment is computed on the negated values and negated back, so a
/// credit note splits exactly like the invoice it reverses.
public enum AllocationSplitter {
    /// One tax component of the transaction being split.
    public struct Component: Sendable, Equatable {
        public let rate: String?
        public let kind: TaxComponentKind
        public let netMinor: Int64
        public let taxMinor: Int64

        public init(rate: String?, kind: TaxComponentKind, netMinor: Int64, taxMinor: Int64) {
            self.rate = rate
            self.kind = kind
            self.netMinor = netMinor
            self.taxMinor = taxMinor
        }

        public var grossMinor: Int64 {
            netMinor + taxMinor
        }
    }

    /// Gross total of the components; the denominator every allocation is
    /// measured against. Callers compare it with the transaction's own gross
    /// amount and raise a `componentMismatch` exception when they differ.
    public static func grossMinor(of components: [Component]) -> Int64 {
        components.reduce(Int64(0)) { $0 + $1.grossMinor }
    }

    /// Splits `allocations` (in exactly the given order) across `components`.
    /// Returns one slice array per allocation, in the same order.
    public static func split(components: [Component], allocations: [Int64]) -> [[TaxSlice]] {
        let weights = buckets(of: components)
        var previous = apportion(total: 0, weights: weights)
        var running: Int64 = 0
        var result: [[TaxSlice]] = []
        result.reserveCapacity(allocations.count)
        for allocation in allocations {
            running += allocation
            let current = apportion(total: running, weights: weights)
            result.append(slices(from: previous, to: current, components: components))
            previous = current
        }
        return result
    }

    /// Splits a single allocation, given the sum of all allocations that come
    /// before it in the same deterministic order. `split(components:allocations:)`
    /// is the same computation for a whole list and should be preferred.
    public static func slice(
        components: [Component],
        allocatedBefore: Int64,
        allocatedMinor: Int64
    ) -> [TaxSlice] {
        let weights = buckets(of: components)
        let previous = apportion(total: allocatedBefore, weights: weights)
        let current = apportion(total: allocatedBefore + allocatedMinor, weights: weights)
        return slices(from: previous, to: current, components: components)
    }

    // MARK: - Rate normalization

    /// Normalizes a stored rate string ("19", "19.0", "19,00", "19 %") to its
    /// canonical form ("19"). Returns `nil` for absent or unreadable rates so
    /// the caller can treat the component as unrated rather than guess.
    public static func normalizedRate(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let cleaned = raw.replacingOccurrences(of: "%", with: "").trimmingCharacters(in: .whitespaces)
        guard !cleaned.isEmpty, let value = try? Money.parseDecimal(cleaned) else { return nil }
        let whole = Money.roundHalfUp(value)
        guard whole == value else { return "\(value)" }
        return "\(NSDecimalNumber(decimal: whole).int64Value)"
    }

    // MARK: - Apportionment

    private static func buckets(of components: [Component]) -> [Int64] {
        var weights: [Int64] = []
        weights.reserveCapacity(components.count * 2)
        for component in components {
            weights.append(component.netMinor)
            weights.append(component.taxMinor)
        }
        return weights
    }

    private static func slices(from previous: [Int64], to current: [Int64], components: [Component]) -> [TaxSlice] {
        components.enumerated().map { index, component in
            TaxSlice(
                rate: component.rate,
                kind: component.kind,
                baseMinor: current[index * 2] - previous[index * 2],
                taxMinor: current[index * 2 + 1] - previous[index * 2 + 1]
            )
        }
    }

    /// Largest-remainder apportionment of `total` over `weights`. The result
    /// always sums to `total` exactly, and equals `weights` when `total` is
    /// the weight sum.
    static func apportion(total rawTotal: Int64, weights rawWeights: [Int64]) -> [Int64] {
        guard !rawWeights.isEmpty else { return [] }
        let rawSum = rawWeights.reduce(Int64(0), +)
        guard rawSum != 0 else {
            // Nothing to be proportional to (an all-zero transaction). Keep
            // the total rather than dropping it; it lands on the first bucket.
            var degenerate = [Int64](repeating: 0, count: rawWeights.count)
            degenerate[0] = rawTotal
            return degenerate
        }

        // Mirror negative transactions so the denominator is always positive.
        let mirrored = rawSum < 0
        let total = mirrored ? -rawTotal : rawTotal
        let weights = mirrored ? rawWeights.map { -$0 } : rawWeights
        let denominator = mirrored ? -rawSum : rawSum

        var quotients = [Int64](repeating: 0, count: weights.count)
        var remainders = [Int64](repeating: 0, count: weights.count)
        for (index, weight) in weights.enumerated() {
            let (quotient, remainder) = divide(total, weight, by: denominator)
            quotients[index] = quotient
            remainders[index] = remainder
        }

        var leftover = total - quotients.reduce(Int64(0), +)
        if leftover != 0 {
            let step: Int64 = leftover > 0 ? 1 : -1
            let order = remainders.indices.sorted { lhs, rhs in
                if remainders[lhs] != remainders[rhs] {
                    return step > 0 ? remainders[lhs] > remainders[rhs] : remainders[lhs] < remainders[rhs]
                }
                return lhs < rhs
            }
            var position = 0
            while leftover != 0 {
                quotients[order[position % order.count]] += step
                leftover -= step
                position += 1
            }
        }

        return mirrored ? quotients.map { -$0 } : quotients
    }

    /// `total * weight / denominator`, truncated toward zero, plus the exact
    /// remainder. Computed through a 128-bit intermediate so large cent
    /// amounts cannot overflow. `denominator` must be positive.
    private static func divide(_ total: Int64, _ weight: Int64, by denominator: Int64) -> (Int64, Int64) {
        guard total != 0, weight != 0 else { return (0, 0) }
        let product = total.magnitude.multipliedFullWidth(by: weight.magnitude)
        let (quotient, remainder) = UInt64(denominator).dividingFullWidth(product)
        let negative = (total < 0) != (weight < 0)
        return negative ? (-Int64(quotient), -Int64(remainder)) : (Int64(quotient), Int64(remainder))
    }
}
