import CoreGraphics
import Foundation
import StagehandCapture
import StagehandModel
import Testing

@Suite struct CapturePipelineTests {
    private let duoEnvironment = CaptureEnvironment(locale: "en-US", simulatorModel: "iPhone19,4", simulatorRuntime: "27.1")
    
    @Test func aFoldedDuoCapturesTheCoverDisplay() throws {
        let cover = FixtureImages.darkUI(width: 1398, height: 2034)
        let inner = FixtureImages.solid(width: 2007, height: 2853, gray: 0)
        
        let processed = try CapturePipeline.process(
            screenshots: [cover, inner],
            name: "read-the-land",
            scene: nil,
            environment: duoEnvironment
        )
        
        #expect(processed.shot.deviceClass == .duoOuter)
        #expect(processed.shot.quirksApplied.isEmpty)
    }
    
    @Test func anOpenDuoCapturesTheInnerDisplayRightSideUp() throws {
        let cover = FixtureImages.darkUI(width: 1398, height: 2034)
        let upsideDownInner = FixtureImages.markedTop(width: 2007, height: 2853).rotated180()!
        
        let processed = try CapturePipeline.process(
            screenshots: [cover, upsideDownInner],
            name: "read-the-land",
            scene: nil,
            environment: duoEnvironment
        )
        
        #expect(processed.shot.deviceClass == .duoInner)
        #expect(processed.shot.quirksApplied == ["duo-inner-rotated-180"])
        #expect(FixtureImages.pixel(processed.image, x: 10, y: 5)[0] == 255)
        #expect(FixtureImages.pixel(processed.image, x: 10, y: 5)[1] < 100)
        #expect(FixtureImages.pixel(processed.image, x: 10, y: 2840)[1] > 200)
    }
    
    @Test func aNewerRuntimeStillAppliesTheQuirkAndRecordsIt() throws {
        var environment = duoEnvironment
        environment.simulatorRuntime = "27.2"
        let inner = FixtureImages.markedTop(width: 2007, height: 2853)
        let unfixed = Quirk.all.map { quirk in
            var quirk = quirk
            quirk.fixedIn = nil
            return quirk
        }
        
        let processed = try CapturePipeline.process(screenshots: [inner], name: "x", scene: nil, environment: environment, quirks: unfixed)
        
        #expect(processed.shot.quirksApplied == ["duo-inner-rotated-180"])
        #expect(processed.shot.simulatorRuntime == "27.2")
    }
    
    /// Regression test: the iPhone Duo's iOS 27.2 simulator takes inner display screenshots at 2006 × 2852, right side up.
    /// They failed the size check, which the runner reported as the Duo still being folded, and every attempt failed.
    @Test func anOpenDuoOnIOS27_2PassesTheSizeCheckRightSideUp() throws {
        var environment = duoEnvironment
        environment.simulatorRuntime = "27.2"
        environment.expectedClass = .duoInner
        let cover = FixtureImages.darkUI(width: 1398, height: 2034)
        let inner = FixtureImages.markedTop(width: 2006, height: 2852)
        
        let processed = try CapturePipeline.process(screenshots: [cover, inner], name: "x", scene: nil, environment: environment)
        
        #expect(processed.expectationFailure == nil)
        #expect(processed.shot.deviceClass == .duoInner)
        #expect(processed.shot.targetID == "iphone-duo-inner")
        #expect(processed.shot.pixelWidth == 2006 && processed.shot.pixelHeight == 2852)
        #expect(processed.shot.quirksApplied.isEmpty)
        #expect(FixtureImages.pixel(processed.image, x: 10, y: 5)[1] < 100)
    }
    
    @Test func aDarkUIIsNotBlank() {
        #expect(!FixtureImages.darkUI(width: 1320, height: 2868).isBlank())
        #expect(FixtureImages.solid(width: 1320, height: 2868, gray: 0).isBlank())
        #expect(FixtureImages.solid(width: 100, height: 100, gray: 0.5).isBlank())
    }
    
