import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

extension CGImage {
    /// Decodes the first image in PNG (or any ImageIO-readable) data.
    public static func decode(_ data: Data) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            return nil
        }
        
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }
    
    /// The pixel size of an image in data, without decoding it.
    public static func pixelSize(of data: Data) -> (width: Int, height: Int)? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int else {
            return nil
        }
        
        return (width, height)
    }
    
    /// This image as PNG data.
    public func pngData() -> Data? {
        let data = NSMutableData()
        
        guard let destination = CGImageDestinationCreateWithData(data as CFMutableData, UTType.png.identifier as CFString, 1, nil) else {
            return nil
        }
        
        CGImageDestinationAddImage(destination, self, nil)
        return CGImageDestinationFinalize(destination) ? data as Data : nil
    }
    
    /// This image drawn onto an opaque sRGB context over a color, so it has no alpha channel.
    ///
    /// App Store Connect rejects images with an alpha channel.
    public func flattened(over background: CGColor = CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1)) -> CGImage? {
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                  data: nil,
                  width: width,
                  height: height,
                  bitsPerComponent: 8,
                  bytesPerRow: 0,
                  space: space,
                  bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
              ) else {
            return nil
        }
        
        let rect = CGRect(x: 0, y: 0, width: width, height: height)
        context.setFillColor(background)
        context.fill(rect)
        context.draw(self, in: rect)
        return context.makeImage()
    }
    
    /// Whether this image stores an alpha channel.
    public var hasAlpha: Bool {
        switch alphaInfo {
        case .none, .noneSkipFirst, .noneSkipLast: false
        default: true
        }
    }
    
    /// This image turned 180°.
    public func rotated180() -> CGImage? {
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }
        
        context.translateBy(x: CGFloat(width), y: CGFloat(height))
        context.rotate(by: .pi)
        context.draw(self, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()
    }
}
