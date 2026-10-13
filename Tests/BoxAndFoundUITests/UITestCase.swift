import Foundation
import XCTest

/// What every UI suite needs: a launch, a couple of waits, and a camera.
///
/// The three flow suites had grown their own copies of the first two. The
/// camera is new, and is the reason this is a base class rather than three
/// more copies — nobody authoring a test on Windows can see the app, so a
/// screenshot is the only description of it that exists.
class UITestCase: XCTestCase {

    /// Generous on purpose: a cold simulator boot under CI is slower than
    /// anything a person would sit through, and a flaky suite is worse than no
    /// suite.
    let timeout: TimeInterval = 30

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    /// Launches against in-memory fixtures, signed in.
    @discardableResult
    func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-uiTestFixtures"]
        app.launch()
        return app
    }

    /// Launches with no fixtures, which lands on the sign-in screen.
    ///
    /// Nothing is dialled: the screen only reaches the network when something
    /// is submitted, and these tests never submit.
    @discardableResult
    func launchSignedOut() -> XCUIApplication {
        let app = XCUIApplication()
        app.launch()
        return app
    }

    func assertVisible(
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
    func scroll(to element: XCUIElement, in app: XCUIApplication, swipes: Int = 6) -> Bool {
        for _ in 0..<swipes {
            if element.exists && element.isHittable { return true }
            app.swipeUp()
        }
        return element.exists && element.isHittable
    }

    // MARK: - The camera

    /// Photographs the whole screen into the test results, under `name`.
    ///
    /// Two details matter more than they look. Attachments default to
    /// `.deleteOnSuccess`, which throws away precisely the screenshots worth
    /// having — the ones from a run that passed. And the name becomes the
    /// filename CI extracts, so it is prefixed by hand to make the gallery
    /// read in the order a person walks the app rather than the order XCTest
    /// happens to run the methods.
    func shoot(_ name: String) {
        let shot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: shot)
        attachment.name = "\(name).png"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// Waits for the screen to settle before photographing it.
    ///
    /// `waitForExistence` returns the moment a view exists, which under
    /// SwiftUI can be mid-transition — a half-slid navigation push, or a list
    /// one frame before its rows have their text. A short settle is the
    /// difference between a gallery and a smear.
    func shoot(_ name: String, after element: XCUIElement) {
        assertVisible(element, "Nothing to photograph for \(name)")
        Thread.sleep(forTimeInterval: 0.6)
        shoot(name)
    }
}
