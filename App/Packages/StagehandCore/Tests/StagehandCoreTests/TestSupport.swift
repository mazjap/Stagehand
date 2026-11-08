import CoreGraphics
import Foundation
@testable import StagehandCore
import StagehandModel

/// Measures text as if every character were 0.6 em wide, wrapping greedily at spaces.
@MainActor
final class FakeTextMeasurer: TextMeasurer {
    private(set) var calls = 0
    
    func lineHeight(for font: FontSpec) -> Double {
        1.2
    }
    
    func invalidate() {}
    
    func measure(_ text: String, font: ResolvedFont, tracking: Double, lineSpacing: Double, width: Double) -> TextMeasurement {
        calls += 1
        let character = font.size * 0.6 + tracking
        let words = text.split(separator: " ").map { Double($0.count) * character }
        var lines = 1
        var current = 0.0
        
        for word in words {
            let next = current == 0 ? word : current + character + word
            
            if next > width && current > 0 {
                lines += 1
                current = word
            } else {
                current = next
            }
        }
        
        let lineHeight = font.size * 1.2
        return TextMeasurement(
            size: CGSize(width: min(width, words.reduce(0, +)), height: Double(lines) * lineHeight + Double(lines - 1) * lineSpacing),
            lineCount: lines
        )
    }
}

enum TestImages {
    /// An opaque image of one color, at a size.
    static func solid(width: Int, height: Int, red: CGFloat = 0.2, green: CGFloat = 0.5, blue: CGFloat = 0.8) -> CGImage {
        draw(width: width, height: height) { context in
            context.setFillColor(CGColor(srgbRed: red, green: green, blue: blue, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        }
    }
    
    /// A fake app screen: a colored background with a few bars, so snapshots show it's clipped and placed.
    static func screen(width: Int, height: Int) -> CGImage {
        draw(width: width, height: height) { context in
            context.setFillColor(CGColor(srgbRed: 0.16, green: 0.42, blue: 0.3, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
            context.setFillColor(CGColor(srgbRed: 0.95, green: 0.9, blue: 0.75, alpha: 1))
            
            for row in 0..<6 {
                let y = height - (row + 2) * height / 9
                context.fill(CGRect(x: width / 12, y: y, width: width * 10 / 12, height: height / 20))
            }
        }
    }
    
    /// The synthetic bezel: an opaque rounded body with a transparent rounded screen, an island inside the screen,
    /// and a transparent margin around the body.
    static let bezelSize = (width: 600, height: 1200)
    static let bezelScreen = PixelRect(x: 60, y: 60, width: 480, height: 1080)
    
    static func bezel() -> CGImage {
        let size = bezelSize
        let screen = bezelScreen
        
        return draw(width: size.width, height: size.height) { context in
            // Core Graphics' origin is the bottom left, so rectangles are flipped from the top-left PixelRects.
            let body = CGRect(x: 20, y: 20, width: size.width - 40, height: size.height - 40)
            context.addPath(CGPath(roundedRect: body, cornerWidth: 80, cornerHeight: 80, transform: nil))
            context.setFillColor(CGColor(srgbRed: 0.1, green: 0.1, blue: 0.12, alpha: 1))
            context.fillPath()
            
            let flipped = CGRect(x: screen.x, y: size.height - screen.y - screen.height, width: screen.width, height: screen.height)
            context.setBlendMode(.clear)
            context.addPath(CGPath(roundedRect: flipped, cornerWidth: 50, cornerHeight: 50, transform: nil))
            context.fillPath()
            
            context.setBlendMode(.normal)
            context.setFillColor(CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1))
            let island = CGRect(x: size.width / 2 - 70, y: size.height - screen.y - 50, width: 140, height: 36)
            context.addPath(CGPath(roundedRect: island, cornerWidth: 18, cornerHeight: 18, transform: nil))
            context.fillPath()
        }
    }
    
    static func draw(width: Int, height: Int, _ body: (CGContext) -> Void) -> CGImage {
        let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        body(context)
        return context.makeImage()!
    }
    
    /// RGBA of a pixel, with (0, 0) at the top left.
    static func pixel(_ image: CGImage, x: Int, y: Int) -> [UInt8] {
        var pixel = [UInt8](repeating: 0, count: 4)
        pixel.withUnsafeMutableBytes { buffer in
            let context = CGContext(
                data: buffer.baseAddress,
                width: 1,
                height: 1,
                bitsPerComponent: 8,
                bytesPerRow: 4,
                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )!
            context.draw(image, in: CGRect(x: -x, y: y - image.height + 1, width: image.width, height: image.height))
        }
        return pixel
    }
}

extension DeviceTable {
    static func target(_ id: String) -> DeviceTarget {
        DeviceTable.standard.target(id: id)!
    }
}

enum TestResources {
    static func url(_ name: String) -> URL {
        Bundle.module.url(forResource: "Resources/\(name)", withExtension: nil)!
    }
    
    static func data(_ name: String) -> Data {
        try! Data(contentsOf: url(name))
    }
}
