import Foundation
import StagehandModel

/// Checks a capture against the device class the runner expects.
public enum Expectation {
    /// The prefix of every expectation failure message. Stagehand's runner looks for it in test results.
    public static let messagePrefix = "stagehand.expectation:"
    
    /// A failure message when the capture isn't the expected class, or `nil` when it is (or nothing is expected).
    public static func check(expected: DeviceClass?, actual: DeviceClass?, width: Int, height: Int) -> String? {
        guard let expected, expected != actual else {
            return nil
        }
        
        let actualName = actual?.rawValue ?? "an unknown size"
        return "\(messagePrefix) expected \(expected.rawValue) but captured \(actualName) (\(width) × \(height))"
    }
}
