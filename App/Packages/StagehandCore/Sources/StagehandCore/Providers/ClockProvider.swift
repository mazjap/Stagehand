import Dependencies
import Foundation

/// The current time, so tests get a fixed one.
public protocol ClockProvider: Sendable {
    var now: Date { get }
}

public struct LiveClock: ClockProvider {
    public init() {}
    
    public var now: Date {
        Date()
    }
}

public struct FixedClock: ClockProvider {
    public var now: Date
    
    public init(now: Date = .sampleDate) {
        self.now = now
    }
}

enum ClockProviderKey: DependencyKey {
    static let liveValue: any ClockProvider = LiveClock()
    static var testValue: any ClockProvider { FixedClock() }
}

extension DependencyValues {
    public var clock: any ClockProvider {
        get { self[ClockProviderKey.self] }
        set { self[ClockProviderKey.self] = newValue }
    }
}
