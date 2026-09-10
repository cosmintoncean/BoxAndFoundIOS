import Testing
@testable import BoxAndFound

/// The diff that replaces the web client's delete-and-reinsert. These are the
/// behaviours that make it worth having, so they are pinned rather than
/// trusted.
@Suite("Item sync")
struct ItemSyncTests {

    private let now = "2026-09-10T12:00:00Z"
    private func clock() -> String { now }

    private func existing(
        _ id: String,
        _ name: String,
        quantity: Int = 1,
        position: Int = 0,
        isTaken: Bool = false,
        takenBy: String? = nil
    ) -> BoxItem {
        BoxItem(
            id: id,
            name: name,
            quantity: quantity,
            position: position,
            isTaken: isTaken,
            takenAt: isTaken ? "2026-01-01T00:00:00Z" : nil,
            takenBy: takenBy
        )
    }

    private func plan(_ existing: [BoxItem], _ desired: [DraftItem]) -> ItemSyncPlan {
        ItemSync.plan(existing: existing, desired: desired, currentUserID: "user-1", now: clock)
    }

    // MARK: - The point of the exercise

    /// The whole reason this exists. The web client rewrites every row on
    /// every save, which churns item ids and breaks `item_nudges.item_id`.
    @Test("An untouched item is not written at all")
    func untouchedItemIsNotWritten() {
        let rows = [existing("i1", "Scarf"), existing("i2", "Gloves", position: 1)]
        let desired = [
            DraftItem(id: "i1", name: "Scarf"),
            DraftItem(id: "i2", name: "Gloves"),
        ]
        #expect(plan(rows, desired).isEmpty)
    }

    /// Two members editing one box must not clobber each other: editing item
    /// one leaves item two alone, so a concurrent edit to it survives.
    @Test("Editing one item leaves every other row untouched")
    func editingOneItemTouchesOnlyIt() {
        let rows = [existing("i1", "Scarf"), existing("i2", "Gloves", position: 1)]
        let desired = [
            DraftItem(id: "i1", name: "Wool scarf"),
            DraftItem(id: "i2", name: "Gloves"),
        ]

        let result = plan(rows, desired)
        #expect(result.updates.map(\.id) == ["i1"])
        #expect(result.updates[0].name == "Wool scarf")
        #expect(result.updates[0].quantity == nil)
        #expect(result.updates[0].position == nil)
        #expect(result.inserts.isEmpty)
        #expect(result.deletes.isEmpty)
    }

    // MARK: - Inserts

    @Test("A draft with no id becomes an insert, positioned by where it sits")
    func newItemsAreInserted() {
        let result = plan([], [DraftItem(name: "Scarf"), DraftItem(name: "Gloves")])
        #expect(result.inserts.map(\.name) == ["Scarf", "Gloves"])
        #expect(result.inserts.map(\.position) == [0, 1])
        #expect(result.updates.isEmpty)
    }

    @Test("Names are trimmed on the way in")
    func namesAreTrimmed() {
        #expect(plan([], [DraftItem(name: "  Scarf  ")]).inserts[0].name == "Scarf")
    }

    @Test("A quantity below one is a typo, not an instruction")
    func quantityFloorsAtOne() {
        #expect(plan([], [DraftItem(name: "Scarf", quantity: 0)]).inserts[0].quantity == 1)
        #expect(plan([], [DraftItem(name: "Scarf", quantity: -5)]).inserts[0].quantity == 1)
    }

    @Test("An item added already taken carries who and when")
    func insertingATakenItem() {
        let insert = plan([], [DraftItem(name: "Scarf", isTaken: true)]).inserts[0]
        #expect(insert.isTaken)
        #expect(insert.takenAt == now)
        #expect(insert.takenBy == "user-1")
    }

    @Test("An item added not taken carries neither")
    func insertingAnUntakenItem() {
        let insert = plan([], [DraftItem(name: "Scarf")]).inserts[0]
        #expect(!insert.isTaken)
        #expect(insert.takenAt == nil)
        #expect(insert.takenBy == nil)
    }

    /// A draft can name an id that no longer has a row — another member
    /// deleted it while this editor was open. Updating it would write nothing;
    /// inserting keeps the person's work.
    @Test("A draft pointing at a row that is gone is inserted, not lost")
    func staleIDBecomesAnInsert() {
        let result = plan([], [DraftItem(id: "deleted-elsewhere", name: "Scarf")])
        #expect(result.inserts.map(\.name) == ["Scarf"])
        #expect(result.updates.isEmpty)
    }

    // MARK: - Updates

    @Test("Only the fields that moved appear in the patch")
    func updatesCarryOnlyChanges() {
        let rows = [existing("i1", "Scarf", quantity: 1, position: 0)]
        let desired = [DraftItem(id: "i1", name: "Scarf", quantity: 3)]

        let update = plan(rows, desired).updates[0]
        #expect(update.quantity == 3)
        #expect(update.name == nil)
        #expect(update.position == nil)
        #expect(update.taken == nil)
    }

    @Test("Reordering writes the new positions and nothing else")
    func reorderingWritesPositions() {
        let rows = [existing("i1", "Scarf", position: 0), existing("i2", "Gloves", position: 1)]
        let desired = [DraftItem(id: "i2", name: "Gloves"), DraftItem(id: "i1", name: "Scarf")]

        let result = plan(rows, desired)
        #expect(result.updates.count == 2)
        #expect(result.updates.first { $0.id == "i2" }?.position == 0)
        #expect(result.updates.first { $0.id == "i1" }?.position == 1)
        #expect(result.updates.allSatisfy { $0.name == nil })
    }

