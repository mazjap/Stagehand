import CoreGraphics
import Foundation
import StagehandModel

/// A capture after choosing its display, classifying it and applying quirks.
public struct ProcessedCapture: @unchecked Sendable {
    public var image: CGImage
    public var png: Data
    public var shot: Shot
    
    /// Set when the runner expected another device class. The test fails with this message.
    public var expectationFailure: String?
    
    /// The attachment name of the image: `stagehand.<capture ID>.<name>`.
    public var imageAttachmentName: String {
        ShotAttachment.imageName(captureID: shot.captureID, name: shot.name)
    }
    
    /// The attachment name of the metadata: `stagehand.<capture ID>.meta`.
    public var metadataAttachmentName: String {
        ShotAttachment.metadataName(captureID: shot.captureID)
    }
}

public enum CaptureError: Error, Equatable, CustomStringConvertible {
    case noScreens
    case undecodableScreenshot
    case encodingFailed
    case quirkFailed(String)
    case expectation(String)
    case notReady(String)
    
    public var description: String {
        switch self {
        case .noScreens: "stagehand: there was no screen to capture"
        case .undecodableScreenshot: "stagehand: a screenshot couldn't be decoded"
        case .encodingFailed: "stagehand: the capture couldn't be encoded as PNG"
        case let .quirkFailed(id): "stagehand: the \(id) quirk couldn't be applied"
        case let .expectation(message): message
        case let .notReady(message): "stagehand: \(message)"
        }
    }
}

/// The capture logic between taking screenshots and writing outputs, as plain functions on values and `CGImage`s.
public enum CapturePipeline {
    /// Chooses the displayed screen, classifies it, applies quirks, checks the expectation and builds its metadata.
    public static func process(
        screenshots: [CGImage],
        name: String,
        scene: String?,
        environment: CaptureEnvironment,
        table: DeviceTable = .standard,
        quirks: [Quirk] = Quirk.all,
        captureID: UUID = UUID(),
        capturedAt: Date = Date()
    ) throws -> ProcessedCapture {
        guard let index = DisplayChooser.choose(screenshots) else {
            throw CaptureError.noScreens
        }
        
        var image = screenshots[index]
        let classification = table.classify(width: image.width, height: image.height)
        let applicable = Quirk.applicable(
            model: environment.simulatorModel,
            runtime: environment.simulatorRuntime,
            deviceClass: classification?.deviceClass,
            in: quirks
        )
        
        for quirk in applicable {
            guard let fixed = image.applying(quirk.fix) else {
                throw CaptureError.quirkFailed(quirk.id)
            }
            
            image = fixed
        }
        
        guard let png = image.pngData() else {
            throw CaptureError.encodingFailed
        }
        
        let shot = Shot(
            captureID: captureID,
            name: name,
            scene: scene,
            deviceClass: classification?.deviceClass,
            targetID: classification?.target.id,
            pixelWidth: image.width,
            pixelHeight: image.height,
            locale: environment.locale,
            runID: environment.runID,
            simulatorModel: environment.simulatorModel,
            simulatorRuntime: environment.simulatorRuntime,
            quirksApplied: applicable.map(\.id),
            capturedAt: capturedAt
        )
        
        let failure = Expectation.check(
            expected: environment.expectedClass,
            actual: classification?.deviceClass,
            width: image.width,
            height: image.height
        )
        
        return ProcessedCapture(image: image, png: png, shot: shot, expectationFailure: failure)
    }
}
