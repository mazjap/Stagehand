import CoreGraphics
import Foundation
@testable import StagehandCore
import StagehandModel
import Testing

/// What `SceneView` draws, checked in the rendered pixels.
@MainActor
@Suite struct SceneViewTests {
    /// Regression test: text took a fixed width so it could wrap, and a line shorter than its box was centered in that
    /// width whatever its alignment, so leading and trailing text both drew centered.
    @Test(arguments: [TextAlign.leading, .center, .trailing])
    func textIsAlignedInItsBox(alignment: TextAlign) throws {
        var project = Project.fixture()
        project.style.updateTemplate(.straight) { $0.layouts[.phone]?.primary.alignment = alignment }
        var slide = project.slides(in: project.mainLineup)[0]
        slide.primary = Varying(["en-US": "Hi"])
        slide.template = Varying(.straight)
        
        let scene = Resolver.resolve(ResolveRequest(
            slide: slide,
            style: project.style,
            target: DeviceTable.target("iphone-dynamic-island-large"),
            locale: "en-US",
            sourceLocale: "en-US",
            captures: CaptureCatalog()
        ))
        let box = try #require(scene.primary).frame
        let scale = 0.25
        let image = try #require(SceneRenderer.render(scene, images: SceneImages(), scale: scale))
        let accent = try #require(RGBA(hex: "#FFA43C"))
        let ink = try #require(Self.inkColumns(in: image, rows: (box.minY * scale)...(box.maxY * scale), matching: accent))
        
        // The text is far narrower than its box, so where it sits says how it's aligned.
        let left = (Double(ink.lowerBound) / scale - box.minX) / box.width
        let right = (box.maxX - Double(ink.upperBound) / scale) / box.width
        
        switch alignment {
        case .leading:
            #expect(left < 0.05 && right > 0.5, "leading text should start at the box's left edge (left \(left), right \(right))")
        case .trailing:
            #expect(right < 0.05 && left > 0.5, "trailing text should end at the box's right edge (left \(left), right \(right))")
        case .center:
            #expect(abs(left - right) < 0.05, "centered text should have equal space on each side (left \(left), right \(right))")
        }
    }
    
    // MARK: - Helpers
    
    /// The first and last columns, within some rows, with a pixel close to a color.
    private static func inkColumns(in image: CGImage, rows: ClosedRange<Double>, matching color: RGBA) -> ClosedRange<Int>? {
        let width = image.width
        let height = image.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        
        let drew = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else {
                return false
            }
            
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        
        guard drew else {
            return nil
        }
        
        let target = [color.red, color.green, color.blue].map { Int(($0 * 255).rounded()) }
        var columns: [Int] = []
        let top = max(0, Int(rows.lowerBound))
        let bottom = min(height - 1, Int(rows.upperBound))
        
        for y in top...bottom {
            for x in 0..<width {
                let index = (y * width + x) * 4
                let distance = zip(target, pixels[index..<index + 3]).map { abs($0 - Int($1)) }.max() ?? 255
                
                if distance < 40 {
                    columns.append(x)
                }
            }
        }
        
        return columns.min().flatMap { min in columns.max().map { min...$0 } }
    }
}
