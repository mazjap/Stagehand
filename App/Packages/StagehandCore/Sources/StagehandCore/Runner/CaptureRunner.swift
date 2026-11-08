#if os(macOS)
import CoreGraphics
import CryptoKit
import Dependencies
import Foundation
import OSLog
import StagehandModel

public enum CaptureRunError: Error, Equatable, LocalizedError {
    case noAppLink
    case unresolvableProject(String)
    case noSimulator(DeviceClass)
    case buildFailed(String)
    case noTestRun(String)
    case simulatorFailed(String, reason: String)
    case notAStagehandSimulator(String)
    case importFailed(String)
    case cancelled
    
    public var errorDescription: String? {
        switch self {
        case .noAppLink: "The project isn't linked to an app's Xcode project yet."
        case let .unresolvableProject(path): "The linked Xcode project at \(path) couldn't be found."
        case let .noSimulator(device): "The app link has no simulator for \(device.displayName)."
        case let .buildFailed(output): "The screenshot tests didn't build.\n\(output)"
        case let .noTestRun(folder): "Building didn't produce an .xctestrun in \(folder)."
        case let .simulatorFailed(name, reason): "\(name) couldn't be prepared: \(reason)"
        case let .notAStagehandSimulator(name): "\(name) isn't one of Stagehand's simulators, so it's left alone."
        case let .importFailed(reason): "The captures couldn't be imported: \(reason)"
        case .cancelled: "The run was cancelled."
        }
    }
    
    /// What a failed build said: its `error:` lines first (once each), since `xcodebuild` prints them well before the
    /// dependency graph and "BUILD FAILED" it ends with, then the end of the log.
    static func buildFailureSummary(_ output: String, tailLength: Int = 1000) -> String {
        var seen = Set<String>()
        let errors = output.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { line in
            line.contains("error:") && seen.insert(line).inserted
        }
        
        let tail = String(output.suffix(tailLength))
        return errors.isEmpty ? tail : errors.prefix(10).joined(separator: "\n") + "\n\n…\n" + tail
    }
}

/// Where a run reads and writes.
public struct RunContext: Hashable, Sendable {
    public var projectURL: URL
    public var scheme: String
    public var testTarget: String
    public var overridesStatusBar: Bool
    public var runID: String
    
    /// Schemes for platforms whose screenshot tests have their own, by platform.
    public var platformSchemes: [RunPlan.Platform: String]
    
    /// Stagehand's caches, which hold derived data and result bundles.
    public var cachesFolder: URL
    
    public init(
        projectURL: URL,
        scheme: String,
        testTarget: String,
        overridesStatusBar: Bool,
        runID: String,
        cachesFolder: URL,
        platformSchemes: [RunPlan.Platform: String] = [:]
    ) {
        self.projectURL = projectURL
        self.scheme = scheme
        self.platformSchemes = platformSchemes
        self.testTarget = testTarget
        self.overridesStatusBar = overridesStatusBar
        self.runID = runID
        self.cachesFolder = cachesFolder
    }
    
    /// A link's run context, resolving its project bookmark.
    public init(link: AppLink, runID: String, cachesFolder: URL = RunContext.defaultCachesFolder) {
        var stale = false
        let url = (try? URL(resolvingBookmarkData: link.project, options: [.withoutUI], bookmarkDataIsStale: &stale)) ?? URL(filePath: link.projectPath)
        var schemes: [RunPlan.Platform: String] = [:]
        
        for (platform, scheme) in link.platformSchemes ?? [:] {
            if let platform = RunPlan.Platform(rawValue: platform), !scheme.isEmpty {
                schemes[platform] = scheme
            }
        }
        
        self.init(projectURL: url, scheme: link.scheme, testTarget: link.testTarget, overridesStatusBar: link.overridesStatusBar, runID: runID, cachesFolder: cachesFolder, platformSchemes: schemes)
    }
    
    /// The scheme that builds a platform's screenshot tests.
    public func scheme(for platform: RunPlan.Platform) -> String {
        platformSchemes[platform] ?? scheme
    }
    
    public static var defaultCachesFolder: URL {
        URL.cachesDirectory.appending(path: "com.mazjap.Stagehand", directoryHint: .isDirectory)
    }
    
