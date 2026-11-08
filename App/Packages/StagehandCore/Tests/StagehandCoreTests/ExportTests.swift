import CoreGraphics
import Foundation
@testable import StagehandCore
import StagehandModel
import Testing

@MainActor
@Suite struct ExportTests {
    @Test func exportsAreTheExactSizeWithNoAlpha() throws {
        let project = Project.fixture()
        let slide = project.slides(in: project.mainLineup)[0]
        
        for targetID in ["iphone-dynamic-island-large", "ipad-13"] {
            let target = DeviceTable.target(targetID)
            let scene = Resolver.resolve(ResolveRequest(slide: slide, style: project.style, target: target, locale: "en-US", sourceLocale: "en-US", captures: CaptureCatalog()))
            let data = try SceneRenderer.exportPNG(scene, images: SceneImages(), name: "test")
            let image = try #require(CGImage.decode(data))
            
            #expect(image.width == target.exportSize.width)
            #expect(image.height == target.exportSize.height)
            #expect(!image.hasAlpha)
        }
    }
    
    /// A capture that isn't the bezel's shape covers the whole screen, cropped rather than letterboxed. A capture within
    /// the size tolerance is one case, and these are far enough off that a gap would be seen.
    @Test(arguments: [(width: 1318, height: 2866), (width: 1000, height: 3000), (width: 1800, height: 2700)])
    func aCaptureThatIsNotExactFillsTheBezelsScreen(size: (width: Int, height: Int)) throws {
        let project = Project.fixture()
        let slide = project.slides(in: project.mainLineup)[0]
        let target = DeviceTable.target("iphone-dynamic-island-large")
        let address = CaptureAddress(key: slide.captureKey[.phone], deviceClass: .phone, locale: "en-US")
        let bezel = BezelInfo(
            id: "test-phone",
            name: "Synthetic",
            deviceClass: .phone,
            model: "Synthetic",
            color: "Black",
            imageWidth: TestImages.bezelSize.width,
            imageHeight: TestImages.bezelSize.height,
            screenRect: TestImages.bezelScreen
        )
        let scene = Resolver.resolve(ResolveRequest(
            slide: slide,
            style: project.style,
            target: target,
            locale: "en-US",
            sourceLocale: "en-US",
            captures: CaptureCatalog(entries: [address: .init(ref: .capture(address, revision: 1), pixelWidth: size.width, pixelHeight: size.height)]),
            bezels: BezelCatalog(bezels: [bezel.id: bezel], defaults: [.phone: bezel.id])
        ))
        let device = try #require(scene.device)
        let bezelImage = TestImages.bezel()
        let rendered = try #require(SceneRenderer.render(scene, images: SceneImages([
            .capture(address, revision: 1): TestImages.solid(width: size.width, height: size.height, red: 0.9, green: 0.1, blue: 0.6),
            bezel.imageRef: bezelImage,
            bezel.maskRef: try BezelDetector.detect(in: bezelImage).mask,
        ]), scale: 1))
        
        let screen = device.screen.offsetBy(dx: device.center.x - device.size.width / 2, dy: device.center.y - device.size.height / 2)
        let inset = 4.0
        let edges = [
            CGPoint(x: screen.minX + inset, y: screen.midY),
            CGPoint(x: screen.maxX - inset, y: screen.midY),
            // A quarter of the way along, to miss the island
            CGPoint(x: screen.minX + screen.width / 4, y: screen.minY + inset),
            CGPoint(x: screen.minX + screen.width / 4, y: screen.maxY - inset),
        ]
        let visible = edges.filter { $0.x >= 0 && $0.y >= 0 && Int($0.x) < rendered.width && Int($0.y) < rendered.height }
        
        #expect(visible.count >= 3, "The layout should keep most of the screen on the canvas")
        
        for point in visible {
            let pixel = TestImages.pixel(rendered, x: Int(point.x), y: Int(point.y))
            #expect(abs(Int(pixel[0]) - 230) < 12 && abs(Int(pixel[1]) - 26) < 12 && abs(Int(pixel[2]) - 153) < 12, "\(point) is \(pixel)")
        }
    }
    
    @Test func exportPathsFollowTheSetOrder() {
        let items = ProjectExporter().items(for: .fixture())
        let paths = items.map(\.relativePath)
        
        #expect(items.count == 6)
        #expect(paths.contains("en-US/iphone-dynamic-island-large/01-read-the-land.png"))
        #expect(paths.contains("en-US/iphone-dynamic-island-large/02-bring-it-along.png"))
        #expect(paths.contains("en-US/ipad-13/03-mark-the-way.png"))
    }
    
    @Test func everyListingLocaleIsExported() {
        var project = Project.fixture()
        project.listingLocales = ["en-US", "de-DE"]
        #expect(ProjectExporter().items(for: project).filter { $0.locale == "de-DE" }.count == 6)
    }
    
    @Test func exportingWritesEachFile() throws {
        let fileManager = InMemoryFileManager()
        let items = ProjectExporter().items(for: .fixture())
        let urls = try ProjectExporter().export(items, to: URL(filePath: "/Exports"), fileManager: fileManager) { _ throws(ExportError) in Data([1]) }
        
        #expect(urls.count == 6)
        #expect(fileManager.fileExists(at: URL(filePath: "/Exports/en-US/ipad-13/01-read-the-land.png")))
    }
}
