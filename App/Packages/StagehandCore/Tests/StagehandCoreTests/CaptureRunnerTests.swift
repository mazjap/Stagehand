#if os(macOS)
import Dependencies
import DependenciesTestSupport
import Foundation
@testable import StagehandCore
import StagehandModel
import Testing

@Suite(.dependencies) struct CaptureRunnerTests {
    private static let phoneSpec = SimulatorSpec(deviceType: "com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro-Max", runtime: "com.apple.CoreSimulator.SimRuntime.iOS-27-0")
    private static let duoSpec = SimulatorSpec(deviceType: "com.apple.CoreSimulator.SimDeviceType.iPhone-Duo", runtime: "com.apple.CoreSimulator.SimRuntime.iOS-27-1", developerDir: "/Applications/Xcode-Beta.app/Contents/Developer")
    
    private let context = RunContext(
        projectURL: URL(filePath: "/Apps/TrekPoint/TrekPoint.xcodeproj"),
        scheme: "TrekPointScreenshots",
        testTarget: "TrekPointScreenshots",
        overridesStatusBar: true,
        runID: "run-1",
        cachesFolder: URL(filePath: "/Caches")
    )
    
    private final class Box<T>: @unchecked Sendable {
        private let lock = NSLock()
        private var value: T
        
        init(_ value: T) {
            self.value = value
        }
        
        func mutate(_ body: (inout T) -> Void) {
            lock.withLock { body(&value) }
        }
        
        var current: T {
            lock.withLock { value }
        }
    }
    
    /// A fake toolchain: builds make an .xctestrun, tests make a result bundle, and exports write the recorded manifest.
    private func fakeTools(
        fileManager: InMemoryFileManager,
        existingDevices: String = #"{"devices":{}}"#,
        testOutputs: Box<[ProcessOutput]> = Box([]),
        results: String = "test-results-passed.json"
    ) -> FakeProcessRunner {
        FakeProcessRunner { command in
            let args = command.arguments
            
            switch (args.first, args.dropFirst().first) {
            case ("xcodebuild", "build-for-testing"):
                let derived = args[args.firstIndex(of: "-derivedDataPath")! + 1]
                try fileManager.write(Data(), to: URL(filePath: derived).appending(path: "Build/Products/App_iphonesimulator27.1-arm64.xctestrun"))
                return ProcessOutput()
            case ("xcodebuild", "test-without-building"):
                var output = ProcessOutput()
                testOutputs.mutate { queued in
                    if !queued.isEmpty { output = queued.removeFirst() }
                }
                
                if output.succeeded {
                    let bundle = args[args.firstIndex(of: "-resultBundlePath")! + 1]
                    try fileManager.createDirectory(at: URL(filePath: bundle))
                }
                
                return output
            case ("simctl", "list"):
                return ProcessOutput(stdout: existingDevices)
            case ("simctl", "create"):
                return ProcessOutput(stdout: "NEW-UDID\n")
            case ("xcresulttool", "export"):
                let folder = URL(filePath: args[args.firstIndex(of: "--output-path")! + 1])
                let manifestData = TestResources.data("xcresult/attachments-manifest.json")
                try fileManager.write(manifestData, to: folder.appending(path: "manifest.json"))
                
                for capture in try AttachmentManifest.parse(manifestData).captures() {
                    let shot = Shot(captureID: capture.captureID, name: capture.name!, deviceClass: .phone, targetID: "iphone-dynamic-island-large", pixelWidth: 1320, pixelHeight: 2868, locale: "en-US", capturedAt: .sampleDate)
                    try fileManager.write(Shot.makeEncoder().encode(shot), to: folder.appending(path: capture.metadataFile!))
                    try fileManager.write(TestImages.solid(width: 1320, height: 2868).pngData()!, to: folder.appending(path: capture.imageFile!))
                }
                
                return ProcessOutput()
            case ("xcresulttool", "get"):
                return ProcessOutput(stdout: String(decoding: TestResources.data("xcresult/\(results)"), as: UTF8.self))
            default:
                return ProcessOutput()
            }
        }
    }
    
    private func phonePass(onlyTesting: [String] = []) -> RunPlan.Pass {
        RunPlan.Pass(
            deviceClass: .phone,
            simulatorName: "Stagehand iphone-dynamic-island-large",
            simulator: Self.phoneSpec,
            platform: .iOSSimulator,
            locale: "de-DE",
            appLocale: AppLocale(language: "de", region: "DE"),
            onlyTesting: onlyTesting,
            posture: .asBooted
        )
    }
    
