import Foundation
@testable import StagehandCore
import StagehandModel
import Testing

@Suite struct CaptureImporterTests {
    private let phonePNG = TestImages.solid(width: 1320, height: 2868).pngData()!
    
    @Test func aDroppedImageIsClassifiedBySize() throws {
        let result = CaptureImporter.importImage(phonePNG, fileName: "Read the Land.png", destination: .sheet, locale: "en-US", existing: CaptureIndex(), now: .sampleDate)
        let imported = try result.get()
        
        #expect(imported.record.address == CaptureAddress(key: "read-the-land", deviceClass: .phone, locale: "en-US"))
        #expect(imported.record.targetID == "iphone-dynamic-island-large")
        #expect(imported.record.revision == 1)
    }
    
    @Test func anImageOfUnknownSizeIsRefused() {
        let odd = TestImages.solid(width: 1000, height: 1000).pngData()!
        let result = CaptureImporter.importImage(odd, fileName: "odd.png", destination: .sheet, locale: "en-US", existing: CaptureIndex(), now: .sampleDate)
        #expect(throws: CaptureImportError.unknownSize("odd.png", width: 1000, height: 1000)) { try result.get() }
    }
    
    @Test func aDropOnACellTakesItsKey() throws {
        let result = CaptureImporter.importImage(phonePNG, fileName: "Screenshot 1.png", destination: .cell(key: "mark-the-way", deviceClass: .phone), locale: "en-US", existing: CaptureIndex(), now: .sampleDate)
        #expect(try result.get().record.address.key == "mark-the-way")
    }
    
    @Test func aDropOnTheWrongClassIsRefused() {
        let result = CaptureImporter.importImage(phonePNG, fileName: "a.png", destination: .cell(key: "x", deviceClass: .pad), locale: "en-US", existing: CaptureIndex(), now: .sampleDate)
        #expect(throws: CaptureImportError.wrongClass("a.png", expected: .pad, found: .phone)) { try result.get() }
    }
    
    @Test func replacingACaptureBumpsItsRevision() throws {
        let first = try CaptureImporter.importImage(phonePNG, fileName: "a.png", destination: .sheet, locale: "en-US", existing: CaptureIndex(), now: .sampleDate).get()
        let index = CaptureIndex(records: [first.record.address: first.record])
        let second = try CaptureImporter.importImage(phonePNG, fileName: "a.png", destination: .sheet, locale: "en-US", existing: index, now: .sampleDate).get()
        #expect(second.record.revision == 2)
    }
}