    /// A returned item still holding a stale `taken_by` would misattribute the
    /// nudges that read it, so the three columns move as one.
    @Test("Taking an item stamps who and when together")
    func takingStampsBoth() {
        let rows = [existing("i1", "Scarf")]
        let desired = [DraftItem(id: "i1", name: "Scarf", isTaken: true)]

        let taken = plan(rows, desired).updates[0].taken
        #expect(taken?.isTaken == true)
        #expect(taken?.at == now)
        #expect(taken?.by == "user-1")
    }

    @Test("Returning an item clears who and when together")
    func returningClearsBoth() {
        let rows = [existing("i1", "Scarf", isTaken: true, takenBy: "someone-else")]
        let desired = [DraftItem(id: "i1", name: "Scarf", isTaken: false)]

        let taken = plan(rows, desired).updates[0].taken
        #expect(taken?.isTaken == false)
        #expect(taken?.at == nil)
        #expect(taken?.by == nil)
    }

    @Test("An unchanged taken flag is not rewritten")
    func unchangedTakenIsNotWritten() {
        let rows = [existing("i1", "Scarf", isTaken: true, takenBy: "someone-else")]
        let desired = [DraftItem(id: "i1", name: "Scarf", isTaken: true)]
        #expect(plan(rows, desired).isEmpty)
    }

    // MARK: - Deletes

    @Test("A row dropped from the list is deleted")
    func removedItemsAreDeleted() {
        let rows = [existing("i1", "Scarf"), existing("i2", "Gloves", position: 1)]
        let result = plan(rows, [DraftItem(id: "i1", name: "Scarf")])
        #expect(result.deletes == ["i2"])
    }

    @Test("Blanking a name deletes the row rather than saving an empty one")
    func blankedNamesAreDeleted() {
        let rows = [existing("i1", "Scarf")]
        let result = plan(rows, [DraftItem(id: "i1", name: "   ")])
        #expect(result.deletes == ["i1"])
        #expect(result.updates.isEmpty)
        #expect(result.inserts.isEmpty)
    }

    @Test("A blank new row is ignored, not inserted")
    func blankDraftsAreIgnored() {
        #expect(plan([], [DraftItem(name: ""), DraftItem(name: "  ")]).isEmpty)
    }

    @Test("Clearing every item deletes them all and inserts nothing")
    func clearingEverything() {
        let rows = [existing("i1", "Scarf"), existing("i2", "Gloves", position: 1)]
        let result = plan(rows, [])
        #expect(Set(result.deletes) == ["i1", "i2"])
        #expect(result.inserts.isEmpty)
        #expect(result.updates.isEmpty)
    }

    /// Positions come from the surviving list, so a gap left by a deletion
    /// does not leave the rest numbered around a hole.
    @Test("Deleting from the middle renumbers what is left")
    func deletionRenumbers() {
        let rows = [
            existing("i1", "A", position: 0),
            existing("i2", "B", position: 1),
            existing("i3", "C", position: 2),
        ]
        let desired = [DraftItem(id: "i1", name: "A"), DraftItem(id: "i3", name: "C")]

        let result = plan(rows, desired)
        #expect(result.deletes == ["i2"])
        #expect(result.updates.map(\.id) == ["i3"])
        #expect(result.updates[0].position == 1)
    }

    // MARK: - Positions

    @Test("A new item goes after the highest position, not after the count")
    func nextPositionUsesTheMaximum() {
        #expect(ItemSync.nextPosition(after: []) == 0)
        #expect(ItemSync.nextPosition(after: [existing("i1", "A", position: 7)]) == 8)
    }
}

@Suite("Stored image values")
struct BoxImagePathTests {

    @Test("A bare path is signed", arguments: ["abc/1.png", "household-id/1757000000.jpg"])
    func pathsNeedSigning(_ value: String) {
        #expect(BoxImagePath.needsSigning(value))
    }

    /// Signing a `data:` URL fails, and handing a loader a bare path fails.
    /// Both fail silently, which is why this rule is tested on its own.
    @Test("Anything carrying a scheme is used as it stands", arguments: [
        "data:image/png;base64,AAAA",
        "https://example.com/a.png",
        "http://example.com/a.png",
        "HTTPS://EXAMPLE.COM/A.PNG",
        "Data:image/png;base64,AAAA",
    ])
    func schemesArePassedThrough(_ value: String) {
        #expect(!BoxImagePath.needsSigning(value))
    }

    @Test("Nothing at all needs nothing doing")
    func emptyNeedsNothing() {
        #expect(!BoxImagePath.needsSigning(""))
        #expect(!BoxImagePath.needsSigning("   "))
    }
}

@Suite("Photo upload paths")
struct UploadPathTests {

    @Test("An extension is normalised to something the bucket will accept")
    func extensionIsCleaned() {
        #expect(InventoryWriteRepository.safeExtension("JPG") == "jpg")
        #expect(InventoryWriteRepository.safeExtension(".PNG") == "png")
        #expect(InventoryWriteRepository.safeExtension("  heic ") == "heic")
    }

    @Test("A missing or nonsense extension falls back rather than failing")
    func extensionFallsBack() {
        #expect(InventoryWriteRepository.safeExtension("") == "jpg")
        #expect(InventoryWriteRepository.safeExtension("...") == "jpg")
        #expect(InventoryWriteRepository.safeExtension("12345") == "jpg")
    }
}
