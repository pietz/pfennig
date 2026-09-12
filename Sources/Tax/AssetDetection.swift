import Domain

/// GWG asset detection, §6 Abs. 2 EStG (spec 5.6). V1 has no depreciation; it
/// only flags candidates for manual review.
///
/// Ambiguity note: spec 5.6 describes the *net > 800 EUR* branch as applying
/// to "a hardware/equipment category", but the categories seeded as
/// hardware/equipment (`hardware_equipment`, `furniture`, `vehicles`, spec
/// 17.4) already carry `kind = assetCandidate`, which this function flags
/// unconditionally regardless of amount. This function's only inputs are the
/// category `kind` and the net amount (as specified), so the amount-based
/// branch is applied to any `.expense`-kind allocation above the threshold -
/// a conservative reading that only ever adds an extra soft warning (the
/// user can clear the flag) and never suppresses one that 5.6 requires.
public enum AssetDetection {
    /// Whether `asset_flag` should be set on an allocation.
    public static func assetFlagApplies(categoryKind: CategoryKind, netAmount: Money) -> Bool {
        if categoryKind == .assetCandidate {
            return true
        }
        guard categoryKind == .expense, netAmount.currency == Thresholds.gwgNetThreshold.currency else {
            return false
        }
        return netAmount.absolute > Thresholds.gwgNetThreshold
    }

    /// Category IDs that spec 5.6 calls "a hardware/equipment category" - the
    /// only ones the net > 800 EUR branch applies to (spec 17.4 seeds).
    public static let hardwareCategoryIDs: Set<String> = [
        "hardware_small", "hardware_equipment", "furniture", "vehicles"
    ]

    /// Category-aware variant: `assetCandidate` categories always flag, every
    /// other category only when it is a hardware/equipment one above the GWG
    /// threshold. Use this whenever the category ID is known, so that an
    /// expensive consulting invoice does not raise an asset warning.
    public static func assetFlagApplies(categoryID: String, categoryKind: CategoryKind, netAmount: Money) -> Bool {
        if categoryKind == .assetCandidate {
            return true
        }
        guard hardwareCategoryIDs.contains(categoryID) else { return false }
        return assetFlagApplies(categoryKind: categoryKind, netAmount: netAmount)
    }
}
