import CoreGraphics
import Foundation

/// Chooses which screen's screenshot is the capture.
public enum DisplayChooser {
    /// The index of the largest screenshot that isn't blank, or of the largest one when every screenshot is blank.
    ///
    /// `XCUIScreen.screens` lists both of a Duo's displays, and the inner one is black while folded, so the
    /// largest screen alone isn't enough. `XCUIScreen.main` is the cover display even when open, so it isn't either.
    public static func choose(_ screenshots: [CGImage]) -> Int? {
        guard !screenshots.isEmpty else {
            return nil
        }
        
        let indexed = Array(screenshots.enumerated())
        let candidates = indexed.filter { !$0.element.isBlank() }
        let pool = candidates.isEmpty ? indexed : candidates
        
        return pool.max { area(of: $0.element) < area(of: $1.element) }?.offset
    }
    
    private static func area(of image: CGImage) -> Int {
        image.width * image.height
    }
}
