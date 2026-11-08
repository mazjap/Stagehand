import Dependencies
import Foundation

/// A command line to run.
public struct Command: Hashable, Sendable, CustomStringConvertible {
    public var executable: String
    public var arguments: [String]
    
    /// Added to the current process's environment.
    public var environment: [String: String]
    
    public init(_ executable: String, _ arguments: [String], environment: [String: String] = [:]) {
        self.executable = executable
        self.arguments = arguments
        self.environment = environment
    }
    
    /// `xcrun <tool> <arguments>`, with another Xcode's developer directory when one is given.
    public static func xcrun(_ arguments: [String], developerDir: String? = nil, environment: [String: String] = [:]) -> Command {
        var environment = environment
        
        if let developerDir {
            environment["DEVELOPER_DIR"] = developerDir
        }
        
        return Command("/usr/bin/xcrun", arguments, environment: environment)
    }
    
    public var description: String {
        let env = environment.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }
        let quoted = arguments.map { $0.contains(" ") ? "'\($0)'" : $0 }
        return (env + [executable] + quoted).joined(separator: " ")
    }
}

/// What a command printed, and how it exited.
public struct ProcessOutput: Hashable, Sendable {
    public var exitCode: Int32
    public var stdout: String
    public var stderr: String
    
    public init(exitCode: Int32 = 0, stdout: String = "", stderr: String = "") {
        self.exitCode = exitCode
        self.stdout = stdout
        self.stderr = stderr
    }
    
    public var succeeded: Bool {
        exitCode == 0
    }
    
    public var combined: String {
        stdout + stderr
    }
}

/// Runs `xcodebuild`, `simctl` and `xcresulttool`, so tests can use a fake.
public protocol ProcessRunnerProvider: Sendable {
    /// Runs a command to completion. Cancelling the task ends the process.
    func run(_ command: Command, onOutput: (@Sendable (String) -> Void)?) async throws -> ProcessOutput
}

extension ProcessRunnerProvider {
    public func run(_ command: Command) async throws -> ProcessOutput {
        try await run(command, onOutput: nil)
    }
}

/// Records every command and answers each from a handler.
public final class FakeProcessRunner: ProcessRunnerProvider, @unchecked Sendable {
    public typealias Handler = @Sendable (Command) throws -> ProcessOutput
    
    private let lock = NSLock()
    private var recorded: [Command] = []
    private let handler: Handler
    
    public init(handler: @escaping Handler = { _ in ProcessOutput() }) {
        self.handler = handler
    }
    
    public var commands: [Command] {
        lock.withLock { recorded }
    }
    
    public func run(_ command: Command, onOutput: (@Sendable (String) -> Void)?) async throws -> ProcessOutput {
        lock.withLock { recorded.append(command) }
        let output = try handler(command)
        onOutput?(output.combined)
        return output
    }
}

#if os(macOS)
/// Runs commands with `Process`, streaming their output.
public struct LiveProcessRunner: ProcessRunnerProvider {
    public init() {}
    
    public func run(_ command: Command, onOutput: (@Sendable (String) -> Void)?) async throws -> ProcessOutput {
        let process = Process()
        process.executableURL = URL(filePath: command.executable)
        process.arguments = command.arguments
        process.environment = ProcessInfo.processInfo.environment.merging(command.environment) { $1 }
        
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        
        let collector = OutputCollector(onOutput: onOutput)
        stdout.fileHandleForReading.readabilityHandler = { handle in
            collector.append(handle.availableData, toError: false)
        }
        stderr.fileHandleForReading.readabilityHandler = { handle in
            collector.append(handle.availableData, toError: true)
        }
        
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<ProcessOutput, any Error>) in
                process.terminationHandler = { process in
                    stdout.fileHandleForReading.readabilityHandler = nil
                    stderr.fileHandleForReading.readabilityHandler = nil
                    collector.append(stdout.fileHandleForReading.readDataToEndOfFile(), toError: false)
                    collector.append(stderr.fileHandleForReading.readDataToEndOfFile(), toError: true)
                    
                    if Task.isCancelled {
                        continuation.resume(throwing: CancellationError())
                    } else {
                        continuation.resume(returning: collector.output(exitCode: process.terminationStatus))
                    }
                }
                
                do {
                    try process.run()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        } onCancel: {
            // NOTE: - xcodebuild ends its own children (the test runner and simulator sessions) on SIGINT, the way
            // Ctrl-C does, so interrupting it ends the whole run. A process that ignores it is terminated.
            if process.isRunning {
                process.interrupt()
                
                DispatchQueue.global().asyncAfter(deadline: .now() + 5) {
                    if process.isRunning {
                        process.terminate()
                    }
                }
            }
        }
    }
    
    private final class OutputCollector: @unchecked Sendable {
        private let lock = NSLock()
        private var stdout = Data()
        private var stderr = Data()
        private let onOutput: (@Sendable (String) -> Void)?
        
        init(onOutput: (@Sendable (String) -> Void)?) {
            self.onOutput = onOutput
        }
        
        func append(_ data: Data, toError: Bool) {
            guard !data.isEmpty else {
                return
            }
            
            lock.withLock {
                if toError {
                    stderr.append(data)
                } else {
                    stdout.append(data)
                }
            }
            
            onOutput?(String(decoding: data, as: UTF8.self))
        }
        
        func output(exitCode: Int32) -> ProcessOutput {
            lock.withLock {
                ProcessOutput(exitCode: exitCode, stdout: String(decoding: stdout, as: UTF8.self), stderr: String(decoding: stderr, as: UTF8.self))
            }
        }
    }
}
#endif

enum ProcessRunnerProviderKey: DependencyKey {
    #if os(macOS)
    static let liveValue: any ProcessRunnerProvider = LiveProcessRunner()
    #else
    static let liveValue: any ProcessRunnerProvider = FakeProcessRunner { _ in ProcessOutput(exitCode: 1, stderr: "Capturing runs only on the Mac.") }
    #endif
    static var testValue: any ProcessRunnerProvider { FakeProcessRunner() }
}

extension DependencyValues {
    public var processRunner: any ProcessRunnerProvider {
        get { self[ProcessRunnerProviderKey.self] }
        set { self[ProcessRunnerProviderKey.self] = newValue }
    }
}
