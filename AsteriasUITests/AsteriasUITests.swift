import XCTest

final class AsteriasUITests: XCTestCase {
    override func setUp() {
        super.setUp()
        continueAfterFailure = false

        let defaults = UserDefaults(suiteName: "com.asterias.settings")!
        defaults.removePersistentDomain(forName: "com.asterias.settings")
        defaults.set("tinySquare", forKey: "selectedDimensions")
        defaults.set(2, forKey: "selectedLayerCount")
        defaults.set(false, forKey: "usesRandomSeed")
        defaults.set("1234", forKey: "seedText")
        defaults.set(true, forKey: "isTilingEnabled")
    }

    @MainActor
    func testAppLaunchesForSeededGenerationConfiguration() {
        let app = XCUIApplication()
        app.launch()

        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 15))
        XCTAssertEqual(app.state, .runningForeground)
    }
}