    /// One derived data folder per project and developer directory, so builds are reused between runs.
    func derivedData(developerDir: String?) -> URL {
        let key = projectURL.path(percentEncoded: false) + "|" + (developerDir ?? "default")
        let digest = SHA256.hash(data: Data(key.utf8)).prefix(6).map { String(format: "%02x", $0) }.joined()
        return cachesFolder.appending(path: "DerivedData/\(projectURL.deletingPathExtension().lastPathComponent)-\(digest)", directoryHint: .isDirectory)
    }
    
    func resultsFolder() -> URL {
        cachesFolder.appending(path: "Results/\(runID)", directoryHint: .isDirectory)
    }
}

/// A capture the runner imported from a result bundle.
public struct RunnerCapture: Hashable, Sendable {
    public var shot: Shot
    public var png: Data
    public var testIdentifier: String
    public var locale: LocaleID
}

/// What the runner reports as it goes.
public enum RunEvent: Hashable, Sendable {
    case log(String)
    case building(RunPlan.BuildKey)
    case preparing(String)
    case passStarted(RunPlan.Pass)
    case passFinished(RunPlan.Pass, captures: [RunnerCapture], failures: [TestFailure], resultBundle: URL)
    case passFailed(RunPlan.Pass, message: String)
}

/// A question the run has to ask, and waits on.
public enum RunPrompt: Hashable, Sendable {
    /// The iPhone Duo simulator boots folded, and there's no command for unfolding it.
    case unfoldDuo(simulatorName: String, attempt: Int)
}

/// Drives an app's screenshot UI tests through `xcodebuild` and imports what the kit attached.
///
/// > Warning: The runner only ever boots, changes or erases simulators named "Stagehand …", which it creates.
/// > Never touch the user's own simulators.
public final class CaptureRunner: Sendable {
    public static let simulatorPrefix = "Stagehand "
    
    private let processRunner: any ProcessRunnerProvider
    private let fileManager: any FileManagerProvider
    private let clock: any ClockProvider
    
    /// Takes its process runner and file manager from the dependencies where it's created.
    public init() {
        @Dependency(\.processRunner) var processRunner
        @Dependency(\.fileManager) var fileManager
        @Dependency(\.clock) var clock
        self.processRunner = processRunner
        self.fileManager = fileManager
        self.clock = clock
    }
    
    // MARK: - Linking
    
    /// The schemes and targets of a project or workspace.
    public func list(projectURL: URL) async throws -> XcodebuildList {
        let flag = projectURL.pathExtension == "xcworkspace" ? "-workspace" : "-project"
        let output = try await processRunner.run(.xcrun(["xcodebuild", "-list", "-json", flag, projectURL.path(percentEncoded: false)]))
        
        guard output.succeeded else {
            throw CaptureRunError.unresolvableProject(output.combined)
        }
        
        return try XcodebuildList.parse(output.stdout)
    }
    
    /// Device types and runtimes, for choosing each class's simulator.
    public func simulatorOptions(developerDir: String? = nil) async throws -> SimctlList {
        let output = try await processRunner.run(.xcrun(["simctl", "list", "-j", "devicetypes", "runtimes"], developerDir: developerDir))
        return try SimctlList.parse(output.stdout)
    }
    
    // MARK: - Running
    
    /// Runs every pass in order, one at a time (two simulators booting at once can crash CoreSimulator).
    public func run(
        _ plan: RunPlan,
        context: RunContext,
        events: @escaping @Sendable (RunEvent) -> Void,
        prompt: @escaping @Sendable (RunPrompt) async -> Bool
    ) async throws {
        var testRuns: [RunPlan.BuildKey: URL] = [:]
        
        for build in plan.builds {
            try Task.checkCancellation()
            events(.building(build))
            testRuns[build] = try await self.build(build, context: context, events: events)
        }
        
        for pass in plan.passes {
            try Task.checkCancellation()
            
            guard let testRun = testRuns[RunPlan.BuildKey(developerDir: pass.developerDir, platform: pass.platform)] else {
                continue
            }
            
            do {
                try await run(pass, testRun: testRun, context: context, events: events, prompt: prompt)
            } catch is CancellationError {
                throw CancellationError()
            } catch let error as CaptureRunError where error == .cancelled {
                throw CancellationError()
            } catch {
                events(.passFailed(pass, message: (error as? LocalizedError)?.errorDescription ?? String(describing: error)))
            }
        }
    }
    
