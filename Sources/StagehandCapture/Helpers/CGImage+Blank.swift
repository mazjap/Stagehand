import CoreGraphics
import Foundation

extension CGImage {
    /// Whether this image is one uniform color, judged on a downscaled copy.
    ///
    /// A folded iPhone Duo lists its inner display, which comes back black. A dark UI isn't blank, since its
    /// content still varies on the downscaled copy.
    ///
    /// - Parameter tolerance: The largest difference in any channel, out of 255, that still counts as uniform.
    public func isBlank(sampleSize: Int = 32, tolerance: Int = 3) -> Bool {
        guard let pixels = downscaledPixels(size: sampleSize) else {
            return false
        }
        
        var minimum = [UInt8](repeating: 255, count: 3)
        var maximum = [UInt8](repeating: 0, count: 3)
        
        for index in stride(from: 0, to: pixels.count, by: 4) {
            for channel in 0..<3 {
                let value = pixels[index + channel]
                minimum[channel] = Swift.min(minimum[channel], value)
                maximum[channel] = Swift.max(maximum[channel], value)
            }
        }
        
        return (0..<3).allSatisfy { Int(maximum[$0]) - Int(minimum[$0]) <= tolerance }
    }
    
    /// RGBA8 pixels of a `size` × `size` copy of this image.
    func downscaledPixels(size: Int) -> [UInt8]? {
        var pixels = [UInt8](repeating: 0, count: size * size * 4)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress,
                width: size,
                height: size,
                bitsPerComponent: 8,
                bytesPerRow: size * 4,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else {
                return false
            }
            
            context.interpolationQuality = .medium
            context.draw(self, in: CGRect(x: 0, y: 0, width: size, height: size))
            return true
        }
        
        return drawn ? pixels : nil
    }
}
