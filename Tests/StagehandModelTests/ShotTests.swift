import Foundation
import StagehandModel
import Testing

@Suite struct ShotTests {
    private let shot = Shot(
        captureID: UUID(uuidString: "6F9A1B52-1D7C-4B0E-9E43-2F1A7C0B3D11")!,
        name: "read-the-land",
        scene: #"{"feature":"map"}"#,
        deviceClass: .duoInner,
        targetID: "iphone-duo-inner",
        pixelWidth: 2007,
        pixelHeight: 2853,
        locale: "en-US",
        runID: "run-1",
        simulatorModel: "iPhone19,4",
        simulatorRuntime: "27.1",
        quirksApplied: ["duo-inner-rotated-180"],
        capturedAt: Date(timeIntervalSince1970: 1_793_102_400)
    )
    
    @Test func roundTripsThroughJSON() throws {
        let data = try Shot.makeEncoder().encode(shot)
        let decoded = try Shot.makeDecoder().decode(Shot.self, from: data)
        #expect(decoded == shot)
    }
    
    @Test func decodesSchemaVersionOne() throws {
        let json = """
        {
          "capturedAt" : "2026-10-27T12:00:00Z",
          "captureID" : "6F9A1B52-1D7C-4B0E-9E43-2F1A7C0B3D11",
          "deviceClass" : "phone",
          "name" : "read-the-land",
          "pixelHeight" : 2868,
          "pixelWidth" : 1320,
          "quirksApplied" : [],
          "schemaVersion" : 1,
          "targetID" : "iphone-dynamic-island-large"
        }
        """
        let decoded = try Shot.makeDecoder().decode(Shot.self, from: Data(json.utf8))
        #expect(decoded.schemaVersion == 1)
        #expect(decoded.deviceClass == .phone)
        #expect(decoded.locale == nil)
    }
    
    @Test func attachmentNamesRoundTrip() throws {
        let image = ShotAttachment.imageName(captureID: shot.captureID, name: shot.name)
        let meta = ShotAttachment.metadataName(captureID: shot.captureID)
        
        #expect(image == "stagehand.6F9A1B52-1D7C-4B0E-9E43-2F1A7C0B3D11.read-the-land")
        #expect(ShotAttachment.parse(image)?.suffix == "read-the-land")
        #expect(ShotAttachment.parse(meta)?.suffix == "meta")
        #expect(ShotAttachment.parse(meta)?.captureID == shot.captureID)
        #expect(ShotAttachment.parse("Screenshot 1") == nil)
    }
}
