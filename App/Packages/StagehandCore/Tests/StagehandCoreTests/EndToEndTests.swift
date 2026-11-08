#if os(macOS)
import CoreGraphics
import Dependencies
import DependenciesTestSupport
import Foundation
@testable import StagehandCore
import StagehandModel
import Testing

/// The runner builds and drives the fixture app's screenshot tests on a real simulator, and imports its captures.
///
/// Slow, so it's opt-in: `STAGEHAND_E2E=1 swift test --package-path App/Packages/StagehandCore --filter EndToEndTests`.
@Suite(.enabled(if: ProcessInfo.processInfo.environment["STAGEHAND_E2E"] == "1", "Set STAGEHAND_E2E=1 to run"), .dependencies, .serialized)
struct EndToEndTests {
    private static var repository: URL {
        URL(filePath: #filePath).deletingLastPathComponent().appending(path: "../../../../..").standardizedFileURL
    }
    
    private final class Events: @unchecked Sendable {
        private let lock = NSLock()
        private var stored: [RunEvent] = []
        
        func append(_ event: RunEvent) {
            lock.withLock { stored.append(event) }
        }
        
        var all: [RunEvent] {
            lock.withLock { stored }
        }
    }
    
    private func run(_ passes: [RunPlan.Pass], scheme: String) async throws -> [RunEvent] {
        let events = Events()
        
        try await withDependencies {
            $0.processRunner = LiveProcessRunner()
            $0.fileManager = LiveFileManager()
        } operation: {
            let context = RunContext(
                projectURL: Self.repository.appending(path: "Fixtures/StagehandFixtureApp/StagehandFixtureApp.xcodeproj"),
                scheme: "StagehandFixtureApp",
                testTarget: "StagehandFixtureAppScreenshots",
                overridesStatusBar: true,
                runID: "e2e-\(Int(Date().timeIntervalSince1970))",
                cachesFolder: URL.cachesDirectory.appending(path: "com.mazjap.Stagehand.E2E", directoryHint: .isDirectory),
                platformSchemes: [.watchOSSimulator: "StagehandFixtureWatch", .macOS: "StagehandFixtureMac"]
            )
            
            try await CaptureRunner().run(RunPlan(passes: passes), context: context, events: { events.append($0) }) { _ in false }
        }
        
        let failed = events.all.compactMap { event -> String? in
            if case let .passFailed(_, message) = event { return message }
            return nil
        }
        
        #expect(failed.isEmpty, "\(failed)")
        return events.all
    }
    
    private func finished(_ events: [RunEvent]) -> [(pass: RunPlan.Pass, captures: [RunnerCapture], failures: [TestFailure])] {
        events.compactMap { event in
            if case let .passFinished(pass, captures, failures, _) = event { return (pass, captures, failures) }
            return nil
        }
    }
    
    private func pass(_ device: DeviceClass, _ spec: SimulatorSpec?, locale: LocaleID, language: String, region: String?) -> RunPlan.Pass {
        RunPlan.Pass(
            deviceClass: device,
            simulatorName: RunPlan.simulatorName(for: device),
            simulator: spec,
            platform: RunPlan.Platform(device),
            locale: locale,
            appLocale: AppLocale(language: language, region: region),
            onlyTesting: [],
            posture: .asBooted
        )
    }
    
    private static let phone = SimulatorSpec(deviceType: "com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro-Max", runtime: "com.apple.CoreSimulator.SimRuntime.iOS-27-0")
    private static let watch = SimulatorSpec(deviceType: "com.apple.CoreSimulator.SimDeviceType.Apple-Watch-Ultra-4-49mm", runtime: "com.apple.CoreSimulator.SimRuntime.watchOS-27-0")
    
    @Test(.timeLimit(.minutes(20)))
    func theRunnerCapturesTheFixtureApp() async throws {
        let events = try await run([pass(.phone, Self.phone, locale: "en-US", language: "en", region: "US")], scheme: "StagehandFixtureApp")
        let result = try #require(finished(events).first)
        
        #expect(result.failures.isEmpty)
        #expect(Set(result.captures.map(\.shot.name)) == ["dark-scene", "light-scene"])
        
        for capture in result.captures {
            #expect(capture.shot.deviceClass == .phone)
            #expect(capture.shot.locale == "en-US")
            #expect(capture.shot.pixelWidth == 1320 && capture.shot.pixelHeight == 2868)
            #expect(capture.testIdentifier.contains("FixtureScreenshots"))
            #expect(CGImage.decode(capture.png)?.width == 1320)
        }
    }
    
    /// Each locale's pass runs the app in that language, and its captures differ.
    @Test(.timeLimit(.minutes(20)))
    func theRunnerCapturesTwoLanguages() async throws {
        let events = try await run([
            pass(.phone, Self.phone, locale: "en-US", language: "en", region: "US"),
            pass(.phone, Self.phone, locale: "de-DE", language: "de", region: "DE"),
        ], scheme: "StagehandFixtureApp")
        let results = finished(events)
        let english = try #require(results.first { $0.pass.locale == "en-US" }?.captures.first { $0.shot.name == "light-scene" })
        let german = try #require(results.first { $0.pass.locale == "de-DE" }?.captures.first { $0.shot.name == "light-scene" })
        
        #expect(english.shot.locale == "en-US")
        #expect(german.shot.locale == "de-DE")
        #expect(english.png != german.png)
    }
    
    /// Answers whether `XCUIScreen` works in watchOS UI tests (PLAN.md's open question 4).
    @Test(.timeLimit(.minutes(25)))
    func theRunnerCapturesTheFixtureWatchApp() async throws {
        let events = try await run([pass(.watch, Self.watch, locale: "en-US", language: "en", region: "US")], scheme: "StagehandFixtureWatch")
        let result = try #require(finished(events).first)
        
        #expect(result.failures.isEmpty, "\(result.failures)")
        #expect(Set(result.captures.map(\.shot.name)) == ["dark-scene", "light-scene"])
        #expect(result.captures.allSatisfy { $0.shot.deviceClass == .watch && $0.shot.pixelWidth == 422 && $0.shot.pixelHeight == 514 })
    }
    
    /// Mac UI tests drive the real desktop and need UI automation permission, so they're opt-in on their own.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["STAGEHAND_E2E_MAC"] == "1", "Set STAGEHAND_E2E_MAC=1 too"), .timeLimit(.minutes(20)))
    func theRunnerCapturesTheFixtureMacApp() async throws {
        let events = try await run([pass(.mac, nil, locale: "en-US", language: "en", region: "US")], scheme: "StagehandFixtureMac")
        let result = try #require(finished(events).first)
        
        #expect(result.failures.isEmpty, "\(result.failures)")
        #expect(result.captures.allSatisfy { $0.shot.deviceClass == .mac })
        #expect(result.captures.contains { $0.shot.pixelWidth == 2880 && $0.shot.pixelHeight == 1800 })
    }
}
#endif
