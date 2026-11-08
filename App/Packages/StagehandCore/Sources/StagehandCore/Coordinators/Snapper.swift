import CoreGraphics
import Foundation

/// A line something snapped to, drawn on the canvas while dragging.
public struct SnapGuide: Hashable, Sendable {
    public enum Axis: Hashable, Sendable {
        /// A vertical line at an x position.
        case vertical
        
        /// A horizontal line at a y position.
        case horizontal
    }
    
    public var axis: Axis
    
    /// In canvas pixels.
    public var position: Double
    
    public init(axis: Axis, position: Double) {
        self.axis = axis
        self.position = position
    }
}

/// Snaps a moving rectangle's edges and center onto the canvas's edges and center, and other elements'.
public enum Snapper {
    public enum Edge: Hashable, Sendable, CaseIterable {
        case min
        case mid
        case max
    }
    
    /// Positions to snap to on each axis, in canvas pixels.
    public struct Targets: Hashable, Sendable {
        public var xs: [Double]
        public var ys: [Double]
        
        public init(xs: [Double], ys: [Double]) {
            self.xs = xs
            self.ys = ys
        }
        
        /// The canvas's edges and center, and each other element's edges and center.
        public init(canvas: CGSize, others: [CGRect]) {
            self.xs = [0, canvas.width / 2, canvas.width] + others.flatMap { [$0.minX, $0.midX, $0.maxX] }
            self.ys = [0, canvas.height / 2, canvas.height] + others.flatMap { [$0.minY, $0.midY, $0.maxY] }
        }
    }
    
    public struct Result: Hashable, Sendable {
        /// What to add to the rectangle's position so its nearest edge lands on a target.
        public var offset: CGSize
        public var guides: [SnapGuide]
    }
    
    /// The smallest offset, within the tolerance on each axis, that puts one of the given edges on a target.
    public static func snap(_ rect: CGRect, xEdges: [Edge] = Edge.allCases, yEdges: [Edge] = Edge.allCases, to targets: Targets, tolerance: Double) -> Result {
        let xValues = xEdges.map { value(of: $0, min: rect.minX, mid: rect.midX, max: rect.maxX) }
        let yValues = yEdges.map { value(of: $0, min: rect.minY, mid: rect.midY, max: rect.maxY) }
        let x = nearest(xValues, targets.xs, tolerance: tolerance)
        let y = nearest(yValues, targets.ys, tolerance: tolerance)
        
        // Every target the snapped edges now touch gets a guide, so ties all show.
        let xGuides = x.map { offset in matches(xValues, offset: offset, targets.xs).map { SnapGuide(axis: .vertical, position: $0) } } ?? []
        let yGuides = y.map { offset in matches(yValues, offset: offset, targets.ys).map { SnapGuide(axis: .horizontal, position: $0) } } ?? []
        
        return Result(offset: CGSize(width: x ?? 0, height: y ?? 0), guides: xGuides + yGuides)
    }
    
    private static func value(of edge: Edge, min: Double, mid: Double, max: Double) -> Double {
        switch edge {
        case .min: min
        case .mid: mid
        case .max: max
        }
    }
    
    private static func nearest(_ values: [Double], _ targets: [Double], tolerance: Double) -> Double? {
        var best: Double?
        
        for value in values {
            for target in targets {
                let offset = target - value
                
                if abs(offset) <= tolerance, abs(offset) < abs(best ?? .infinity) {
                    best = offset
                }
            }
        }
        
        return best
    }
    
    private static func matches(_ values: [Double], offset: Double, _ targets: [Double]) -> [Double] {
        let moved = values.map { $0 + offset }
        return Array(Set(targets.filter { target in moved.contains { abs($0 - target) < 0.5 } })).sorted()
    }
}
