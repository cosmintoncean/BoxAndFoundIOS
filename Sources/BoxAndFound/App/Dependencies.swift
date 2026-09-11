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

    private static var overrides: (reading: any InventoryReading, writing: any InventoryWriting)?

    static var inventoryReading: any InventoryReading {
        overrides?.reading ?? InventoryRepository()
    }

    static var inventoryWriting: any InventoryWriting {
        overrides?.writing ?? InventoryWriteRepository()
    }

    static func use(reading: any InventoryReading, writing: any InventoryWriting) {
        overrides = (reading, writing)
    }
}
