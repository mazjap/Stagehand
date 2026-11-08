import CoreGraphics
import Foundation
import StagehandModel

/// Contact sheet thumbnails, cached by the scene they draw and their scale.
///
/// A scene includes its images' references, which change when a capture is replaced, so a cell re-renders exactly
/// when something it draws changes.
@MainActor
public final class ThumbnailCache {
    private struct Key: Hashable {
        var scene: ResolvedScene
        var scale: Double
    }
    
    private var cache: [Key: CGImage] = [:]
    private var order: [Key] = []
    private let limit: Int
    
    /// How many thumbnails have been rendered, for tests.
    public private(set) var renderCount = 0
    
    public init(limit: Int = 400) {
        self.limit = limit
    }
    
    // MARK: - Functions
    
    public func thumbnail(for scene: ResolvedScene, scale: Double, images: () -> SceneImages) -> CGImage? {
        let key = Key(scene: scene, scale: scale)
        
        if let cached = cache[key] {
            return cached
        }
        
        guard let image = SceneRenderer.render(scene, images: images(), scale: scale) else {
            return nil
        }
        
        renderCount += 1
        cache[key] = image
        order.append(key)
        
        if order.count > limit {
            cache[order.removeFirst()] = nil
        }
        
        return image
    }
    
    public func removeAll() {
        cache = [:]
        order = []
    }
}

/// Auto-fit results, cached by everything a fit reads.
@MainActor
public final class AutoFitCache {
    private struct Key: Hashable {
        var slides: [Slide]
        var style: Style
        var target: DeviceTarget
        var locale: LocaleID
        var sourceLocale: LocaleID
    }
    
    private var cache: [Key: AutoFitResult] = [:]
    private let fitter: AutoFitter
    private let measurer: any TextMeasurer
    
    public init(measurer: any TextMeasurer) {
        self.fitter = AutoFitter(measurer: measurer)
        self.measurer = measurer
    }
    
    // MARK: - Functions
    
    public func result(slides: [Slide], style: Style, target: DeviceTarget, locale: LocaleID, sourceLocale: LocaleID) -> AutoFitResult {
        // Only what a fit reads goes into the key, so moving the device or changing a capture doesn't refit.
        let trimmed = slides.map { slide in
            var copy = slide
            copy.captureKey = Varying("")
            copy.title = ""
            copy.extraContent = [:]
            
            for device in copy.detachments.keys {
                copy.detachments[device]?.device = nil
                copy.detachments[device]?.extras = [:]
                
                if copy.detachments[device]?.isEmpty == true {
                    copy.detachments[device] = nil
                }
            }
            
            return copy
        }
        
        let key = Key(slides: trimmed, style: style, target: target, locale: locale, sourceLocale: sourceLocale)
        
        if let cached = cache[key] {
            return cached
        }
        
        let result = fitter.fit(slides: slides, style: style, target: target, locale: locale, sourceLocale: sourceLocale)
        cache[key] = result
        
        if cache.count > 200 {
            cache.removeAll()
            cache[key] = result
        }
        
        return result
    }
    
    /// Forgets every result and measurement, after fonts change.
    public func removeAll() {
        cache = [:]
        measurer.invalidate()
    }
}
