import XCTest

/// Walks the app and photographs every screen.
///
/// This is the only description of what the app looks like that anyone working
/// on it can see. The project is authored on Windows: there is no Mac, no
/// device, and no simulator outside CI, so a view can compile, pass its
/// presenter tests, pass its flow tests, and still be laid out wrongly —
/// clipped text, a wrapped icon grid, a map letterboxed to a sliver, a colour
/// that vanishes against its background.
///
/// Each test is one screen, so one unreachable screen costs one photograph
/// rather than the rest of the tour. The numbers in the names are what order
/// the gallery reads in once CI extracts the attachments as files; without
/// them the files arrive in whatever order the runner finished.
///
/// The assertions are deliberately thin — the flow suites already check
/// behaviour. Here they are only there to make sure the shutter fires on the
/// screen it claims to, rather than on a spinner.
final class ScreenshotTourTests: UITestCase {

    func testTour01SignIn() {
        let app = launchSignedOut()
        shoot("01-sign-in", after: app.textFields["you@example.com"])
    }

    func testTour02Inventory() {
        let app = launch()
        shoot("02-inventory", after: app.staticTexts["Winter Clothes"])
    }

    func testTour03Search() {
        let app = launch()
        assertVisible(app.staticTexts["Winter Clothes"], "The box list never appeared")

        let field = app.searchFields.firstMatch
        assertVisible(field, "No search field")
        field.tap()
        // The newline submits, which puts the keyboard away — otherwise it
        // covers the results the photograph is of.
        field.typeText("hammer\n")

        shoot("03-inventory-search", after: app.staticTexts["Matches: Hammer"])
    }

    func testTour04BoxDetail() {
        let app = launch()
        assertVisible(app.staticTexts["Winter Clothes"], "The box list never appeared")
        app.staticTexts["Winter Clothes"].tap()

        shoot("04-box-detail", after: app.staticTexts["Scarf"])
    }

    /// Two shots, because the editor is taller than a phone: the identity half
    /// at the top, and the photo and item list below the fold.
    func testTour05BoxEditor() {
        let app = launch()
        assertVisible(app.staticTexts["Winter Clothes"], "The box list never appeared")
        app.buttons["New box"].tap()

        shoot("05-box-editor", after: app.textFields["Name"])

        let newItem = app.textFields["Add an item"]
        XCTAssertTrue(scroll(to: newItem, in: app), "The item section never came into view")
        shoot("06-box-editor-items")
    }

    func testTour07RoomMap() {
        let app = launch()
        assertVisible(app.staticTexts["Winter Clothes"], "The box list never appeared")
        app.buttons["Map of Attic"].tap()

        shoot("07-room-map", after: app.staticTexts["4.0 m × 3.0 m"])
    }

    func testTour08RoomMapUnmapped() {
        let app = launch()
        assertVisible(app.staticTexts["Winter Clothes"], "The box list never appeared")
        app.buttons["Map of Garage"].tap()

        let empty = app.staticTexts.containing(
            NSPredicate(format: "label CONTAINS[c] 'has not been mapped'")
        ).firstMatch
        shoot("08-room-map-unmapped", after: empty)
    }

    func testTour09Notifications() {
        let app = launch()
        assertVisible(app.staticTexts["Winter Clothes"], "The box list never appeared")
        app.buttons["More"].tap()
        app.buttons["Notifications"].tap()

        shoot("09-notifications", after: app.staticTexts["Cosmin wants the Scarf back"])

        app.buttons["Notification settings"].tap()
        shoot("10-notification-settings", after: app.staticTexts["Someone asks for an item back"])
    }

    func testTour11Storage() {
        let app = launch()
        assertVisible(app.staticTexts["Winter Clothes"], "The box list never appeared")
        app.buttons["Storage in Attic"].tap()

        shoot("11-storage-room", after: app.staticTexts["Wardrobe"])

        app.staticTexts["Wardrobe"].tap()
        shoot("12-storage-container", after: app.staticTexts["Winter coat"])
    }

    func testTour13Households() {
        let app = launch()
        assertVisible(app.staticTexts["Winter Clothes"], "The box list never appeared")
        app.buttons["More"].tap()
        app.buttons["Households"].tap()

        // The navigation bar rather than the section header: a `Form` uppercases
        // its headers for display, and XCUITest reads what is displayed.
        shoot("13-households", after: app.navigationBars["Households"])
    }
}
