import Foundation

/// A background: a color token, or a gradient of tokens.
public enum Fill: Codable, Hashable, Sendable {
    case color(token: String)
    
    /// A linear gradient at an angle in degrees (0 runs top to bottom).
    case linearGradient(tokens: [String], angle: Double)
    
    /// A radial gradient from a center, with a radius in fractions of the canvas width.
    case radialGradient(tokens: [String], center: NormPoint, radius: Double)
    
    // MARK: - Computed Properties
    
    /// Every token the fill uses.
    public var tokens: [String] {
        switch self {
        case let .color(token): [token]
        case let .linearGradient(tokens, _): tokens
        case let .radialGradient(tokens, _, _): tokens
        }
    }
}

/// A font, by PostScript name, from the document's `fonts/`.
///
/// Names that start with `system-` use the system font at a weight (`system-bold`, `system-heavy`), so a
/// style can be designed before its fonts are chosen.
public struct FontSpec: Codable, Hashable, Sendable {
    public var postScriptName: String
    
    public init(postScriptName: String) {
        self.postScriptName = postScriptName
    }
    
    public static let systemBold = FontSpec(postScriptName: "system-bold")
    public static let systemHeavy = FontSpec(postScriptName: "system-heavy")
    public static let systemRegular = FontSpec(postScriptName: "system-regular")
    public static let systemMedium = FontSpec(postScriptName: "system-medium")
    
    // MARK: - Computed Properties
    
    /// The weight's name when this is a system font, like `bold`.
    public var systemWeight: String? {
        postScriptName.hasPrefix("system-") ? String(postScriptName.dropFirst("system-".count)) : nil
    }
    
    public var displayName: String {
        systemWeight.map { "System \($0.capitalized)" } ?? postScriptName
    }
}

public enum LetterCase: String, Codable, Hashable, Sendable, CaseIterable {
    case asWritten
    case uppercase
    case lowercase
}

public enum TextAlign: String, Codable, Hashable, Sendable, CaseIterable {
    case leading
    case center
    case trailing
}

public enum VerticalAlign: String, Codable, Hashable, Sendable, CaseIterable {
    case top
    case center
    case bottom
}

/// A glow drawn behind the device in its own shape (the bezel's silhouette), which moves and rotates with it.
public struct Glow: Codable, Hashable, Sendable {
    public var colorToken: String
    
    /// How far the glow spreads, as a blur radius in fractions of the canvas width.
    public var blur: Double
    public var opacity: Double
    
    /// The silhouette's size before blurring, as a multiple of the device's.
    public var spread: Double
    
    /// From the device, in fractions of the canvas width and height.
    public var offset: NormPoint
    
    public init(colorToken: String, blur: Double = 0.06, opacity: Double = 0.7, spread: Double = 1, offset: NormPoint = NormPoint(x: 0, y: 0)) {
        self.colorToken = colorToken
        self.blur = blur
        self.opacity = opacity
        self.spread = spread
        self.offset = offset
    }
}

/// One of the nine points of a box: its corners, the middles of its edges, and its center.
public enum BoxAnchor: String, Codable, Hashable, Sendable, CaseIterable {
    case topLeading
    case top
    case topTrailing
    case leading
    case center
    case trailing
    case bottomLeading
    case bottom
    case bottomTrailing
    
    // MARK: - Computed Properties
    
    /// Where the point is in a unit box, from the top leading corner: 0, 0.5 or 1 on each axis.
    public var unit: (x: Double, y: Double) {
        switch self {
        case .topLeading: (0, 0)
        case .top: (0.5, 0)
        case .topTrailing: (1, 0)
        case .leading: (0, 0.5)
        case .center: (0.5, 0.5)
        case .trailing: (1, 0.5)
        case .bottomLeading: (0, 1)
        case .bottom: (0.5, 1)
        case .bottomTrailing: (1, 1)
        }
    }
    
    /// The point's direction from the center: -1, 0 or 1 on each axis.
    public var direction: (x: Double, y: Double) {
        (unit.x * 2 - 1, unit.y * 2 - 1)
    }
    
    /// The point on the opposite side of the center.
    public var opposite: BoxAnchor {
        let (x, y) = unit
        return BoxAnchor.allCases.first { $0.unit.x == 1 - x && $0.unit.y == 1 - y } ?? .center
    }
    
    /// Whether dragging this point resizes horizontally, vertically, or both.
    public var resizesHorizontally: Bool {
        unit.x != 0.5
    }
    
    public var resizesVertically: Bool {
        unit.y != 0.5
    }
    
    public var displayName: String {
        switch self {
        case .topLeading: "Top Leading"
        case .top: "Top"
        case .topTrailing: "Top Trailing"
        case .leading: "Leading"
        case .center: "Center"
        case .trailing: "Trailing"
        case .bottomLeading: "Bottom Leading"
        case .bottom: "Bottom"
        case .bottomTrailing: "Bottom Trailing"
        }
    }
}

public typealias BezelID = String

/// Which bezel a device is drawn in.
public enum BezelChoice: Codable, Hashable, Sendable {
    /// The library's default bezel for the target's device class ("Library Default"), which changes with the library.
    case matchTarget
    
    /// A specific bezel, which stays until it's changed by hand. New template layouts pin one, and projects embed it.
    case pinned(BezelID)
    
    /// No bezel: the capture alone, with rounded corners and a shadow.
    case none
}

/// A template's ID. Format 2's variants (`straight`, `tilted` and `zoomed`) became templates with the same IDs, and
/// new templates get a UUID's string.
public struct TemplateID: RawRepresentable, Codable, Hashable, Sendable, CodingKeyRepresentable, ExpressibleByStringLiteral, Comparable {
    public var rawValue: String
    
    public init(rawValue: String) {
        self.rawValue = rawValue
    }
    
    public init(stringLiteral value: String) {
        self.rawValue = value
    }
    
    public init(from decoder: any Decoder) throws {
        self.rawValue = try decoder.singleValueContainer().decode(String.self)
    }
    
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
    
    public init?<T: CodingKey>(codingKey: T) {
        self.rawValue = codingKey.stringValue
    }
    
    public var codingKey: any CodingKey {
        AnyCodingKey(rawValue)
    }
    
    public static func < (lhs: TemplateID, rhs: TemplateID) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
    
    public static let straight: TemplateID = "straight"
    public static let tilted: TemplateID = "tilted"
    public static let zoomed: TemplateID = "zoomed"
    
    /// A new, unique ID.
    public static func make() -> TemplateID {
        TemplateID(rawValue: UUID().uuidString.lowercased())
    }
}

/// The two text roles on a slide.
public enum TextRole: String, Codable, Hashable, Sendable, CaseIterable, CodingKeyRepresentable {
    case primary
    case secondary
    
    public var displayName: String {
        switch self {
        case .primary: "Primary"
        case .secondary: "Secondary"
        }
    }
}

struct AnyCodingKey: CodingKey {
    var stringValue: String
    var intValue: Int?
    
    init(_ string: String) {
        self.stringValue = string
    }
    
    init?(stringValue: String) {
        self.stringValue = stringValue
    }
    
    init?(intValue: Int) {
        self.stringValue = String(intValue)
        self.intValue = intValue
    }
}
