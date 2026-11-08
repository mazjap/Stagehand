#if canImport(XCTest)
import CoreGraphics
import Foundation
import StagehandScene

/// The capture kit's settings for a screenshot test target.
public enum Stagehand {
    /// How captures are staged and saved.
    public struct Configuration: Sendable {
        /// Launch arguments every capture launches the app with. The kit adds `-stagehand-capturing`.
        public var launchArguments: [String] = []
        
        /// Environment variables every capture launches the app with.
        public var launchEnvironment: [String: String] = [:]
        
        /// The environment variable the scene is sent in.
        public var sceneEnvironmentKey: String = StagehandScene.environmentKey
        
        /// A folder captures are also written into, unless the runner turns it off.
        public var folder: FolderOutput?
        
        /// The window size Mac captures ask the app for, in points.
        public var macWindowSize: CGSize = CGSize(width: 1440, height: 900)
        
        /// How long readiness is waited for before the test fails.
        public var timeout: TimeInterval = 10
        
        /// How long to settle when there's no readiness check.
        public var settle: TimeInterval = 3
        
        /// How long to settle after readiness.
        public var settleAfterReadiness: TimeInterval = 1
        
        public init() {}
    }
    
    private final class Storage: @unchecked Sendable {
        private let lock = NSLock()
        private var value = Configuration()
        
        func read() -> Configuration {
            lock.withLock { value }
        }
        
        func update(_ body: (inout Configuration) -> Void) {
            lock.withLock { body(&value) }
        }
    }
    
    private static let storage = Storage()
    
    // MARK: - Functions
    
    /// Changes the configuration, usually from a test case's `class func setUp()`.
    public static func configure(_ body: (inout Configuration) -> Void) {
        storage.update(body)
    }
    
    /// The current configuration.
    public static var configuration: Configuration {
        storage.read()
    }
    
    /// Restores the default configuration.
    public static func reset() {
        storage.update { $0 = Configuration() }
    }
}
#endif
