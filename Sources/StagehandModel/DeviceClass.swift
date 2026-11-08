import Foundation

/// A family of screens that share one layout, one set of captures and one bezel.
///
/// Classes are told apart by pixel size (through ``DeviceTable``), never by idiom: an idiom can't tell
/// an iPhone Duo's outer display from its inner one.
public enum DeviceClass: String, Codable, CaseIterable, Sendable, Hashable, CodingKeyRepresentable {
    case phone
    case duoOuter
    case duoInner
    case pad
    case mac
    case watch
    
    // MARK: - Computed Properties
    
    /// The class whose layout this one borrows until it has its own.
    ///
    /// The Duo's panels are close to an iPad's shape, so `duoOuter` falls back to `duoInner`, which falls back to `pad`.
    public var layoutFallback: DeviceClass? {
        switch self {
        case .duoOuter: .duoInner
        case .duoInner: .pad
        case .phone, .pad, .mac, .watch: nil
        }
    }
    
    /// This class, then each class it falls back to, in order.
    public var layoutFallbackChain: [DeviceClass] {
        var chain = [self]
        var next = layoutFallback
        
        while let current = next {
            chain.append(current)
            next = current.layoutFallback
        }
        
        return chain
    }
    
    /// A short name for the editor.
    public var displayName: String {
        switch self {
        case .phone: "iPhone"
        case .duoOuter: "iPhone Duo (outer)"
        case .duoInner: "iPhone Duo (inner)"
        case .pad: "iPad"
        case .mac: "Mac"
        case .watch: "Apple Watch"
        }
    }
}
