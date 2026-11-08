import CoreGraphics
import Foundation

/// A point in fractions of the canvas's width (`x`) and height (`y`), from the top left.
public struct NormPoint: Codable, Hashable, Sendable {
    public var x: Double
    public var y: Double
    
    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }
    
    // MARK: - Functions
    
    /// This point on a canvas of this size, in pixels.
    public func absolute(in canvas: CGSize) -> CGPoint {
        CGPoint(x: x * canvas.width, y: y * canvas.height)
    }
}

/// A rectangle in fractions of the canvas's width (`x`, `width`) and height (`y`, `height`), from the top left.
public struct NormRect: Codable, Hashable, Sendable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double
    
    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }
    
    // MARK: - Functions
    
    /// This rectangle on a canvas of this size, in pixels.
    public func absolute(in canvas: CGSize) -> CGRect {
        CGRect(x: x * canvas.width, y: y * canvas.height, width: width * canvas.width, height: height * canvas.height)
    }
    
    /// This rectangle moved by a fraction of the canvas.
    public func offsetBy(dx: Double, dy: Double) -> NormRect {
        NormRect(x: x + dx, y: y + dy, width: width, height: height)
    }
}

/// A per-device adjustment to a variant's placement.
public struct NormTransform: Codable, Hashable, Sendable {
    /// Fractions of the canvas width.
    public var dx: Double
    
    /// Fractions of the canvas height.
    public var dy: Double
    
    /// Degrees, added to the placement's rotation.
    public var rotation: Double
    
    /// Multiplies the placement's width.
    public var scale: Double
    
    public init(dx: Double = 0, dy: Double = 0, rotation: Double = 0, scale: Double = 1) {
        self.dx = dx
        self.dy = dy
        self.rotation = rotation
        self.scale = scale
    }
    
    public static let identity = NormTransform()
    
    // MARK: - Computed Properties
    
    public var isIdentity: Bool {
        self == .identity
    }
}
