import Foundation

/// Remembers which household was last opened, so returning to the app does not
/// ask again. The web client keeps the same thing in
/// `localStorage.activeHouseholdId`, and Android in a DataStore preference.
///
/// Not `Sendable`: `UserDefaults` is not, and this does not need to be. The
/// store is held by a main-actor presenter and read from there, so nothing
/// carries it across an isolation boundary. Marking it `@unchecked Sendable`
/// to say so would be claiming a guarantee nobody needs.
///
/// The id is a hint, never an authority: `resolve` validates it against the
/// households actually returned, so being removed from one cannot strand you
/// on a screen you can no longer read.
struct ActiveHouseholdStore {
    private let defaults: UserDefaults
    private let key = "activeHouseholdId"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var activeHouseholdID: String? {
        defaults.string(forKey: key)
    }

    func set(_ householdID: String) {
        defaults.set(householdID, forKey: key)
    }

    func clear() {
        defaults.removeObject(forKey: key)
    }

    /// The household to open: the remembered one if it is still visible, else
    /// the first. Nil only when there are none.
    func resolve(from households: [Household]) -> Household? {
        guard !households.isEmpty else { return nil }
        if let remembered = activeHouseholdID,
           let match = households.first(where: { $0.id == remembered }) {
            return match
        }
        return households.first
    }
}
