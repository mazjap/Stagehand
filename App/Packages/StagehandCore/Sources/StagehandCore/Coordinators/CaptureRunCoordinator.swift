#if os(macOS)
import Dependencies
import Foundation
import Observation
import OSLog
import StagehandModel

/// Runs captures for a project and shows their progress on its cells.
@Observable
@MainActor
public final class CaptureRunCoordinator {
    public enum Intent {
        case runAll
        case recapture(CellID)
        case cancel
        case answerPrompt(Bool)
        case clearLog
        case dismissAlert
    }
    
    public private(set) var isRunning = false
    public private(set) var log = ""
    public private(set) var step: String?
    public private(set) var statuses: [CaptureAddress: RunCellStatus] = [:]
    public private(set) var resultBundles: [CaptureAddress: URL] = [:]
    public private(set) var prompt: RunPrompt?
    public var alert: CoordinatorAlert?
    
    private let project: ProjectCoordinator
    
    @ObservationIgnored @Dependency(\.captureRunner) private var runner
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var promptContinuation: CheckedContinuation<Bool, Never>?
    
    public init(project: ProjectCoordinator) {
        self.project = project
    }
    
    // MARK: - Computed Properties
    
    /// A cell's run status in the selected locale.
    public func status(for cell: CellID) -> RunCellStatus? {
        address(for: cell, locale: project.selection.locale).flatMap { statuses[$0] }
    }
    
    public func resultBundle(for cell: CellID) -> URL? {
        address(for: cell, locale: project.selection.locale).flatMap { resultBundles[$0] }
    }
    
    // MARK: - Intents
    
    public func handle(_ intent: Intent) {
        switch intent {
        case .runAll:
            start(RunPlan.make(project: project.project))
        case let .recapture(cell):
            recapture(cell)
        case .cancel:
            task?.cancel()
            answer(false)
        case let .answerPrompt(answer):
            self.answer(answer)
        case .clearLog:
            log = ""
        case .dismissAlert:
            alert = nil
        }
    }
    
    private func recapture(_ cell: CellID) {
        guard let target = DeviceTable.standard.target(id: cell.targetID),
              let address = address(for: cell, locale: project.selection.locale) else {
            return
        }
        
        let link = project.project.appLink
        let platform = RunPlan.Platform(target.deviceClass).rawValue
        let testTarget = link?.platformTestTargets?[platform].flatMap { $0.isEmpty ? nil : $0 } ?? link?.testTarget ?? ""
        let only = project.document.captures.records[address]?.testIdentifier.map { identifier in
            // `-only-testing:` takes Target/Class/method, without the parentheses Swift Testing adds.
            let trimmed = identifier.hasSuffix("()") ? String(identifier.dropLast(2)) : identifier
            return "\(testTarget)/\(trimmed)"
        }
        
        start(RunPlan.make(
            project: project.project,
            classes: [target.deviceClass],
            locales: [project.selection.locale],
            onlyTesting: only.map { [$0] } ?? []
        ))
    }
    
