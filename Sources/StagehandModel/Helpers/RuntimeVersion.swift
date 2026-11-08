import Foundation

/// A dotted version like a simulator runtime's `27.1` or `27.1.2`, compared numerically.
public struct RuntimeVersion: Comparable, Hashable, Sendable, CustomStringConvertible, Codable {
    public var components: [Int]
    
    public init?(_ string: String) {
        let parts = string.split(separator: ".").map { Int($0) }
        
        guard !parts.isEmpty, !parts.contains(nil) else {
            return nil
        }
        
        self.components = parts.compactMap { $0 }
    }
    
    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let string = try container.decode(String.self)
        
        guard let version = RuntimeVersion(string) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "\(string) isn't a version")
        }
        
        self = version
    }
    
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(description)
    }
    
    // MARK: - Computed Properties
    
    public var description: String {
        components.map(String.init).joined(separator: ".")
    }
    
    // MARK: - Functions
    
    public static func < (lhs: RuntimeVersion, rhs: RuntimeVersion) -> Bool {
        let count = max(lhs.components.count, rhs.components.count)
        
        for index in 0..<count {
            let left = index < lhs.components.count ? lhs.components[index] : 0
            let right = index < rhs.components.count ? rhs.components[index] : 0
            
            if left != right {
                return left < right
            }
        }
        
        return false
    }
    
    public static func == (lhs: RuntimeVersion, rhs: RuntimeVersion) -> Bool {
        !(lhs < rhs) && !(rhs < lhs)
    }
    
    public func hash(into hasher: inout Hasher) {
        var trimmed = components
        
        while trimmed.last == 0 {
            trimmed.removeLast()
        }
        
        hasher.combine(trimmed)
    }
}
