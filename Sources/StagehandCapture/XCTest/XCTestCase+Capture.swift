#if canImport(XCTest)
import CoreGraphics
import Foundation
import StagehandModel
import StagehandScene
import XCTest

extension XCTestCase {
    /// Stages a scene, waits for it, and captures the displayed screen.
    ///
    /// The capture is attached to the test as `stagehand.<capture ID>.<name>` (the corrected PNG) with its
    /// metadata as `stagehand.<capture ID>.meta`, and is also written to the configured folder unless the
    /// runner turns that off.
    ///
    /// - Parameters:
    ///   - scene: The scene, sent to the app in the configured environment variable.
    ///   - name: The capture key.
    ///   - element: Shorthand for `until: .element(element)`.
    ///   - readiness: What to wait for before settling.
    ///   - timeout: How long to wait for readiness before failing the test.
    ///   - settle: How long to wait before capturing: 3 seconds, or 1 second after readiness, by default.
    @MainActor
    public func capture(
        scene: String,
        named name: String,
        waitingFor element: (@MainActor (XCUIApplication) -> XCUIElement)? = nil,
        until readiness: Readiness? = nil,
        timeout: TimeInterval? = nil,
        settle: TimeInterval? = nil,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let configuration = Stagehand.configuration
        let environment = CaptureEnvironment.current
        let readiness = readiness ?? element.map { .element($0) }
        let app = XCUIApplication()
        
        app.launchArguments = configuration.launchArguments + [StagehandScene.capturingArgument] + environment.languageArguments
        
        #if os(macOS)
        let size = configuration.macWindowSize
        app.launchArguments += [StagehandScene.windowSizeArgument, "\(Int(size.width))x\(Int(size.height))"]
        #endif
        
        app.launchEnvironment = configuration.launchEnvironment
        app.launchEnvironment[configuration.sceneEnvironmentKey] = scene
        app.launch()
        
        defer {
            app.terminate()
        }
        
        if let readiness {
            if let failure = readiness.wait(in: app, timeout: timeout ?? configuration.timeout) {
                XCTFail("stagehand: \(name) wasn't ready: \(failure)", file: file, line: line)
                throw CaptureError.notReady(failure)
            }
        }
        
        Self.pause(settle ?? (readiness == nil ? configuration.settle : configuration.settleAfterReadiness))
        
        let screenshots = try Self.screenshots(of: app)
        let processed = try CapturePipeline.process(
            screenshots: screenshots,
            name: name,
            scene: scene,
            environment: environment
        )
        
        attach(processed)
        
        if let failure = processed.expectationFailure {
            XCTFail(failure, file: file, line: line)
            throw CaptureError.expectation(failure)
        }
        
        if environment.isFolderOutputEnabled, let folder = configuration.folder {
            do {
                _ = try folder.write(processed.png, for: ShotPath(shot: processed.shot))
            } catch {
                XCTContext.runActivity(named: "stagehand: couldn't write \(name) to \(folder.root.path): \(error)") { _ in }
            }
        }
    }
    
    /// Stages an `Encodable` scene, sent to the app as JSON, like the `String` overload.
    @MainActor
    public func capture<Scene: Encodable>(
        scene: Scene,
        named name: String,
        waitingFor element: (@MainActor (XCUIApplication) -> XCUIElement)? = nil,
        until readiness: Readiness? = nil,
        timeout: TimeInterval? = nil,
        settle: TimeInterval? = nil,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let json = String(decoding: try encoder.encode(scene), as: UTF8.self)
        
        try capture(
            scene: json,
            named: name,
            waitingFor: element,
            until: readiness,
            timeout: timeout,
            settle: settle,
            file: file,
            line: line
        )
    }
    
    // MARK: - Helpers
    
    @MainActor
    private func attach(_ processed: ProcessedCapture) {
        let image = XCTAttachment(data: processed.png, uniformTypeIdentifier: "public.png")
        image.name = processed.imageAttachmentName
        image.lifetime = .keepAlways
        add(image)
        
        if let metadata = try? Shot.makeEncoder().encode(processed.shot) {
            let attachment = XCTAttachment(data: metadata, uniformTypeIdentifier: "public.json")
            attachment.name = processed.metadataAttachmentName
            attachment.lifetime = .keepAlways
            add(attachment)
        }
    }
    
    /// Every screen's screenshot (on iOS and watchOS), or the app's window (on macOS).
    @MainActor
    private static func screenshots(of app: XCUIApplication) throws -> [CGImage] {
        // NOTE: - Screenshots are decoded from `pngRepresentation` into `CGImage`s, not `UIImage`s, so the same
        // code compiles for iOS, watchOS and macOS test targets.
        #if os(macOS)
        let shots = [app.windows.firstMatch.screenshot()]
        #else
        let screens = XCUIScreen.screens
        let shots = screens.isEmpty ? [app.screenshot()] : screens.map { $0.screenshot() }
        #endif
        
        let images = shots.compactMap { CGImage.decode($0.pngRepresentation) }
        
        guard images.count == shots.count else {
            throw CaptureError.undecodableScreenshot
        }
        
        return images
    }
    
    @MainActor
    private static func pause(_ seconds: TimeInterval) {
        guard seconds > 0 else {
            return
        }
        
        _ = XCTWaiter.wait(for: [XCTestExpectation(description: "stagehand.settle")], timeout: seconds)
    }
}
#endif
