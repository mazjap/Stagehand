import StagehandCapture
import XCTest

/// Captures the fixture app's two scenes with the capture kit, as an app's screenshot tests would.
final class FixtureScreenshots: XCTestCase {
    override class func setUp() {
        super.setUp()
        
        Stagehand.configure { config in
            config.launchArguments = ["-ui-testing"]
            config.settleAfterReadiness = 0.5
        }
    }
    
    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }
    
    @MainActor
    func testDarkScene() throws {
        try capture(
            scene: "dark",
            named: "dark-scene",
            until: .value(of: { $0.staticTexts["fixture-ready"] }, contains: "staged: true")
        )
    }
    
    @MainActor
    func testLightScene() throws {
        try capture(scene: "light", named: "light-scene", waitingFor: { $0.staticTexts["fixture-ready"] })
    }
}
