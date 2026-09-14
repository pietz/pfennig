import Database

/// UStVA settings that are not columns of `business_profiles`.
///
/// Dauerfristverlängerung (§§46-48 UStDV) shifts every filing deadline out by
/// one month. It lives in the generic `settings` table (spec 10.5) rather than
/// in the business profile: it is an approval by the tax office, not a property
/// of the business, and the archive schema needs no change for it.
enum UStVAPreferences {
    static let dauerfristverlaengerungKey = "ustva.dauerfristverlaengerung"

    static func dauerfristverlaengerung(in database: AppDatabase?) -> Bool {
        guard let database else { return false }
        let stored = try? database.setting(Bool.self, forKey: dauerfristverlaengerungKey)
        return stored.flatMap(\.self) ?? false
    }

    static func setDauerfristverlaengerung(_ value: Bool, in database: AppDatabase?) {
        try? database?.setSetting(value, forKey: dauerfristverlaengerungKey)
    }
}
