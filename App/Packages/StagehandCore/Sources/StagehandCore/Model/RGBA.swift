import Foundation

/// A color in sRGB, with components from 0 to 1.
public struct RGBA: Codable, Hashable, Sendable {
    public var red: Double
    public var green: Double
    public var blue: Double
    public var alpha: Double
    
    public init(red: Double, green: Double, blue: Double, alpha: Double = 1) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }
    
    /// A color from a hex string like `#FFA43C` or `FFA43CCC`.
    public init?(hex: String) {
        var string = hex.trimmingCharacters(in: .whitespaces)
        
        if string.hasPrefix("#") {
            string.removeFirst()
        }
        
        guard string.count == 6 || string.count == 8, let value = UInt64(string, radix: 16) else {
            return nil
        }
        
        let hasAlpha = string.count == 8
        let shift: UInt64 = hasAlpha ? 8 : 0
        
        self.init(
            red: Double((value >> (16 + shift)) & 0xFF) / 255,
            green: Double((value >> (8 + shift)) & 0xFF) / 255,
            blue: Double((value >> shift) & 0xFF) / 255,
            alpha: hasAlpha ? Double(value & 0xFF) / 255 : 1
        )
    }
    
    public static let black = RGBA(red: 0, green: 0, blue: 0)
    public static let white = RGBA(red: 1, green: 1, blue: 1)
    
    /// The color drawn for a token a style doesn't define, so a missing token is easy to spot.
    public static let missing = RGBA(red: 1, green: 0, blue: 1)
    
    // MARK: - Computed Properties
    
    /// `#RRGGBB`, or `#RRGGBBAA` when it isn't opaque.
    public var hex: String {
        func component(_ value: Double) -> String {
            String(format: "%02X", Int((min(max(value, 0), 1) * 255).rounded()))
        }
        
        let rgb = "#" + component(red) + component(green) + component(blue)
        return alpha < 1 ? rgb + component(alpha) : rgb
    }
}
