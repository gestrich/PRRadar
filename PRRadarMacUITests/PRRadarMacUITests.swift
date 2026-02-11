import XCTest
import XCUITestControl

final class InteractiveControlTests: XCTestCase {

    private static let containerTmp = NSHomeDirectory() + "/tmp"

    @MainActor
    func testInteractiveControl() throws {
        let app = XCUIApplication()
        app.launch()
        let config = InteractiveControlLoop.Configuration(
            commandPath: Self.containerTmp + "/xcuitest-command.json",
            hierarchyPath: Self.containerTmp + "/xcuitest-hierarchy.txt",
            screenshotPath: Self.containerTmp + "/xcuitest-screenshot.png"
        )
        InteractiveControlLoop(configuration: config).run(app: app)
    }
}