    @Test func everyScreenBlankKeepsTheLargest() {
        let small = FixtureImages.solid(width: 100, height: 200, gray: 0)
        let large = FixtureImages.solid(width: 200, height: 400, gray: 0)
        #expect(DisplayChooser.choose([small, large]) == 1)
        #expect(DisplayChooser.choose([]) == nil)
    }
    
    @Test func aMismatchedClassFailsTheExpectation() throws {
        var environment = duoEnvironment
        environment.expectedClass = .duoInner
        let cover = FixtureImages.darkUI(width: 1398, height: 2034)
        let inner = FixtureImages.solid(width: 2007, height: 2853, gray: 0)
        
        let processed = try CapturePipeline.process(screenshots: [cover, inner], name: "x", scene: nil, environment: environment)
        
        let failure = try #require(processed.expectationFailure)
        #expect(failure.hasPrefix("stagehand.expectation:"))
        #expect(failure.contains("duoOuter"))
    }
    
    @Test func aMatchingClassPassesTheExpectation() throws {
        let environment = CaptureEnvironment(expectedClass: .phone)
        let phone = FixtureImages.darkUI(width: 1320, height: 2868)
        let processed = try CapturePipeline.process(screenshots: [phone], name: "x", scene: nil, environment: environment)
        #expect(processed.expectationFailure == nil)
    }
    
    @Test func anUnknownSizeHasNoClass() throws {
        let odd = FixtureImages.darkUI(width: 1000, height: 1000)
        let processed = try CapturePipeline.process(screenshots: [odd], name: "x", scene: nil, environment: .init())
        #expect(processed.shot.deviceClass == nil)
        #expect(processed.shot.targetID == nil)
    }
    
    @Test func metadataCarriesTheEnvironment() throws {
        let environment = CaptureEnvironment(
            environment: [
                "STAGEHAND_LOCALE": "de",
                "STAGEHAND_RUN_ID": "run-7",
                "STAGEHAND_EXPECTED_CLASS": "phone",
                "STAGEHAND_FOLDER_OUTPUT": "off",
                "SIMULATOR_MODEL_IDENTIFIER": "iPhone18,2",
                "SIMULATOR_RUNTIME_VERSION": "27.0",
            ],
            preferredLanguages: ["en"]
        )
        let id = UUID()
        let date = Date(timeIntervalSince1970: 1_793_102_400)
        let processed = try CapturePipeline.process(
            screenshots: [FixtureImages.darkUI(width: 1320, height: 2868)],
            name: "bring-it",
            scene: "trail",
            environment: environment,
            captureID: id,
            capturedAt: date
        )
        
        #expect(!environment.isFolderOutputEnabled)
        #expect(processed.shot == Shot(
            captureID: id,
            name: "bring-it",
            scene: "trail",
            deviceClass: .phone,
            targetID: "iphone-dynamic-island-large",
            pixelWidth: 1320,
            pixelHeight: 2868,
            locale: "de",
            runID: "run-7",
            simulatorModel: "iPhone18,2",
            simulatorRuntime: "27.0",
            quirksApplied: [],
            capturedAt: date
        ))
        #expect(processed.imageAttachmentName == "stagehand.\(id.uuidString).bring-it")
        #expect(processed.metadataAttachmentName == "stagehand.\(id.uuidString).meta")
    }
    
    @Test func theAppLanguageBecomesLaunchArguments() {
        let environment = CaptureEnvironment(environment: ["STAGEHAND_APP_LANGUAGE": "de", "STAGEHAND_APP_REGION": "DE"], preferredLanguages: [])
        #expect(environment.languageArguments == ["-AppleLanguages", "(de)", "-AppleLocale", "de_DE"])
        #expect(CaptureEnvironment(environment: [:], preferredLanguages: []).languageArguments.isEmpty)
    }
    
    @Test func theLocaleFallsBackToThePreferredLanguage() {
        let environment = CaptureEnvironment(environment: [:], preferredLanguages: ["fr-FR"])
        #expect(environment.locale == "fr-FR")
        #expect(environment.isFolderOutputEnabled)
    }
}
