#if canImport(XCTest)
import XCTest

/// What a capture waits for before it settles and takes its screenshot.
public enum Readiness {
    /// The element exists.
    case element(@MainActor (XCUIApplication) -> XCUIElement)
    
    /// The element's value (or label) contains the text.
    case value(of: @MainActor (XCUIApplication) -> XCUIElement, contains: String)
    
    /// Polled until it returns true.
    case condition(@MainActor (XCUIApplication) -> Bool)
    
    // MARK: - Functions
    
    /// Waits until ready, returning a description of what timed out, or `nil` once ready.
    @MainActor
    func wait(in app: XCUIApplication, timeout: TimeInterval) -> String? {
        switch self {
        case let .element(element):
            let target = element(app)
            return target.waitForExistence(timeout: timeout) ? nil : "\(target) didn't appear within \(timeout) seconds"
        case let .value(element, text):
            let target = element(app)
            let ready = Self.poll(timeout: timeout) {
                let value = (target.value as? String) ?? ""
                return value.contains(text) || target.label.contains(text)
            }
            return ready ? nil : "\(target)'s value didn't contain \"\(text)\" within \(timeout) seconds"
        case let .condition(condition):
            let ready = Self.poll(timeout: timeout) { condition(app) }
            return ready ? nil : "the readiness condition wasn't met within \(timeout) seconds"
        }
    }
    
    @MainActor
    private static func poll(timeout: TimeInterval, interval: TimeInterval = 0.25, _ check: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        
        repeat {
            if check() {
                return true
            }
            
            RunLoop.current.run(until: Date().addingTimeInterval(interval))
        } while Date() < deadline
        
        return check()
    }
}
#endif
