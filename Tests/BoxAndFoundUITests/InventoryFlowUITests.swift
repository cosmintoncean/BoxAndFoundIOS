import XCTest

/// Drives the real app in a simulator against in-memory fixtures.
///
/// XCTest rather than Swift Testing: `XCUIApplication` is still an XCTest
/// citizen, and the runner lifecycle is built around `XCTestCase`.
///
/// These exist to catch what a presenter test structurally cannot — a view
/// tree that will not render, a navigation destination that never fires, a
/// button disabled when it should not be. They say nothing about how anything
/// *looks*; that is what `ScreenshotTourTests` is for.
final class InventoryFlowUITests: UITestCase {

    func testSignedInLaunchLandsOnTheInventory() {
        let app = launch()

        assertVisible(app.staticTexts["Winter Clothes"], "The box list never appeared")
        XCTAssertTrue(app.staticTexts["Tools"].exists)
        XCTAssertTrue(app.staticTexts["Spare Box"].exists)

        // Room headings come from the grouping, so their presence proves the
        // sections were built rather than a flat list rendered.
        XCTAssertTrue(app.staticTexts["Attic"].exists)
        XCTAssertTrue(app.staticTexts["Garage"].exists)
        XCTAssertTrue(app.staticTexts["No room"].exists)
    }

    func testCountsAndLocationsAreOnTheRows() {
        let app = launch()
        assertVisible(app.staticTexts["Winter Clothes"], "The box list never appeared")

        XCTAssertTrue(app.staticTexts["2 items"].exists)
        XCTAssertTrue(app.staticTexts["Top shelf"].exists)
        XCTAssertTrue(app.staticTexts["Empty"].exists, "The empty box should say so")
    }

    func testOpeningABoxShowsItsItems() {
        let app = launch()
        assertVisible(app.staticTexts["Winter Clothes"], "The box list never appeared")

        app.staticTexts["Winter Clothes"].tap()

        assertVisible(app.staticTexts["Scarf"], "The detail screen never pushed")
        XCTAssertTrue(app.staticTexts["Gloves"].exists)
        XCTAssertTrue(app.buttons["Edit"].exists, "Edit should be offered once the box has loaded")
    }

    /// The round trip a presenter test cannot do: a write, and the list saying
    /// something different afterwards.
    func testTakingAnItemShowsUpBackOnTheList() {
        let app = launch()
        assertVisible(app.staticTexts["Winter Clothes"], "The box list never appeared")
        app.staticTexts["Winter Clothes"].tap()

        assertVisible(app.staticTexts["Scarf"], "The detail screen never pushed")
        app.staticTexts["Scarf"].tap()

        app.navigationBars.buttons.element(boundBy: 0).tap()

        assertVisible(app.staticTexts["1 taken"], "Taking an item did not reach the list")
    }

    func testSearchNarrowsTheList() {
        let app = launch()
        assertVisible(app.staticTexts["Winter Clothes"], "The box list never appeared")

        let field = app.searchFields.firstMatch
        assertVisible(field, "No search field")
        field.tap()
        field.typeText("hammer")

        // Found by an item rather than by its own name, so the row has to say
        // why it survived.
        assertVisible(app.staticTexts["Matches: Hammer"], "The match note never appeared")
        XCTAssertFalse(app.staticTexts["Winter Clothes"].exists, "A non-match stayed on screen")
    }

    func testCreatingABoxAddsItToTheList() {
        let app = launch()
        assertVisible(app.staticTexts["Winter Clothes"], "The box list never appeared")

        app.buttons["New box"].tap()

        let name = app.textFields["Name"]
        assertVisible(name, "The editor never pushed")
        name.tap()
        name.typeText("Camping Gear")

        let newItem = app.textFields["Add an item"]
        XCTAssertTrue(
            scroll(to: newItem, in: app),
            "The add-an-item field never came into view"
        )
        newItem.tap()
        newItem.typeText("Tent")
        app.buttons["Add"].tap()

        // The save button lives in the toolbar, so it stays put however far
        // the form has been scrolled.
        app.buttons["Create box"].tap()

        assertVisible(app.staticTexts["Camping Gear"], "The new box never reached the list")
        XCTAssertTrue(app.staticTexts["1 item"].exists, "Its item did not save with it")
    }

    /// A box with no name cannot be found in a list sorted by name, so the
    /// editor refuses to save one. Worth checking on the real control, since a
    /// disabled button is a common thing to get wrong in a form.
    func testSavingIsRefusedWithoutAName() {
        let app = launch()
        assertVisible(app.staticTexts["Winter Clothes"], "The box list never appeared")

        app.buttons["New box"].tap()
        assertVisible(app.textFields["Name"], "The editor never pushed")

        XCTAssertFalse(app.buttons["Create box"].isEnabled)
    }
}

