import XCTest
import XCUITestControl

final class InteractiveControlTests: XCTestCase {
    @MainActor
    func testInteractiveControl() throws {
        let app = XCUIApplication()
        app.launch()
        InteractiveControlLoop().run(app: app)
    }
}
