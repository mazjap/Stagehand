import CoreGraphics
import SwiftUI

extension Image {
    /// A decoded image drawn at its pixel size.
    init(pixels image: CGImage) {
        self.init(decorative: image, scale: 1)
    }
}
