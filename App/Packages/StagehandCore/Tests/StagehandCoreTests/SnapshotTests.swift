import AppKit
import CoreGraphics
import Foundation
import SnapshotTesting
@testable import StagehandCore
import StagehandModel
import Testing

/// Renders the fixture project at a small scale. References are recorded on macOS 27, and the suite is skipped elsewhere.
@MainActor
@Suite(.enabled(if: ProcessInfo.processInfo.operatingSystemVersion.majorVersion == 27, "Snapshots are recorded on macOS 27"))
struct SnapshotTests {
    private let project = Project.fixture()
    private let scale = 0.2
    
    private var bezel: BezelInfo {
        BezelInfo(
            id: "test-phone",
            name: "Synthetic",
            deviceClass: .phone,
            model: "Synthetic",
            color: "Black",
            imageWidth: TestImages.bezelSize.width,
            imageHeight: TestImages.bezelSize.height,
            screenRect: TestImages.bezelScreen
        )
    }
    
    private func image(slide index: Int, target: String, withBezel: Bool, in project: Project? = nil) throws -> NSImage {
        let project = project ?? self.project
        let target = DeviceTable.target(target)
        let slide = project.slides(in: project.mainLineup)[index]
        let address = CaptureAddress(key: slide.captureKey[target.deviceClass], deviceClass: target.deviceClass, locale: "en-US")
        let size = target.exportSize
        let catalog = CaptureCatalog(entries: [address: .init(ref: .capture(address, revision: 1), pixelWidth: size.width, pixelHeight: size.height)])
        let bezels = withBezel ? BezelCatalog(bezels: [bezel.id: bezel], defaults: [.phone: bezel.id]) : .empty
        
        let scene = Resolver.resolve(ResolveRequest(
            slide: slide,
            style: project.style,
            target: target,
            locale: "en-US",
            sourceLocale: "en-US",
            captures: catalog,
            bezels: bezels
        ))
        
        let bezelImage = TestImages.bezel()
        let images = SceneImages([
            .capture(address, revision: 1): TestImages.screen(width: size.width, height: size.height),
            bezel.imageRef: bezelImage,
            bezel.maskRef: try BezelDetector.detect(in: bezelImage).mask,
        ])
        
        let rendered = try #require(SceneRenderer.render(scene, images: images, scale: scale))
        return NSImage(cgImage: rendered, size: NSSize(width: rendered.width, height: rendered.height))
    }
    
    @Test func iPhoneStraight() throws {
        assertSnapshot(of: try image(slide: 0, target: "iphone-dynamic-island-large", withBezel: true), as: .image(precision: 0.98))
    }
    
    @Test func iPhoneTiltedRunningOffTheEdge() throws {
        assertSnapshot(of: try image(slide: 1, target: "iphone-dynamic-island-large", withBezel: true), as: .image(precision: 0.98))
    }
    
    @Test func iPadStraightWithAMissingBezel() throws {
        assertSnapshot(of: try image(slide: 0, target: "ipad-13", withBezel: false), as: .image(precision: 0.98))
    }
    
    @Test func iPadTilted() throws {
        var project = project
        project.slides[project.slideOrder[1]]?.template = Varying(.tilted)
        assertSnapshot(of: try image(slide: 1, target: "ipad-13", withBezel: false, in: project), as: .image(precision: 0.98))
    }
}
