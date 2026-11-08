import CoreGraphics
import Foundation
import ImageIO

extension CGImage {
    /// Decodes the first image in PNG (or any ImageIO-readable) data.
    public static func decode(_ data: Data) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            return nil
        }
        
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }
    
    /// This image as PNG data.
    public func pngData() -> Data? {
        let data = NSMutableData()
        
        guard let destination = CGImageDestinationCreateWithData(data as CFMutableData, "public.png" as CFString, 1, nil) else {
            return nil
        }
        
        CGImageDestinationAddImage(destination, self, nil)
        
        guard CGImageDestinationFinalize(destination) else {
            return nil
        }
        
        return data as Data
    }
}
