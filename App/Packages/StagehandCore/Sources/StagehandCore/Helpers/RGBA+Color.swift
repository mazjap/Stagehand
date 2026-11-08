import CoreGraphics
import SwiftUI

extension RGBA {
    public var color: Color {
        Color(.sRGB, red: red, green: green, blue: blue, opacity: alpha)
    }
    
    public var cgColor: CGColor {
        CGColor(srgbRed: red, green: green, blue: blue, alpha: alpha)
    }
    
    /// The nearest `RGBA` to a SwiftUI color, in sRGB.
    public init(_ color: Color) {
        let resolved = color.resolve(in: EnvironmentValues())
        self.init(red: Double(resolved.red), green: Double(resolved.green), blue: Double(resolved.blue), alpha: Double(resolved.opacity))
    }
}

extension ResolvedFont {
    /// The SwiftUI font: a registered font by PostScript name, or the system font at a weight.
    public var font: Font {
        if let weight = spec.systemWeight {
            return .system(size: size, weight: Self.weight(named: weight))
        }
        
        return .custom(spec.postScriptName, fixedSize: size)
    }
    
    static func weight(named name: String) -> Font.Weight {
        switch name {
        case "ultralight": .ultraLight
        case "thin": .thin
        case "light": .light
        case "medium": .medium
        case "semibold": .semibold
        case "bold": .bold
        case "heavy": .heavy
        case "black": .black
        default: .regular
        }
    }
}

extension TextAlign {
    public var textAlignment: TextAlignment {
        switch self {
        case .leading: .leading
        case .center: .center
        case .trailing: .trailing
        }
    }
    
    public var horizontalAlignment: HorizontalAlignment {
        switch self {
        case .leading: .leading
        case .center: .center
        case .trailing: .trailing
        }
    }
}

extension VerticalAlign {
    public var verticalAlignment: SwiftUI.VerticalAlignment {
        switch self {
        case .top: .top
        case .center: .center
        case .bottom: .bottom
        }
    }
}
