import CoreGraphics
import Foundation
import StagehandScene
import Testing

@Suite struct StagehandSceneTests {
    private struct Scene: Codable, Equatable {
        var feature: String
    }
    
    @Test func theDefaultKeyIsStagehandScene() {
        #expect(StagehandScene.environmentKey == "STAGEHAND_SCENE")
    }
    
    @Test func currentReadsTheKey() {
        #expect(StagehandScene.current(environment: ["STAGEHAND_SCENE": "map"]) == "map")
        #expect(StagehandScene.current(key: "TREKPOINT_SCREENSHOT_SCENE", environment: ["TREKPOINT_SCREENSHOT_SCENE": "trail"]) == "trail")
        #expect(StagehandScene.current(environment: [:]) == nil)
        #expect(StagehandScene.current(environment: ["STAGEHAND_SCENE": ""]) == nil)
    }
    
    @Test func decodeReadsJSON() {
        let scene = StagehandScene.decode(Scene.self, environment: ["STAGEHAND_SCENE": #"{"feature":"map"}"#])
        #expect(scene == Scene(feature: "map"))
        #expect(StagehandScene.decode(Scene.self, environment: ["STAGEHAND_SCENE": "not json"]) == nil)
    }
    
    @Test func isCapturingLooksForTheArgument() {
        #expect(StagehandScene.isCapturing(arguments: ["App", "-stagehand-capturing"]))
        #expect(!StagehandScene.isCapturing(arguments: ["App"]))
    }
    
    #if os(macOS)
    @Test func requestedWindowSizeParsesWidthByHeight() {
        #expect(StagehandScene.requestedWindowSize(arguments: ["App", "-stagehand-window-size", "1440x900"]) == CGSize(width: 1440, height: 900))
        #expect(StagehandScene.requestedWindowSize(arguments: ["App", "-stagehand-window-size"]) == nil)
        #expect(StagehandScene.requestedWindowSize(arguments: ["App", "-stagehand-window-size", "wide"]) == nil)
    }
    #endif
}
