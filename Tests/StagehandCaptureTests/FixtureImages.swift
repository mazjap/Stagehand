import CoreGraphics
import Foundation

/// Images drawn in code for the capture logic's tests.
enum FixtureImages {
    /// One uniform color.
    static func solid(width: Int, height: Int, gray: CGFloat) -> CGImage {
        draw(width: width, height: height) { context in
            context.setFillColor(CGColor(gray: gray, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        }
    }
    
    /// A nearly black UI with a few dim elements, which must not count as blank.
    static func darkUI(width: Int, height: Int) -> CGImage {
        draw(width: width, height: height) { context in
            context.setFillColor(CGColor(gray: 0.04, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
            context.setFillColor(CGColor(gray: 0.22, alpha: 1))
            context.fill(CGRect(x: width / 10, y: height / 2, width: width * 8 / 10, height: height / 12))
            context.fill(CGRect(x: width / 10, y: height / 4, width: width / 3, height: height / 20))
        }
    }
    
    /// A red marker at the top of the image (in image coordinates, the first rows), so a rotation can be seen.
    static func markedTop(width: Int, height: Int) -> CGImage {
        draw(width: width, height: height) { context in
            context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
            context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
            // Core Graphics' origin is the bottom left, so the top rows are at the largest y.
            context.fill(CGRect(x: 0, y: height - height / 10, width: width, height: height / 10))
        }
    }
    
    /// The RGBA of one pixel, with (0, 0) at the top left.
    static func pixel(_ image: CGImage, x: Int, y: Int) -> [UInt8] {
        var pixel = [UInt8](repeating: 0, count: 4)
        pixel.withUnsafeMutableBytes { buffer in
            let context = CGContext(
                data: buffer.baseAddress,
                width: 1,
                height: 1,
                bitsPerComponent: 8,
                bytesPerRow: 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )!
            context.draw(image, in: CGRect(x: -x, y: y - image.height + 1, width: image.width, height: image.height))
        }
        return pixel
    }
    
    private static func draw(width: Int, height: Int, _ body: (CGContext) -> Void) -> CGImage {
        let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        body(context)
        return context.makeImage()!
    }
}
