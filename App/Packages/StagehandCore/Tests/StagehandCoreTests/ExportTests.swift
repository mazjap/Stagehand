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
