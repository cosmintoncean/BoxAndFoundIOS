import XCTest

/// Drives the real app in a simulator against in-memory fixtures.
///
/// XCTest rather than Swift Testing: `XCUIApplication` is still an XCTest
/// citizen, and the runner lifecycle is built around `XCTestCase`.
///
/// These exist to catch what a presenter test structurally cannot — a view
/// tree that will not render, a navigation destination that never fires, a
/// button disabled when it should not be. They say nothing about how anything
/// *looks*; that still waits for a real screen.
final class InventoryFlowUITests: XCTestCase {

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-uiTestFixtures"]
        app.launch()
        return app
    }

    /// Generous on purpose: a cold simulator boot under CI is slower than
    /// anything a person would sit through, and a flaky suite is worse than no
    /// suite.
    private let timeout: TimeInterval = 30

    private func assertVisible(
        _ element: XCUIElement,
        _ message: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertTrue(element.waitForExistence(timeout: timeout), message, file: file, line: line)
    }

    /// Brings an element below the fold into view.
    ///
    /// XCUITest does not scroll to find things: an element off-screen in a
    /// `Form` is simply absent from the query, which reads exactly like a view
    /// that was never built. The editor is taller than a phone — name,
    /// location, room, a twelve-icon grid and a photo section all sit above
    /// the item list — so anything below that has to be scrolled to first.
    @discardableResult
    private func scroll(to element: XCUIElement, in app: XCUIApplication, swipes: Int = 6) -> Bool {
        for _ in 0..<swipes {
            if element.exists && element.isHittable { return true }
            app.swipeUp()
        }
        return element.exists && element.isHittable
    }

    // MARK: -

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
final class NotificationsFlowUITests: XCTestCase {

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-uiTestFixtures"]
        app.launch()
        return app
    }

    private func openNotifications(_ app: XCUIApplication) {
        XCTAssertTrue(
            app.staticTexts["Winter Clothes"].waitForExistence(timeout: 30),
            "The box list never appeared"
        )
        app.buttons["More"].tap()
        app.buttons["Notifications"].tap()
    }

    func testFeedListsWhatIsThere() {
        let app = launch()
        openNotifications(app)

        XCTAssertTrue(
            app.staticTexts["Cosmin wants the Scarf back"].waitForExistence(timeout: 30),
            "The feed never appeared"
        )
        XCTAssertTrue(app.staticTexts["Sam joined Home"].exists)
    }

    /// One unread row in the fixtures, so the button is live on arrival and
    /// dead afterwards — which is the whole behaviour.
    func testMarkAllReadTurnsItselfOff() {
        let app = launch()
        openNotifications(app)

        let markAll = app.buttons["Mark all read"]
        XCTAssertTrue(markAll.waitForExistence(timeout: 30), "No mark-all button")
        XCTAssertTrue(markAll.isEnabled)

        markAll.tap()

        let wentQuiet = NSPredicate(format: "isEnabled == false")
        expectation(for: wentQuiet, evaluatedWith: markAll)
        waitForExpectations(timeout: 30)
    }

    func testSettingsListsEveryType() {
        let app = launch()
        openNotifications(app)

        app.buttons["Notification settings"].tap()

        XCTAssertTrue(
            app.staticTexts["Someone asks for an item back"].waitForExistence(timeout: 30),
            "The settings screen never pushed"
        )
        XCTAssertTrue(app.staticTexts["Someone joins a household"].exists)
        XCTAssertTrue(app.staticTexts["Premium is about to expire"].exists)
    }
}