/// The notification feed, driven the way a person would reach it.
final class NotificationsFlowUITests: UITestCase {

    private func openNotifications(_ app: XCUIApplication) {
        assertVisible(app.staticTexts["Winter Clothes"], "The box list never appeared")
        app.buttons["More"].tap()
        app.buttons["Notifications"].tap()
    }

    func testFeedListsWhatIsThere() {
        let app = launch()
        openNotifications(app)

        assertVisible(app.staticTexts["Cosmin wants the Scarf back"], "The feed never appeared")
        XCTAssertTrue(app.staticTexts["Sam joined Home"].exists)
    }

    /// One unread row in the fixtures, so the button is live on arrival and
    /// dead afterwards — which is the whole behaviour.
    func testMarkAllReadTurnsItselfOff() {
        let app = launch()
        openNotifications(app)

        let markAll = app.buttons["Mark all read"]
        assertVisible(markAll, "No mark-all button")
        XCTAssertTrue(markAll.isEnabled)

        markAll.tap()

        // Polled rather than waited on with an NSPredicate expectation: that
        // API captures the test case itself, which Swift 6 rejects as a
        // non-Sendable value crossing an isolation boundary.
        let deadline = Date().addingTimeInterval(timeout)
        while markAll.isEnabled && Date() < deadline {
            usleep(200_000)
        }
        XCTAssertFalse(markAll.isEnabled, "Mark all read stayed live with nothing left unread")
    }

    func testSettingsListsEveryType() {
        let app = launch()
        openNotifications(app)

        app.buttons["Notification settings"].tap()

        assertVisible(
            app.staticTexts["Someone asks for an item back"],
            "The settings screen never pushed"
        )
        XCTAssertTrue(app.staticTexts["Someone joins a household"].exists)
        XCTAssertTrue(app.staticTexts["Premium is about to expire"].exists)
    }
}

/// Storage as a tree, walked the way a person walks it.
final class StorageFlowUITests: UITestCase {

    func testOpeningARoomShowsWhatIsStoredInIt() {
        let app = launch()
        assertVisible(app.staticTexts["Winter Clothes"], "The box list never appeared")

        app.buttons["Storage in Attic"].tap()

        assertVisible(app.staticTexts["Wardrobe"], "The storage screen never pushed")
        // The hidden holder for a room's own items is never offered as
        // something to open — on screen, those things are simply in the room.
        XCTAssertTrue(app.staticTexts["Stepladder"].exists, "A room's loose items never appeared")
        XCTAssertEqual(
            app.cells.staticTexts.matching(identifier: "Attic").count, 0,
            "The hidden room-items holder was listed as a place"
        )
    }

    /// The round trip the tree exists for: a box four levels in is still
    /// reachable, and still opens.
    func testOpeningAContainerShowsWhatIsInside() {
        let app = launch()
        assertVisible(app.staticTexts["Winter Clothes"], "The box list never appeared")

        app.buttons["Storage in Attic"].tap()
        assertVisible(app.staticTexts["Wardrobe"], "The storage screen never pushed")
        app.staticTexts["Wardrobe"].tap()

        // Its own item is loose in it; the box inside it is a thing to open.
        assertVisible(app.staticTexts["Winter coat"], "The container never pushed")
        XCTAssertTrue(app.staticTexts["Winter Clothes"].exists, "The nested box was not listed")

        app.staticTexts["Winter Clothes"].tap()
        assertVisible(app.staticTexts["Scarf"], "The box would not open from inside a container")
    }
}

/// The room map, reached the way a person reaches it.
final class RoomMapFlowUITests: UITestCase {

    func testOpeningAMappedRoomDrawsIt() {
        let app = launch()
        assertVisible(app.staticTexts["Winter Clothes"], "The box list never appeared")

        app.buttons["Map of Attic"].tap()

        // The size note is the proof the layout parsed and projected: it is
        // measured off the saved walls, not read from the box list.
        assertVisible(app.staticTexts["4.0 m × 3.0 m"], "The map never drew")
    }

    /// Most rooms are never drawn, so the empty state is the common case and
    /// has to say where maps come from.
    func testAnUnmappedRoomSaysSo() {
        let app = launch()
        assertVisible(app.staticTexts["Winter Clothes"], "The box list never appeared")

        app.buttons["Map of Garage"].tap()

        let empty = app.staticTexts.containing(
            NSPredicate(format: "label CONTAINS[c] 'has not been mapped'")
        ).firstMatch
        assertVisible(empty, "No empty state for an unmapped room")
    }
}