    private func start(_ plan: RunPlan) {
        guard !isRunning else {
            return
        }
        
        guard let link = project.project.appLink else {
            alert = CoordinatorAlert(title: "Link an App First", message: CaptureRunError.noAppLink.errorDescription ?? "")
            return
        }
        
        let context = RunContext(link: link, runID: ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-"))
        
        for pass in plan.passes {
            for address in addresses(for: pass) {
                statuses[address] = .queued
            }
        }
        
        isRunning = true
        step = "Starting"
        log = ""
        
        let runner = runner
        let (events, continuation) = AsyncStream<RunEvent>.makeStream()
        
        let consumer = Task { @MainActor [weak self] in
            for await event in events {
                self?.apply(event)
            }
        }
        
        task = Task { [weak self] in
            
            do {
                try await runner.run(plan, context: context, events: { continuation.yield($0) }) { [weak self] prompt in
                    await self?.ask(prompt) ?? false
                }
            } catch is CancellationError {
                continuation.yield(.log("\nCancelled. Captures that already finished were kept.\n"))
            } catch {
                self?.alert = CoordinatorAlert(title: "Capture Run Failed", error: error)
            }
            
            continuation.finish()
            await consumer.value
            self?.finish()
        }
    }
    
    private func finish() {
        isRunning = false
        step = nil
        prompt = nil
        
        for (address, status) in statuses where status == .queued || status == .capturing {
            statuses[address] = nil
        }
    }
    
    private func ask(_ prompt: RunPrompt) async -> Bool {
        self.prompt = prompt
        
        return await withCheckedContinuation { continuation in
            promptContinuation = continuation
        }
    }
    
    private func answer(_ answer: Bool) {
        prompt = nil
        promptContinuation?.resume(returning: answer)
        promptContinuation = nil
    }
    
    private func apply(_ event: RunEvent) {
        switch event {
        case let .log(text):
            log += text
            
            if log.count > 200_000 {
                log = String(log.suffix(150_000))
            }
        case let .building(build):
            step = "Building for \(build.platform.rawValue)"
        case let .preparing(name):
            step = "Preparing \(name)"
        case let .passStarted(pass):
            step = "Capturing \(pass)"
            
            for address in addresses(for: pass) {
                statuses[address] = .capturing
            }
        case let .passFinished(pass, captures, failures, bundle):
            importCaptures(captures, pass: pass)
            var captured = Set<CaptureAddress>()
            
            for capture in captures {
                if let address = Self.address(for: capture.shot, locale: capture.locale) {
                    captured.insert(address)
                    statuses[address] = .captured
                    resultBundles[address] = bundle
                }
            }
            
            let message = failures.flatMap(\.messages).first ?? "No capture came back for this cell."
            
            for address in addresses(for: pass) where !captured.contains(address) {
                statuses[address] = .failed(message)
                resultBundles[address] = bundle
            }
        case let .passFailed(pass, message):
            log += "\n\(pass) failed: \(message)\n"
            
            for address in addresses(for: pass) {
                statuses[address] = .failed(message)
            }
        }
    }
    
    private func importCaptures(_ captures: [RunnerCapture], pass: RunPlan.Pass) {
        guard !captures.isEmpty else {
            return
        }
        
        project.edit("Run Captures") { contents in
            for capture in captures {
                guard let address = Self.address(for: capture.shot, locale: capture.locale) else {
                    Logger.runner.warning("Skipping \(capture.shot.name, privacy: .public): its size isn't in devices.json")
                    continue
                }
                
                contents.captures.records[address] = CaptureRecord(
                    address: address,
                    pixelWidth: capture.shot.pixelWidth,
                    pixelHeight: capture.shot.pixelHeight,
                    targetID: capture.shot.targetID,
                    source: .runner,
                    importedAt: capture.shot.capturedAt,
                    shot: capture.shot,
                    revision: (contents.captures.records[address]?.revision ?? 0) + 1,
                    testIdentifier: capture.testIdentifier
                )
                contents.captureFiles[address] = capture.png
            }
        }
    }
    
    // MARK: - Helpers
    
    private static func address(for shot: Shot, locale: LocaleID) -> CaptureAddress? {
        shot.deviceClass.map { CaptureAddress(key: shot.name, deviceClass: $0, locale: locale) }
    }
    
    private func address(for cell: CellID, locale: LocaleID) -> CaptureAddress? {
        guard let slide = project.project.slides[cell.slideID], let target = DeviceTable.standard.target(id: cell.targetID) else {
            return nil
        }
        
        return CaptureAddress(key: slide.captureKey[target.deviceClass], deviceClass: target.deviceClass, locale: locale)
    }
    
    /// The cells a pass fills: each slide's capture key for the pass's class, in its locale.
    private func addresses(for pass: RunPlan.Pass) -> [CaptureAddress] {
        let project = project.project
        let slides = project.devices.contains(pass.deviceClass) ? project.sets.flatMap { project.slides(in: $0, on: pass.deviceClass) } : []
        var seen = Set<CaptureAddress>()
        
        return slides.map { CaptureAddress(key: $0.captureKey[pass.deviceClass], deviceClass: pass.deviceClass, locale: pass.locale) }
            .filter { seen.insert($0).inserted }
    }
}
#endif
