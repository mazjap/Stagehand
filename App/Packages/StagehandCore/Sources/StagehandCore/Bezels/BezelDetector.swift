import CoreGraphics
import Foundation

public enum BezelImportError: Error, Equatable, LocalizedError {
    case undecodable(String)
    case centerNotTransparent(String)
    case screenTooSmall(String)
    case writeFailed(String)
    
    public var errorDescription: String? {
        switch self {
        case let .undecodable(name): "\(name) isn't a PNG Stagehand can read."
        case let .centerNotTransparent(name): "\(name)'s center isn't transparent, so its screen can't be found."
        case let .screenTooSmall(name): "\(name)'s transparent center is too small to be a screen."
        case let .writeFailed(reason): "The bezel couldn't be saved: \(reason)"
        }
    }
}

/// Finds a bezel's screen by flood-filling the transparent region from the center pixel.
public enum BezelDetector {
    public struct Detection: @unchecked Sendable {
        /// The filled region's bounding box.
        public var screenRect: PixelRect
        
        /// Opaque where the region was filled, transparent elsewhere, at the bezel's size.
        public var mask: CGImage
        
        /// How many pixels were filled.
        public var filledCount: Int
    }
    
    public static func detect(in image: CGImage, name: String = "The bezel", alphaThreshold: UInt8 = 128) throws(BezelImportError) -> Detection {
        let width = image.width
        let height = image.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else {
                return false
            }
            
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        
        guard drawn else {
            throw .undecodable(name)
        }
        
        // NOTE: - A bitmap context's first row in memory is the image's top row.
        func alpha(_ x: Int, _ y: Int) -> UInt8 {
            pixels[(y * width + x) * 4 + 3]
        }
        
        let startX = width / 2
        let startY = height / 2
        
        guard alpha(startX, startY) < alphaThreshold else {
            throw .centerNotTransparent(name)
        }
        
        var filled = [Bool](repeating: false, count: width * height)
        var stack = [(startX, startY)]
        var minX = startX, maxX = startX, minY = startY, maxY = startY
        var count = 0
        filled[startY * width + startX] = true
        
        while let (x, y) = stack.popLast() {
            count += 1
            minX = min(minX, x)
            maxX = max(maxX, x)
            minY = min(minY, y)
            maxY = max(maxY, y)
            
            for (nx, ny) in [(x - 1, y), (x + 1, y), (x, y - 1), (x, y + 1)] {
                guard nx >= 0, ny >= 0, nx < width, ny < height else {
                    continue
                }
                
                let index = ny * width + nx
                
                if !filled[index] && alpha(nx, ny) < alphaThreshold {
                    filled[index] = true
                    stack.append((nx, ny))
                }
            }
        }
        
        let rect = PixelRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
        
        guard rect.width >= width / 4, rect.height >= height / 4 else {
            throw .screenTooSmall(name)
        }
        
        // The region touching the image's edge means the fill leaked out of the screen.
        if minX == 0 || minY == 0 || maxX == width - 1 || maxY == height - 1 {
            throw .screenTooSmall(name)
        }
        
        var maskPixels = [UInt8](repeating: 0, count: width * height * 4)
        
        for index in 0..<(width * height) where filled[index] {
            maskPixels[index * 4] = 255
            maskPixels[index * 4 + 1] = 255
            maskPixels[index * 4 + 2] = 255
            maskPixels[index * 4 + 3] = 255
        }
        
        let mask = maskPixels.withUnsafeMutableBytes { buffer -> CGImage? in
            CGContext(
                data: buffer.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )?.makeImage()
        }
        
        guard let mask else {
            throw .undecodable(name)
        }
        
        return Detection(screenRect: rect, mask: mask, filledCount: count)
    }
}