    /// `build-for-testing` into Stagehand's derived data, returning the `.xctestrun` it made.
    func build(_ build: RunPlan.BuildKey, context: RunContext, events: @escaping @Sendable (RunEvent) -> Void) async throws -> URL {
        let derivedData = context.derivedData(developerDir: build.developerDir)
        let flag = context.projectURL.pathExtension == "xcworkspace" ? "-workspace" : "-project"
        let destination = build.platform == .macOS ? "platform=macOS" : "generic/platform=\(build.platform.rawValue)"
        
        let output = try await processRunner.run(
            .xcrun([
                "xcodebuild", "build-for-testing",
                flag, context.projectURL.path(percentEncoded: false),
                "-scheme", context.scheme(for: build.platform),
                "-destination", destination,
                "-derivedDataPath", derivedData.path(percentEncoded: false),
            ], developerDir: build.developerDir),
            onOutput: { events(.log($0)) }
        )
        
        guard output.succeeded else {
            throw CaptureRunError.buildFailed(CaptureRunError.buildFailureSummary(output.combined))
        }
        
        let products = derivedData.appending(path: "Build/Products", directoryHint: .isDirectory)
        let runs = (try? fileManager.contentsOfDirectory(at: products)) ?? []
        
        // An .xctestrun belongs to the Xcode that built it, so each developer directory has its own derived data.
        guard let testRun = runs.filter({ $0.pathExtension == "xctestrun" && $0.lastPathComponent.contains(build.platform.sdkName) }).sorted(by: { $0.lastPathComponent > $1.lastPathComponent }).first else {
            throw CaptureRunError.noTestRun(products.path(percentEncoded: false))
        }
        
        return testRun
    }
    
    private func run(
        _ pass: RunPlan.Pass,
        testRun: URL,
        context: RunContext,
        events: @escaping @Sendable (RunEvent) -> Void,
        prompt: @escaping @Sendable (RunPrompt) async -> Bool
    ) async throws {
        let udid: String?
        
        if pass.platform == .macOS {
            udid = nil
        } else {
            guard let spec = pass.simulator else {
                throw CaptureRunError.noSimulator(pass.deviceClass)
            }
            
            events(.preparing(pass.simulatorName))
            udid = try await prepareSimulator(named: pass.simulatorName, spec: spec, overridesStatusBar: context.overridesStatusBar)
        }
        
        var attempt = 1
        
        while true {
            if pass.posture == .unfolded {
                guard await prompt(.unfoldDuo(simulatorName: pass.simulatorName, attempt: attempt)) else {
                    throw CaptureRunError.cancelled
                }
            }
            
            events(.passStarted(pass))
            let result = try await test(pass, testRun: testRun, udid: udid, context: context, attempt: attempt, events: events)
            
            // A folded Duo fails the inner display's expectation, so ask again.
            if pass.posture == .unfolded, result.failures.contains(where: \.isExpectationFailure), attempt < 3 {
                attempt += 1
                continue
            }
            
            events(.passFinished(pass, captures: result.captures, failures: result.failures, resultBundle: result.bundle))
            return
        }
    }
    
    /// `test-without-building` for one pass, then the import. Retries once after rebooting a "Busy" simulator.
    func test(
        _ pass: RunPlan.Pass,
        testRun: URL,
        udid: String?,
        context: RunContext,
        attempt: Int,
        events: @escaping @Sendable (RunEvent) -> Void
    ) async throws -> (captures: [RunnerCapture], failures: [TestFailure], bundle: URL) {
        var retried = false
        
        while true {
            let bundle = context.resultsFolder().appending(path: "\(pass.id)-\(attempt)\(retried ? "-retry" : "").xcresult")
            try? fileManager.removeItem(at: bundle)
            try? fileManager.createDirectory(at: bundle.deletingLastPathComponent())
            
            let output = try await processRunner.run(
                testCommand(pass, testRun: testRun, udid: udid, bundle: bundle, context: context),
                onOutput: { events(.log($0)) }
            )
            
            if !output.succeeded, !retried, let udid, Self.needsReboot(output.combined) {
                retried = true
                events(.log("The simulator wasn't ready, so it's restarting and the pass runs again.\n"))
                try await guardStagehandSimulator(udid: udid, name: pass.simulatorName)
                _ = try await processRunner.run(.xcrun(["simctl", "shutdown", udid], developerDir: pass.developerDir))
                try await boot(udid: udid, developerDir: pass.developerDir)
                continue
            }
            
            guard fileManager.fileExists(at: bundle) else {
                throw CaptureRunError.importFailed("xcodebuild didn't write a result bundle.\n" + String(output.combined.suffix(1500)))
            }
            
            let captures = try await importAttachments(from: bundle, locale: pass.locale, developerDir: pass.developerDir)
            let failures = try await failures(in: bundle, developerDir: pass.developerDir)
            return (captures, failures, bundle)
        }
    }
    
