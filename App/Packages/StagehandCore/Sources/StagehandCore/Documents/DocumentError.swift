import Foundation

public enum DocumentError: Error, Equatable, LocalizedError {
    case missingFile(String)
    case newerFormat(found: Int, supported: Int)
    case corrupt(String, reason: String)
    
    public var errorDescription: String? {
        switch self {
        case let .missingFile(name):
            "The document is missing \(name)."
        case let .newerFormat(found, supported):
            "This document was saved by a newer version of Stagehand (format \(found)). This version reads up to format \(supported)."
        case let .corrupt(name, reason):
            "\(name) couldn't be read: \(reason)"
        }
    }
}
