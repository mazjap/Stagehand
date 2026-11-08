import CoreGraphics
import Foundation
import StagehandModel

/// How a piece of text lays out at one size and width.
public struct TextMeasurement: Hashable, Sendable {
    public var size: CGSize
    public var lineCount: Int
    
    public init(size: CGSize, lineCount: Int) {
        self.size = size
        self.lineCount = lineCount
    }
}

/// Measures text. The live measurer lays out SwiftUI `Text`, so measuring matches rendering. Tests use a fake.
@MainActor
public protocol TextMeasurer: AnyObject {
    func measure(_ text: String, font: ResolvedFont, tracking: Double, lineSpacing: Double, width: Double) -> TextMeasurement
    
    /// A font's line height as a multiple of its size.
    func lineHeight(for font: FontSpec) -> Double
    
    /// Forgets every measurement, after fonts change.
    func invalidate()
}

/// Text is drawn at its style's size and wraps to as many lines as it needs. The resolver is pure, so it can't
/// measure: this resolves once to find each text's string, font and width, measures the lines each wraps to, and
/// resolves again with them, so each text box is as tall as its text (for anchoring, handles and snapping).
@MainActor
public enum TextWrapping {
    /// A scene with its text boxes as tall as the lines their text wraps to.
    public static func resolve(_ request: ResolveRequest, measurer: any TextMeasurer) -> ResolvedScene {
        let first = Resolver.resolve(request)
        let counts = lineCounts(in: first, measurer: measurer)
        
        // NOTE: - A request's text is one line until measured, so one-line text needs no second pass.
        guard counts.contains(where: { $0.value != (request.lineCounts[$0.key] ?? 1) }) else {
            return first
        }
        
        var measured = request
        measured.lineCounts = counts
        return Resolver.resolve(measured)
    }
    
    /// How many lines each text element in a scene wraps to at its box's width.
    public static func lineCounts(in scene: ResolvedScene, measurer: any TextMeasurer) -> [ElementRef: Int] {
        var counts: [ElementRef: Int] = [:]
        
        func lines(_ text: ResolvedText) -> Int {
            measurer.measure(text.string, font: text.font, tracking: text.tracking, lineSpacing: text.lineSpacing, width: text.frame.width).lineCount
        }
        
        if let primary = scene.primary {
            counts[.primary] = lines(primary)
        }
        
        if let secondary = scene.secondary {
            counts[.secondary] = lines(secondary)
        }
        
        for extra in scene.extras {
            if case let .text(text) = extra.content {
                counts[.extra(extra.id)] = lines(text)
            }
        }
        
        return counts
    }
}
