import CoreGraphics
import Foundation

/// The decoded images a scene draws, by reference.
public struct SceneImages: @unchecked Sendable {
    public var images: [ImageRef: CGImage]
    
    public init(_ images: [ImageRef: CGImage] = [:]) {
        self.images = images
    }
    
    public subscript(_ ref: ImageRef?) -> CGImage? {
        ref.flatMap { images[$0] }
    }
}

/// Decodes and caches the images scenes draw.
@MainActor
public final class ImageStore {
    public typealias Loader = (ImageRef) -> CGImage?
    
    private var cache: [ImageRef: CGImage] = [:]
    private let loader: Loader
    
    public init(loader: @escaping Loader) {
        self.loader = loader
    }
    
    // MARK: - Functions
    
    public func image(_ ref: ImageRef) -> CGImage? {
        if let cached = cache[ref] {
            return cached
        }
        
        let image = loader(ref)
        cache[ref] = image
        return image
    }
    
    /// Every image a scene draws.
    public func images(for scene: ResolvedScene) -> SceneImages {
        var images: [ImageRef: CGImage] = [:]
        
        for ref in scene.imageRefs {
            images[ref] = image(ref)
        }
        
        return SceneImages(images)
    }
    
    /// Forgets images, so the next request loads them again.
    public func invalidate(where predicate: (ImageRef) -> Bool = { _ in true }) {
        cache = cache.filter { !predicate($0.key) }
    }
}
