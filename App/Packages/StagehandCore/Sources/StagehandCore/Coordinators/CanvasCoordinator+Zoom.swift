import CoreGraphics
import Foundation

// MARK: - Zooming and Panning

extension CanvasCoordinator {
    /// Space around the canvas at the zoom that fits, in points, so the handles on its edges can be reached.
    public static let fitMargin: Double = 24
    
    /// How much one ⌘+ or ⌘− zooms.
    public static let zoomStep = 1.25
    
    /// From a tenth of the size that fits, which leaves room to drag things far past the canvas's edges, to 16 times.
    public static let zoomRange: ClosedRange<Double> = 0.1...16
    
    /// How much of the canvas, in points, always stays in view when panning.
    public static let panKeepsVisible: Double = 80
    
    /// Points on screen per canvas pixel, for a view of this size: the scale that fits the canvas, times the zoom.
    public static func scale(canvas: CGSize, viewport: CGSize, zoom: Double) -> Double {
        guard canvas.width > 0, canvas.height > 0 else {
            return 0.01
        }
        
        let fit = min((viewport.width - 2 * fitMargin) / canvas.width, (viewport.height - 2 * fitMargin) / canvas.height)
        return max(0.01, fit) * zoom
    }
    
    /// Points on screen per canvas pixel at the current zoom.
    public var scale: Double {
        Self.scale(canvas: project.canvasScene?.canvas ?? .zero, viewport: viewport, zoom: zoom)
    }
    
    /// Whether the canvas is zoomed or panned away from fitting the view.
    public var isZoomed: Bool {
        zoom != 1 || pan != .zero
    }
    
    // MARK: - Functions
    
    /// Zooms, clamped to ``zoomRange``, keeping the canvas point under `anchor` (in points from the view's center)
    /// where it is. At the zoom that fits, the canvas centers again.
    func zoom(to newZoom: Double, around anchor: CGPoint) {
        let clamped = min(max(newZoom, Self.zoomRange.lowerBound), Self.zoomRange.upperBound)
        
        // NOTE: - Snaps to 1 within half a percent, so stepping out and back in lands on the fit exactly.
        let next = abs(clamped - 1) < 0.005 ? 1 : clamped
        let ratio = next / zoom
        
        // The point under the anchor is `anchor - pan` from the canvas's center, and that distance scales by `ratio`.
        let moved = CGSize(width: anchor.x - (anchor.x - pan.width) * ratio, height: anchor.y - (anchor.y - pan.height) * ratio)
        zoom = next
        pan = next == 1 ? .zero : clampedPan(moved)
    }
    
    /// Sets the pan only when it changes, since setting an observed property redraws the canvas even when it's equal,
    /// and the view's size comes in on every layout.
    func setPan(_ newPan: CGSize) {
        if pan != newPan {
            pan = newPan
        }
    }
    
    /// Keeps at least ``panKeepsVisible`` points of the canvas in view, so it can't be scrolled away and lost.
    func clampedPan(_ pan: CGSize) -> CGSize {
        guard viewport.width > 0, viewport.height > 0, let canvas = project.canvasScene?.canvas else {
            return pan
        }
        
        let scale = scale
        let limitX = max(0, (canvas.width * scale + viewport.width) / 2 - Self.panKeepsVisible)
        let limitY = max(0, (canvas.height * scale + viewport.height) / 2 - Self.panKeepsVisible)
        return CGSize(width: min(max(pan.width, -limitX), limitX), height: min(max(pan.height, -limitY), limitY))
    }
}
