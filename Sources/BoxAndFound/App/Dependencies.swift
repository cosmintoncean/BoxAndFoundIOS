import Foundation

/// The composition root.
///
/// Presenters take what they need as initialiser parameters and default those
/// parameters to these, so production wiring is a default argument and a unit
/// test can still pass its own stub. Nothing reads through here at runtime
/// except those defaults.
///
/// The override exists for one caller: the UI test launch path, which runs the
/// real screens against in-memory fixtures so a simulator can actually drive
/// them. It is deliberately write-once-at-launch rather than a general service
/// locator — anything that reaches for it mid-flight is doing something the
/// initialiser parameters already allow.
@MainActor
enum Dependencies {

    /// A struct rather than a growing tuple: every milestone adds a
    /// collaborator, and positional arguments stop being readable at three.
    struct Overrides {
        var inventoryReading: any InventoryReading
        var inventoryWriting: any InventoryWriting
        var households: any HouseholdManaging
        var notifications: any NotificationsReading
        var nudges: any NudgeManaging
    }

    private static var overrides: Overrides?

    static var inventoryReading: any InventoryReading {
        overrides?.inventoryReading ?? InventoryRepository()
    }

    static var inventoryWriting: any InventoryWriting {
        overrides?.inventoryWriting ?? InventoryWriteRepository()
    }

    static var householdManaging: any HouseholdManaging {
        overrides?.households ?? HouseholdRepository()
    }

    static var notifications: any NotificationsReading {
        overrides?.notifications ?? NotificationRepository()
    }

    static var nudges: any NudgeManaging {
        overrides?.nudges ?? NudgeRepository()
    }

    static func use(_ replacements: Overrides) {
        overrides = replacements
    }
}