    /// The `test-without-building` command line for a pass.
    public func testCommand(_ pass: RunPlan.Pass, testRun: URL, udid: String?, bundle: URL, context: RunContext) -> Command {
        var arguments = [
            "xcodebuild", "test-without-building",
            "-xctestrun", testRun.path(percentEncoded: false),
            "-destination", udid.map { "id=\($0)" } ?? "platform=macOS",
            // NOTE: - One simulator per pass. Parallel testing would clone it (losing the Duo's unfolded state) and
            // run screenshots side by side; FlaskMaster's screenshot scheme also asks for it off.
            "-parallel-testing-enabled", "NO",
            "-testLanguage", pass.appLocale.language,
        ]
        
        if let region = pass.appLocale.region {
            arguments += ["-testRegion", region]
        }
        
        arguments += ["-resultBundlePath", bundle.path(percentEncoded: false)]
        arguments += pass.onlyTesting.map { "-only-testing:\($0)" }
        
        // NOTE: - xcodebuild strips the TEST_RUNNER_ prefix and passes these to the test runner. Anything else set on
        // xcodebuild doesn't reach the tests.
        var environment = [
            "TEST_RUNNER_STAGEHAND_LOCALE": pass.locale,
            "TEST_RUNNER_STAGEHAND_RUN_ID": context.runID,
            "TEST_RUNNER_STAGEHAND_EXPECTED_CLASS": pass.deviceClass.rawValue,
            "TEST_RUNNER_STAGEHAND_FOLDER_OUTPUT": "off",
            "TEST_RUNNER_STAGEHAND_APP_LANGUAGE": pass.appLocale.language,
        ]
        
        // NOTE: - `-testLanguage` only reaches the test runner, so the kit launches the app with these too.
        if let region = pass.appLocale.region {
            environment["TEST_RUNNER_STAGEHAND_APP_REGION"] = region
        }
        
        return .xcrun(arguments, developerDir: pass.developerDir, environment: environment)
    }
    
    static func needsReboot(_ output: String) -> Bool {
        output.contains("Busy") || output.localizedCaseInsensitiveContains("failed preflight checks")
    }
    
    // MARK: - Simulators
    
