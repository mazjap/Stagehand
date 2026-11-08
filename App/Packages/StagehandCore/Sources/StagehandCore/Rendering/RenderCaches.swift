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
