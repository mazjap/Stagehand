import CoreGraphics
import Foundation
@testable import StagehandCore
import StagehandModel
import Testing

@Suite struct BezelDetectorTests {
    @Test func theSyntheticBezelsScreenIsFoundWithinAPixel() throws {
        let detection = try BezelDetector.detect(in: TestImages.bezel())
        let expected = TestImages.bezelScreen
        
        #expect(abs(detection.screenRect.x - expected.x) <= 1)
        #expect(abs(detection.screenRect.y - expected.y) <= 1)
        #expect(abs(detection.screenRect.width - expected.width) <= 1)
        #expect(abs(detection.screenRect.height - expected.height) <= 1)
    }
    
    @Test func theMaskMatchesTheScreen() throws {
        let detection = try BezelDetector.detect(in: TestImages.bezel())
        let mask = detection.mask
        
        // Inside the screen, opaque.
        #expect(TestImages.pixel(mask, x: 300, y: 600)[3] == 255)
        
        // The body, the margin and the island are left out.
        #expect(TestImages.pixel(mask, x: 30, y: 600)[3] == 0)
        #expect(TestImages.pixel(mask, x: 5, y: 5)[3] == 0)
        #expect(TestImages.pixel(mask, x: 300, y: 85)[3] == 0)
        
        // The screen's rounded corner is left out too.
        #expect(TestImages.pixel(mask, x: 62, y: 62)[3] == 0)
    }
    
    @Test func anOpaqueCenterIsRefused() {
        #expect(throws: BezelImportError.centerNotTransparent("The bezel")) {
            try BezelDetector.detect(in: TestImages.solid(width: 100, height: 200))
        }
    }
    
    @Test func importingWritesTheImageAndItsJSON() throws {
        let fileManager = InMemoryFileManager()
        let library = BezelLibrary(libraryURL: URL(filePath: "/Library"), fileManager: fileManager)
        let info = try library.importBezel(data: TestImages.bezel().pngData()!, name: "iPhone Test", deviceClass: .phone, model: "Test", color: "Black")
        
        #expect(info.id == "phone-iphone-test")
        #expect(fileManager.fileExists(at: URL(filePath: "/Library/Bezels/phone-iphone-test.png")))
        
        let catalog = library.load()
        #expect(catalog.bezels[info.id] == info)
        #expect(catalog.defaults[.phone] == info.id)
        #expect(library.mask(for: info.id) != nil)
    }
}