    /// Finds or creates Stagehand's simulator for a spec, boots it, and sets its appearance and status bar.
    public func prepareSimulator(named name: String, spec: SimulatorSpec, overridesStatusBar: Bool) async throws -> String {
        guard name.hasPrefix(Self.simulatorPrefix) else {
            throw CaptureRunError.notAStagehandSimulator(name)
        }
        
        let list = try SimctlList.parse(try await processRunner.run(.xcrun(["simctl", "list", "-j", "devices"], developerDir: spec.developerDir)).stdout)
        let udid: String
        
        if let existing = list.device(named: name, runtime: spec.runtime), existing.deviceTypeIdentifier.map({ $0 == spec.deviceType }) ?? true {
            udid = existing.udid
        } else {
            let created = try await processRunner.run(.xcrun(["simctl", "create", name, spec.deviceType, spec.runtime], developerDir: spec.developerDir))
            
            guard created.succeeded else {
                throw CaptureRunError.simulatorFailed(name, reason: created.combined)
            }
            
            udid = created.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        
        try await boot(udid: udid, developerDir: spec.developerDir)
        _ = try await processRunner.run(.xcrun(["simctl", "ui", udid, "appearance", "light"], developerDir: spec.developerDir))
        
        if overridesStatusBar {
            _ = try await processRunner.run(.xcrun([
                "simctl", "status_bar", udid, "override",
                "--time", "9:41",
                "--dataNetwork", "wifi",
                "--wifiMode", "active",
                "--wifiBars", "3",
                "--cellularMode", "active",
                "--cellularBars", "4",
                "--batteryState", "charged",
                "--batteryLevel", "100",
            ], developerDir: spec.developerDir))
        }
        
        return udid
    }
    
    private func boot(udid: String, developerDir: String?) async throws {
        // Booting an already booted simulator fails harmlessly; bootstatus waits until it's ready either way.
        _ = try await processRunner.run(.xcrun(["simctl", "boot", udid], developerDir: developerDir))
        let status = try await processRunner.run(.xcrun(["simctl", "bootstatus", udid, "-b"], developerDir: developerDir))
        
        guard status.succeeded else {
            throw CaptureRunError.simulatorFailed(udid, reason: status.combined)
        }
    }
    
    /// Refuses to change a simulator that isn't one of Stagehand's.
    private func guardStagehandSimulator(udid: String, name: String) async throws {
        guard name.hasPrefix(Self.simulatorPrefix) else {
            throw CaptureRunError.notAStagehandSimulator(name)
        }
    }
    
    // MARK: - Importing
    
    /// Exports a result bundle's attachments and pairs each capture's image with its metadata.
    public func importAttachments(from bundle: URL, locale: LocaleID, developerDir: String?) async throws -> [RunnerCapture] {
        let folder = bundle.deletingPathExtension().appendingPathExtension("attachments")
        try? fileManager.removeItem(at: folder)
        try fileManager.createDirectory(at: folder)
        
        let output = try await processRunner.run(.xcrun([
            "xcresulttool", "export", "attachments",
            "--path", bundle.path(percentEncoded: false),
            "--output-path", folder.path(percentEncoded: false),
        ], developerDir: developerDir))
        
        guard output.succeeded else {
            throw CaptureRunError.importFailed(output.combined)
        }
        
        let manifest = try AttachmentManifest.parse(fileManager.read(folder.appending(path: "manifest.json")))
        let decoder = Shot.makeDecoder()
        var captures: [RunnerCapture] = []
        
        for attachment in manifest.captures() {
            guard let imageFile = attachment.imageFile, let metadataFile = attachment.metadataFile else {
                Logger.runner.warning("Capture \(attachment.captureID, privacy: .public) is missing its image or metadata")
                continue
            }
            
            let shot = try decoder.decode(Shot.self, from: fileManager.read(folder.appending(path: metadataFile)))
            let png = try fileManager.read(folder.appending(path: imageFile))
            captures.append(RunnerCapture(shot: shot, png: png, testIdentifier: attachment.testIdentifier, locale: shot.locale ?? locale))
        }
        
        // NOTE: - Apps that don't use the kit (like FlaskMaster, through MJScreenshotTesting, and TrekPoint) attach
        // plain screenshots. Each becomes a capture keyed by its name, classified by its pixel size.
        for attachment in manifest.plainScreenshots() {
            let data = try fileManager.read(folder.appending(path: attachment.imageFile))
            
            guard let image = CGImage.decode(data), let png = image.flattened()?.pngData() else {
                Logger.runner.warning("Skipping attachment \(attachment.name, privacy: .public): not a readable image")
                continue
            }
            
            guard let classification = DeviceTable.standard.classify(width: image.width, height: image.height) else {
                Logger.runner.warning("Skipping attachment \(attachment.name, privacy: .public): \(image.width) × \(image.height) isn't in devices.json")
                continue
            }
            
            let shot = Shot(
                captureID: UUID(),
                name: attachment.name.slugified,
                deviceClass: classification.deviceClass,
                targetID: classification.target.id,
                pixelWidth: image.width,
                pixelHeight: image.height,
                locale: locale,
                capturedAt: clock.now
            )
            captures.append(RunnerCapture(shot: shot, png: png, testIdentifier: attachment.testIdentifier, locale: locale))
        }
        
        return captures
    }
    
    func failures(in bundle: URL, developerDir: String?) async throws -> [TestFailure] {
        let output = try await processRunner.run(.xcrun([
            "xcresulttool", "get", "test-results", "tests",
            "--path", bundle.path(percentEncoded: false),
        ], developerDir: developerDir))
        
        guard output.succeeded else {
            return []
        }
        
        return (try? TestResults.parse(output.stdout).failures) ?? []
    }
}

enum CaptureRunnerKey: DependencyKey {
    static let liveValue = CaptureRunner()
    static var testValue: CaptureRunner { CaptureRunner() }
}

extension DependencyValues {
    public var captureRunner: CaptureRunner {
        get { self[CaptureRunnerKey.self] }
        set { self[CaptureRunnerKey.self] = newValue }
    }
}
#endif