    private func run(_ plan: RunPlan, tools: FakeProcessRunner, fileManager: InMemoryFileManager, prompt: @escaping @Sendable (RunPrompt) async -> Bool = { _ in true }) async throws -> [RunEvent] {
        let events = Box<[RunEvent]>([])
        
        try await withDependencies {
            $0.processRunner = tools
            $0.fileManager = fileManager
        } operation: {
            try await CaptureRunner().run(plan, context: context, events: { event in events.mutate { $0.append(event) } }, prompt: prompt)
        }
        
        return events.current
    }
    
    /// Regression test: a failed build showed the last 2,000 characters of `xcodebuild`'s output, which is its target
    /// dependency graph, so the error that stopped it (a package macro that needed trusting again) never showed.
    @Test func aFailedBuildLeadsWithItsErrors() async throws {
        let fileManager = InMemoryFileManager()
        let macroError = "/DerivedData/SourcePackages/checkouts/swift-dependencies/Package.swift:PACKAGE-TARGET:DependenciesMacrosPlugin: error: Macro \u{201C}DependenciesMacrosPlugin\u{201D} from package \u{201C}swift-dependencies\u{201D} was changed since a previous approval and must be enabled before it can be used"
        let graph = (1...200).map { "    \u{279C} Explicit dependency on target 'Target\($0)' in project 'MapboxMaps'" }.joined(separator: "\n")
        let tools = FakeProcessRunner { command in
            if command.arguments.dropFirst().first == "build-for-testing" {
                return ProcessOutput(exitCode: 65, stdout: "Resolve Package Graph\n\(macroError)\n\(macroError)\n\(graph)\n\n** TEST BUILD FAILED **\n")
            }
            
            return ProcessOutput()
        }
        
        await #expect {
            _ = try await run(RunPlan(passes: [phonePass()]), tools: tools, fileManager: fileManager)
        } throws: { error in
            guard case let .buildFailed(message) = error as? CaptureRunError else {
                return false
            }
            
            return message.hasPrefix(macroError + "\n\n…\n") && message.contains("TEST BUILD FAILED")
        }
    }
    
    /// FlaskMaster (through MJScreenshotTesting) and TrekPoint attach plain screenshots named after the shot, without
    /// the kit's metadata. Each becomes a capture keyed by its name and classified by its size; failure screenshots
    /// and other files are left out.
    @Test func plainScreenshotAttachmentsAreImported() async throws {
        let fileManager = InMemoryFileManager()
        let bundle = URL(filePath: "/Caches/run/phone-en-US.xcresult")
        let folder = URL(filePath: "/Caches/run/phone-en-US.attachments")
        let phone = TestImages.solid(width: 1320, height: 2868).pngData()!
        let manifest = """
        [
          {"testIdentifier": "AppStoreScreenshots/test01Level()", "attachments": [
            {"suggestedHumanReadableName": "01-level_0_3A382E9C-04C7-4D6F-AA62-840E4CFC5DC6.png", "exportedFileName": "A.png", "isAssociatedWithFailure": false}
          ]},
          {"testIdentifier": "AppStoreScreenshots/test1TerrainMadeClear()", "attachments": [
            {"suggestedHumanReadableName": "1_0_DAFD9F0F-A4F1-4172-8BBE-A8A032B9D702. Terrain Made Clear", "exportedFileName": "B.png", "isAssociatedWithFailure": false},
            {"suggestedHumanReadableName": "Screenshot_0_77DDC687-1082-4BDF-9C16-16FBCAB085C1.png", "exportedFileName": "C.png", "isAssociatedWithFailure": true},
            {"suggestedHumanReadableName": "Complete Issue Description.txt", "exportedFileName": "D.txt", "isAssociatedWithFailure": false}
          ]}
        ]
        """
        let tools = FakeProcessRunner { command in
            if command.arguments.contains("export") {
                try fileManager.write(Data(manifest.utf8), to: folder.appending(path: "manifest.json"))
                try fileManager.write(phone, to: folder.appending(path: "A.png"))
                try fileManager.write(phone, to: folder.appending(path: "B.png"))
                try fileManager.write(phone, to: folder.appending(path: "C.png"))
                try fileManager.write(Data("issue".utf8), to: folder.appending(path: "D.txt"))
            }
            
            return ProcessOutput()
        }
        
        let captures = try await withDependencies {
            $0.processRunner = tools
            $0.fileManager = fileManager
            $0.clock = FixedClock(now: .sampleDate)
        } operation: {
            try await CaptureRunner().importAttachments(from: bundle, locale: "en-US", developerDir: nil)
        }
        
        #expect(captures.map(\.shot.name) == ["01-level", "1-terrain-made-clear"])
        #expect(captures.map(\.shot.deviceClass) == [.phone, .phone])
        #expect(captures.map(\.testIdentifier) == ["AppStoreScreenshots/test01Level()", "AppStoreScreenshots/test1TerrainMadeClear()"])
        #expect(captures.allSatisfy { $0.locale == "en-US" && $0.shot.capturedAt == .sampleDate })
    }
    
    @Test func theCommandLinesAreExact() async throws {
        let fileManager = InMemoryFileManager()
        let tools = fakeTools(fileManager: fileManager)
        _ = try await run(RunPlan(passes: [phonePass(onlyTesting: ["TrekPointScreenshots/AppStoreScreenshots/testReadTheLand"])]), tools: tools, fileManager: fileManager)
        
        let build = try #require(tools.commands.first { $0.arguments.dropFirst().first == "build-for-testing" })
        let derived = context.derivedData(developerDir: nil).path(percentEncoded: false)
        #expect(build.executable == "/usr/bin/xcrun")
        #expect(build.arguments == ["xcodebuild", "build-for-testing", "-project", "/Apps/TrekPoint/TrekPoint.xcodeproj", "-scheme", "TrekPointScreenshots", "-destination", "generic/platform=iOS Simulator", "-derivedDataPath", derived])
        
        let test = try #require(tools.commands.first { $0.arguments.dropFirst().first == "test-without-building" })
        #expect(test.arguments == [
            "xcodebuild", "test-without-building",
            "-xctestrun", derived.trimmingSuffix("/") + "/Build/Products/App_iphonesimulator27.1-arm64.xctestrun",
            "-destination", "id=NEW-UDID",
            "-parallel-testing-enabled", "NO",
            "-testLanguage", "de",
            "-testRegion", "DE",
            "-resultBundlePath", "/Caches/Results/run-1/phone-de-DE-1.xcresult",
            "-only-testing:TrekPointScreenshots/AppStoreScreenshots/testReadTheLand",
        ])
        #expect(test.environment == [
            "TEST_RUNNER_STAGEHAND_LOCALE": "de-DE",
            "TEST_RUNNER_STAGEHAND_RUN_ID": "run-1",
            "TEST_RUNNER_STAGEHAND_EXPECTED_CLASS": "phone",
            "TEST_RUNNER_STAGEHAND_FOLDER_OUTPUT": "off",
            "TEST_RUNNER_STAGEHAND_APP_LANGUAGE": "de",
            "TEST_RUNNER_STAGEHAND_APP_REGION": "DE",
        ])
    }
    
    @Test func onlyStagehandSimulatorsAreBootedOrChanged() async throws {
        let fileManager = InMemoryFileManager()
        let devices = """
        {"devices":{"com.apple.CoreSimulator.SimRuntime.iOS-27-0":[
            {"udid":"USER-UDID","name":"iPhone 17 Pro Max","state":"Booted","isAvailable":true,"deviceTypeIdentifier":"com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro-Max"},
            {"udid":"OURS-UDID","name":"Stagehand iphone-dynamic-island-large","state":"Shutdown","isAvailable":true,"deviceTypeIdentifier":"com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro-Max"}
        ]}}
        """
        let tools = fakeTools(fileManager: fileManager, existingDevices: devices)
        _ = try await run(RunPlan(passes: [phonePass()]), tools: tools, fileManager: fileManager)
        
        let simctl = tools.commands.filter { $0.arguments.first == "simctl" && $0.arguments[1] != "list" }
        #expect(!simctl.isEmpty)
        #expect(simctl.allSatisfy { !$0.arguments.contains("USER-UDID") })
        #expect(simctl.contains { $0.arguments == ["simctl", "boot", "OURS-UDID"] })
        #expect(!tools.commands.contains { $0.arguments.dropFirst().first == "create" })
        #expect(simctl.contains { $0.arguments.starts(with: ["simctl", "status_bar", "OURS-UDID", "override"]) })
    }
    
    @Test func aSimulatorWithoutTheStagehandPrefixIsRefused() async throws {
        let fileManager = InMemoryFileManager()
        
        await #expect(throws: CaptureRunError.notAStagehandSimulator("iPhone 17 Pro Max")) {
            try await withDependencies {
                $0.processRunner = fakeTools(fileManager: fileManager)
                $0.fileManager = fileManager
            } operation: {
                _ = try await CaptureRunner().prepareSimulator(named: "iPhone 17 Pro Max", spec: Self.phoneSpec, overridesStatusBar: true)
            }
        }
    }
    
    @Test func capturesAreImportedFromTheResultBundle() async throws {
        let fileManager = InMemoryFileManager()
        let events = try await run(RunPlan(passes: [phonePass()]), tools: fakeTools(fileManager: fileManager), fileManager: fileManager)
        
        let finished = try #require(events.compactMap { event -> [RunnerCapture]? in
            if case let .passFinished(_, captures, _, _) = event { return captures }
            return nil
        }.first)
        
        #expect(finished.map(\.shot.name) == ["dark-scene", "light-scene"])
        #expect(finished[1].testIdentifier == "FixtureScreenshots/testLightScene()")
    }
    
    @Test func aBusySimulatorIsRestartedAndRetriedOnce() async throws {
        let fileManager = InMemoryFileManager()
        let outputs = Box([ProcessOutput(exitCode: 65, stderr: "Simulator device failed to launch: Busy")])
        let tools = fakeTools(fileManager: fileManager, testOutputs: outputs)
        _ = try await run(RunPlan(passes: [phonePass()]), tools: tools, fileManager: fileManager)
        
        let tests = tools.commands.filter { $0.arguments.dropFirst().first == "test-without-building" }
        #expect(tests.count == 2)
        #expect(tools.commands.contains { $0.arguments == ["simctl", "shutdown", "NEW-UDID"] })
        #expect(tests[1].arguments.contains("/Caches/Results/run-1/phone-de-DE-1-retry.xcresult"))
    }
    
    @Test func eachDeveloperDirectoryBuildsOnceAndUsesItsOwnXcode() async throws {
        var project = Project.fixture()
        project.devices = [.phone, .duoOuter, .duoInner]
        project.appLink = AppLink(project: Data(), projectPath: "/a.xcodeproj", scheme: "S", testTarget: "T", simulators: [.phone: Self.phoneSpec, .duoOuter: Self.duoSpec])
        let plan = RunPlan.make(project: project)
        
        #expect(plan.passes.map(\.deviceClass) == [.phone, .duoOuter, .duoInner])
        #expect(plan.builds.count == 2)
        #expect(plan.passes[2].simulator == Self.duoSpec)
        #expect(plan.passes[2].posture == .unfolded)
        
        let fileManager = InMemoryFileManager()
        let tools = fakeTools(fileManager: fileManager)
        _ = try await run(plan, tools: tools, fileManager: fileManager)
        
        let builds = tools.commands.filter { $0.arguments.dropFirst().first == "build-for-testing" }
        #expect(builds.map { $0.environment["DEVELOPER_DIR"] } == [nil, Self.duoSpec.developerDir])
        
        let duoTests = tools.commands.filter { $0.arguments.dropFirst().first == "test-without-building" && $0.environment["DEVELOPER_DIR"] != nil }
        #expect(duoTests.count == 2)
        #expect(duoTests.allSatisfy { $0.arguments.contains { $0.contains(context.derivedData(developerDir: Self.duoSpec.developerDir).path(percentEncoded: false)) } })
    }
    
    @Test func theDuoInnerDisplayAsksToUnfoldAndAsksAgainWhenStillFolded() async throws {
        var project = Project.fixture()
        project.devices = [.duoInner]
        project.appLink = AppLink(project: Data(), projectPath: "/a.xcodeproj", scheme: "S", testTarget: "T", simulators: [.duoInner: Self.duoSpec])
        
        let fileManager = InMemoryFileManager()
        let prompts = Box<[RunPrompt]>([])
        let tools = fakeTools(fileManager: fileManager, results: "test-results-expectation-failed.json")
        _ = try await run(RunPlan.make(project: project), tools: tools, fileManager: fileManager) { prompt in
            prompts.mutate { $0.append(prompt) }
            return true
        }
        
        #expect(prompts.current == [
            .unfoldDuo(simulatorName: "Stagehand iphone-duo", attempt: 1),
            .unfoldDuo(simulatorName: "Stagehand iphone-duo", attempt: 2),
            .unfoldDuo(simulatorName: "Stagehand iphone-duo", attempt: 3),
        ])
    }
    
    @Test func decliningToUnfoldStopsThatPass() async throws {
        var project = Project.fixture()
        project.devices = [.duoInner]
        project.appLink = AppLink(project: Data(), projectPath: "/a.xcodeproj", scheme: "S", testTarget: "T", simulators: [.duoInner: Self.duoSpec])
        let fileManager = InMemoryFileManager()
        let tools = fakeTools(fileManager: fileManager)
        
        await #expect(throws: CancellationError.self) {
            _ = try await run(RunPlan.make(project: project), tools: tools, fileManager: fileManager) { _ in false }
        }
        
        #expect(!tools.commands.contains { $0.arguments.dropFirst().first == "test-without-building" })
    }
}
#endif
