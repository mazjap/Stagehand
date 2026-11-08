import CoreGraphics
import SwiftUI

/// Measures text by laying out SwiftUI `Text` through `ImageRenderer`, so measuring matches rendering.
@MainActor
public final class SwiftUITextMeasurer: TextMeasurer {
    private struct Key: Hashable {
        var text: String
        var font: ResolvedFont
        var tracking: Double
        var lineSpacing: Double
        var width: Double?
    }
    
    private var cache: [Key: CGSize] = [:]
    private var lineHeights: [FontSpec: Double] = [:]
    
    public init() {}
    
    // MARK: - Functions
    
    public func measure(_ text: String, font: ResolvedFont, tracking: Double, lineSpacing: Double, width: Double) -> TextMeasurement {
        let full = size(of: text, font: font, tracking: tracking, lineSpacing: lineSpacing, width: width)
        let line = size(of: "Ag", font: font, tracking: tracking, lineSpacing: lineSpacing, width: nil)
        let lineHeight = max(line.height, 1)
        let lines = max(1, Int(((full.height + lineSpacing) / (lineHeight + lineSpacing)).rounded()))
        let widestWord = text
            .split(whereSeparator: \.isWhitespace)
            .map { size(of: String($0), font: font, tracking: tracking, lineSpacing: lineSpacing, width: nil).width }
            .max() ?? 0
        
        return TextMeasurement(size: full, lineCount: lines, widestWord: widestWord)
    }
    
    public func invalidate() {
        cache = [:]
        lineHeights = [:]
    }
    
    public func lineHeight(for font: FontSpec) -> Double {
        if let cached = lineHeights[font] {
            return cached
        }
        
        let reference = 100.0
        let height = size(of: "Ag", font: ResolvedFont(spec: font, size: reference), tracking: 0, lineSpacing: 0, width: nil).height
        let ratio = height > 0 ? height / reference : Resolver.defaultLineHeight
        lineHeights[font] = ratio
        return ratio
    }
    
    private func size(of text: String, font: ResolvedFont, tracking: Double, lineSpacing: Double, width: Double?) -> CGSize {
        let key = Key(text: text, font: font, tracking: tracking, lineSpacing: lineSpacing, width: width)
        
        if let cached = cache[key] {
            return cached
        }
        
        let base = Text(text)
            .font(font.font)
            .tracking(tracking)
            .lineSpacing(lineSpacing)
        
        let image: CGImage? = if let width {
            ImageRenderer(content: base.fixedSize(horizontal: false, vertical: true).frame(width: width)).cgImage
        } else {
            ImageRenderer(content: base.fixedSize()).cgImage
        }
        
        let size = image.map { CGSize(width: $0.width, height: $0.height) } ?? .zero
        cache[key] = size
        return size
    }
}
