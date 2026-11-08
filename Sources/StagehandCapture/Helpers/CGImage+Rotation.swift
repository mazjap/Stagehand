import CoreGraphics
import Foundation
import StagehandModel

extension CGImage {
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
    
    /// This image with a quirk's fix applied.
    public func applying(_ fix: Quirk.Fix) -> CGImage? {
        switch fix {
        case .rotate180: rotated180()
        }
    }
}
