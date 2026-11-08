import CoreGraphics
import Foundation
import SwiftUI

public enum ExportError: Error, Equatable, LocalizedError {
    case renderFailed(String)
    case encodingFailed(String)
    case writeFailed(String, reason: String)
    case nothingToExport
    
    public var errorDescription: String? {
        switch self {
        case let .renderFailed(name): "\(name) couldn't be rendered."
        case let .encodingFailed(name): "\(name) couldn't be encoded as PNG."
        case let .writeFailed(path, reason): "\(path) couldn't be written: \(reason)"
        case .nothingToExport: "There's nothing to export."
        }
    }
}

/// Renders scenes to images through `ImageRenderer`.
@MainActor
public enum SceneRenderer {
    /// The scene at a scale (1 for exports), or `nil` when rendering fails.
    public static func render(_ scene: ResolvedScene, images: SceneImages, scale: CGFloat = 1) -> CGImage? {
        let renderer = ImageRenderer(content: SceneView(scene: scene, images: images))
        renderer.scale = scale
        renderer.proposedSize = ProposedViewSize(scene.canvas)
        renderer.isOpaque = true
        return renderer.cgImage
    }
    
    /// The scene at its exact pixel size, flattened onto an opaque context, as PNG.
    public static func exportPNG(_ scene: ResolvedScene, images: SceneImages, name: String) throws(ExportError) -> Data {
        guard let image = render(scene, images: images, scale: 1) else {
            throw .renderFailed(name)
        }
        
        let background = switch scene.background {
        case let .solid(color): color.cgColor
        case let .linear(colors, _), let .radial(colors, _, _): (colors.first ?? .black).cgColor
        }
        
        guard let flat = image.flattened(over: background), let data = flat.pngData() else {
            throw .encodingFailed(name)
        }
        
        return data
    }
}
