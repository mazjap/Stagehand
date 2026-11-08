import CoreGraphics
import Foundation
import StagehandModel

/// How a piece of text lays out at one size and width.
public struct TextMeasurement: Hashable, Sendable {
    public var size: CGSize
    public var lineCount: Int
    
    /// The widest word on its own line, which can't wrap.
    public var widestWord: Double
    
    public init(size: CGSize, lineCount: Int, widestWord: Double) {
        self.size = size
        self.lineCount = lineCount
        self.widestWord = widestWord
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

/// The text sizes for one set, device class and locale.
public struct AutoFitResult: Hashable, Sendable {
    /// The size every slide shares, in fractions of the canvas width: the smallest slide's.
    public var sizes: [TextRole: Double]
    public var overflowing: [Slide.ID: Set<TextRole>]
    
    /// Each slide's own largest fitting size, which it uses when the style fits each slide on its own.
    public var slideSizes: [Slide.ID: [TextRole: Double]]
    
    /// The style's size for each role, before fitting.
    public var styleSizes: [TextRole: Double]
    
    /// The slide whose text set a shared size below the style's.
    public var limiting: [TextRole: Slide.ID]
    
    public var scope: AutoFitScope
    
    public init(
        sizes: [TextRole: Double] = [:],
        overflowing: [Slide.ID: Set<TextRole>] = [:],
        slideSizes: [Slide.ID: [TextRole: Double]] = [:],
        styleSizes: [TextRole: Double] = [:],
        limiting: [TextRole: Slide.ID] = [:],
        scope: AutoFitScope = .lineup
    ) {
        self.sizes = sizes
        self.overflowing = overflowing
        self.slideSizes = slideSizes
        self.styleSizes = styleSizes
        self.limiting = limiting
        self.scope = scope
    }
    
    public func fitted(for slide: Slide.ID) -> FittedText {
        let own = scope == .slide ? sizes.merging(slideSizes[slide] ?? [:]) { _, own in own } : sizes
        return FittedText(sizes: own, overflowing: overflowing[slide] ?? [])
    }
    
    /// Why a slide's text is smaller than the style's, if it is: the fraction of the style's size it's drawn at, and
    /// the slide that made it shrink (itself, or, when the lineup shares one size, the slide with the longest text).
    public func shrinking(_ role: TextRole, on slide: Slide.ID) -> (fraction: Double, cause: Slide.ID)? {
        guard let base = styleSizes[role], base > 0, let size = fitted(for: slide).sizes[role], size < base - 0.000_1 else {
            return nil
        }
        
        let cause = scope == .slide ? slide : (limiting[role] ?? slide)
        return (size / base, cause)
    }
}

/// Finds the largest text size, up to the style's, at which every slide's text fits its frame and line limit.
///
/// Every slide in a lineup on a device then shares one size per role, and each locale is fitted on its own, so German never
/// shrinks English. Below the style's minimum, a slide is flagged as overflowing instead of shrinking further.
@MainActor
public struct AutoFitter {
    private let measurer: any TextMeasurer
    private let iterations: Int
    
    public init(measurer: any TextMeasurer, iterations: Int = 8) {
        self.measurer = measurer
        self.iterations = iterations
    }
    
    // MARK: - Functions
    
    public func fit(slides: [Slide], style: Style, target: DeviceTarget, locale: LocaleID, sourceLocale: LocaleID) -> AutoFitResult {
        let device = target.deviceClass
        let canvas = CGSize(width: target.exportSize.width, height: target.exportSize.height)
        var result = AutoFitResult(scope: style.autoFitScope)
        
        for role in TextRole.allCases {
            let textStyle = style.textStyle(role)
            let base = textStyle.size[device]
            let minimum = base * style.autoFitMinimum
            var setSize = base
            result.styleSizes[role] = base
            
            for slide in slides {
                guard let text = slide.text(role).text(for: device, locale: locale, source: sourceLocale)?.text, !text.isEmpty else {
                    continue
                }
                
                // Each slide's own template (and detachment) sets its text's width and line limit.
                let layout = Resolver.layout(for: slide, style: style, device: device).layout
                
                guard !layout.isHidden(role == .primary ? .primary : .secondary) else {
                    continue
                }
                
                let placement = layout.textPlacement(role)
                let width = placement.width * canvas.width
                let string = Resolver.applyCase(textStyle.letterCase[device], to: text, locale: locale)
                
                func fits(_ size: Double) -> Bool {
                    let pixels = size * canvas.width
                    let measurement = measurer.measure(
                        string,
                        font: ResolvedFont(spec: textStyle.font[device], size: pixels),
                        tracking: textStyle.tracking[device] * pixels,
                        lineSpacing: textStyle.lineSpacing[device] * pixels,
                        width: width
                    )
                    
                    // NOTE: - A box's height follows its font size and line limit, so fitting is only the line count
                    // and the widest word, which can't wrap.
                    return measurement.lineCount <= placement.lineLimit && measurement.widestWord <= width + 0.5
                }
                
                let slideSize: Double
                
                if fits(base) {
                    slideSize = base
                } else if !fits(minimum) {
                    slideSize = minimum
                    result.overflowing[slide.id, default: []].insert(role)
                } else {
                    var low = minimum
                    var high = base
                    
                    for _ in 0..<iterations {
                        let middle = (low + high) / 2
                        
                        if fits(middle) {
                            low = middle
                        } else {
                            high = middle
                        }
                    }
                    
                    slideSize = low
                }
                
                result.slideSizes[slide.id, default: [:]][role] = slideSize
                
                if slideSize < setSize {
                    setSize = slideSize
                    result.limiting[role] = slide.id
                }
            }
            
            result.sizes[role] = setSize
        }
        
        return result
    }
}
