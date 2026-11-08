import CoreGraphics
import Dependencies
import DependenciesTestSupport
import Foundation
@testable import StagehandCore
import StagehandModel
import Testing

/// Bezels from Apple Design Resources: the page's links, downloading and installing, pinning, and newer bezels.
@MainActor
@Suite(.dependencies) struct BezelSourceTests {
    private let iPhone = AppleBezelProduct(
        name: "iPhone 18",
        url: URL(string: "https://devimages-cdn.apple.com/design/resources/download/Bezel-iPhone-18.dmg")!,
        deviceClasses: [.phone]
    )
    
    private func bezel(_ id: BezelID, model: String, color: String = "Black", importedAt: Date? = nil, screen: PixelRect = TestImages.bezelScreen) -> BezelInfo {
        BezelInfo(id: id, name: id, deviceClass: .phone, model: model, color: color, imageWidth: 600, imageHeight: 1200, screenRect: screen, importedAt: importedAt)
    }
    
    // MARK: - The Page
    
    @Test func everyBezelLinkIsListedOnceWithItsClasses() {
        let products = BezelSource.products(fromPage: String(decoding: TestResources.data("bezels/design-resources.html"), as: UTF8.self))
        
        #expect(products.map(\.name) == ["Apple TV", "Apple Watch Ultra 4", "iMac M4", "iPad Pro (M5)", "iPhone Duo", "iPhone 18", "MacBook Pro M5"])
        #expect(products.map(\.deviceClasses) == [[], [.watch], [.mac], [.pad], [.duoOuter, .duoInner], [.phone], [.mac]])
        #expect(products[3].url.absoluteString == "https://devimages-cdn.apple.com/design/resources/download/Bezel-iPad-Pro-(M5).dmg")
    }
    
    // MARK: - Installing
    
    /// Regression test: the install imported every PNG on the disk image, and Apple's carry their Finder window's
    /// background in `.DropDMGBackground/`. A portrait one with a clear middle would have become a bezel.
    @Test func installingMountsImportsEveryUsableImageAndDetaches() async throws {
        let volume = "/Volumes/Bezel-iPhone-18"
        let images = [
            URL(filePath: "\(volume)/.DropDMGBackground/Bezel-iPhone18@2x.png"): TestImages.bezel().pngData()!,
            URL(filePath: "\(volume)/iPhone 18 Pro Max - Cosmic Orange - Portrait.png"): TestImages.bezel().pngData()!,
            URL(filePath: "\(volume)/iPhone 18 Pro Max - Cosmic Orange - Landscape.png"): TestImages.solid(width: 1200, height: 600).pngData()!,
            URL(filePath: "\(volume)/Shadow.png"): TestImages.solid(width: 100, height: 200).pngData()!,
        ]
        let fileManager = InMemoryFileManager(files: images)
        let listing = images.keys.map { $0.path(percentEncoded: false) }.joined(separator: "\n")
        
        let license = try PropertyListSerialization.data(fromPropertyList: ["TEXT": [["Name": "English", "Data": "LICENSE AGREEMENT FOR APPLE DESIGN RESOURCES".data(using: .macOSRoman)!]]], format: .xml, options: 0)
        let attach = try PropertyListSerialization.data(fromPropertyList: ["system-entities": [["dev-entry": "/dev/disk9"], ["mount-point": volume]]], format: .xml, options: 0)
        let processes = FakeProcessRunner { command in
            switch command.arguments.first {
            case "udifderez": ProcessOutput(stdout: String(decoding: license, as: UTF8.self))
            case "-c": ProcessOutput(stdout: "Agree Y/N?\n" + String(decoding: attach, as: UTF8.self))
            case volume: ProcessOutput(stdout: listing)
            default: ProcessOutput()
            }
        }
        
        let library = BezelLibrary(libraryURL: URL(filePath: "/Library"), fileManager: fileManager)
        let downloader = BezelDownloader(
            library: library,
            downloads: FakeBezelDownloads(versions: [iPhone.url: "\"v1\""]),
            processes: processes,
            fileManager: fileManager,
            workFolder: URL(filePath: "/Caches")
        )
        
        let downloaded = try await downloader.download(iPhone) { _ in }
        #expect(downloaded.license == "LICENSE AGREEMENT FOR APPLE DESIGN RESOURCES")
        #expect(downloaded.file == URL(filePath: "/Caches/Bezel-iPhone-18.dmg"))
        
        let imported = try await downloader.install(downloaded, now: .sampleDate)
        
        #expect(imported.map { $0.model } == ["iPhone 18 Pro Max"])
        #expect(imported.first?.color == "Cosmic Orange")
        #expect(imported.first?.source == BezelSourceInfo(url: iPhone.url, product: "iPhone 18", version: "\"v1\""))
        #expect(library.installedVersions() == [iPhone.url: "\"v1\""])
        
        let shell = try #require(processes.commands.first { $0.executable == "/bin/sh" })
        #expect(shell.arguments == ["-c", "yes | /usr/bin/hdiutil attach -readonly -nobrowse -noautoopen -plist \"$1\"", "sh", "/Caches/Bezel-iPhone-18.dmg"])
        #expect(processes.commands.last?.arguments == ["detach", volume, "-quiet"])
    }
    
    @Test func aBezelIsNeverOverwrittenByAnUpdatedFile() throws {
        let fileManager = InMemoryFileManager()
        let library = BezelLibrary(libraryURL: URL(filePath: "/Library"), fileManager: fileManager)
        let original = try library.importBezel(data: TestImages.bezel().pngData()!, name: "iPhone 18", deviceClass: .phone, model: "iPhone 18", color: "Black")
        let again = try library.importBezel(data: TestImages.bezel().pngData()!, name: "iPhone 18", deviceClass: .phone, model: "iPhone 18", color: "Black")
        let updatedImage = TestImages.draw(width: 600, height: 1200) { context in
            context.draw(TestImages.bezel(), in: CGRect(x: 0, y: 0, width: 600, height: 1200))
            context.setFillColor(CGColor(gray: 0.5, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: 10, height: 10))
        }
        let updated = try library.importBezel(data: updatedImage.pngData()!, name: "iPhone 18", deviceClass: .phone, model: "iPhone 18", color: "Black")
        
        #expect(again == original)
        #expect(updated.id != original.id)
        #expect(updated.id.hasPrefix(original.id + "-"))
        #expect(library.load().bezels.count == 2)
    }
    
    // MARK: - Pinning and Newer Bezels
    
    @Test func aNewerGenerationOrAnUpdatedFileIsNewer() {
        let old = bezel("a", model: "iPhone 18 Pro Max", importedAt: .sampleDate)
        let updated = bezel("b", model: "iPhone 18 Pro Max", importedAt: .sampleDate.addingTimeInterval(60))
        let next = bezel("c", model: "iPhone 19 Pro Max", color: "Silver")
        let otherSize = bezel("d", model: "iPhone 20")
        let catalog = BezelCatalog(bezels: [old.id: old, updated.id: updated, next.id: next, otherSize.id: otherSize])
        
        #expect(catalog.newerBezel(than: "a")?.id == "c")
        #expect(catalog.newerBezel(than: "b")?.id == "c")
        #expect(catalog.newerBezel(than: "c") == nil)
        #expect(BezelCatalog(bezels: [old.id: old, updated.id: updated]).newerBezel(than: "a")?.id == "b")
    }
    
    @Test func anUpdateWarnsWhenTheScreenOrFrameChanges() {
        let old = bezel("a", model: "iPhone 18 Pro Max")
        var same = bezel("b", model: "iPhone 19 Pro Max")
        same.color = "Silver"
        let taller = bezel("c", model: "iPhone 19 Pro Max", screen: PixelRect(x: 60, y: 60, width: 480, height: 1120))
        var widerFrame = bezel("d", model: "iPhone 19 Pro Max", screen: PixelRect(x: 30, y: 60, width: 456, height: 1026))
        widerFrame.imageWidth = 516
        
        #expect(old.changes(to: same).isEmpty)
        #expect(old.changes(to: taller) == [.screenShape])
        #expect(old.changes(to: widerFrame) == [.frameSize])
    }
    
    @Test func theBestBezelMatchesTheScreensShapeThenIsTheNewest() {
        let wide = bezel("wide", model: "iPhone 19", screen: PixelRect(x: 0, y: 0, width: 500, height: 900))
        let old = bezel("old", model: "iPhone 17 Pro Max")
        let new = bezel("new", model: "iPhone 18 Pro Max")
        let catalog = BezelCatalog(bezels: [wide.id: wide, old.id: old, new.id: new])
        
        #expect(catalog.bestBezel(for: .phone, aspectRatio: 1320.0 / 2868.0)?.id == "new")
        #expect(catalog.bestBezel(for: .phone, aspectRatio: 500.0 / 900.0)?.id == "wide")
        #expect(catalog.bestBezel(for: .pad, aspectRatio: nil) == nil)
    }
    
    /// Regression test: of two bezels from the same disk image, both within 3% of the target's shape, the one whose ID
    /// sorted first won, so the 6.9-inch iPhone drew in an iPhone 18 Pro rather than the Pro Max that matches it.
    @Test func theClosestShapeWinsWithinAGeneration() {
        let pro = bezel("phone-iphone-18-pro-black-portrait", model: "iPhone 18 Pro", screen: PixelRect(x: 72, y: 69, width: 1206, height: 2622))
        let proMax = bezel("phone-iphone-18-pro-max-black-portrait", model: "iPhone 18 Pro Max", screen: PixelRect(x: 75, y: 66, width: 1320, height: 2868))
        let catalog = BezelCatalog(bezels: [pro.id: pro, proMax.id: proMax])
        
        #expect(catalog.bestBezel(for: .phone, aspectRatio: 1320.0 / 2868.0)?.id == proMax.id)
        #expect(catalog.bestBezel(for: .phone, aspectRatio: 1206.0 / 2622.0)?.id == pro.id)
    }
    
    @Test func aNewTemplatePinsAndEmbedsTheBestBezel() async throws {
        let fileManager = InMemoryFileManager()
        let library = BezelLibrary(libraryURL: URL(filePath: "/Library"), fileManager: fileManager)
        let installed = try library.importBezel(data: TestImages.bezel().pngData()!, name: "iPhone 18 Pro Max", deviceClass: .phone, model: "iPhone 18 Pro Max", color: "Black")
        
        try await withDependencies {
            $0.fileManager = fileManager
            $0.ubiquity = FixedUbiquity(url: URL(filePath: "/Library"))
        } operation: {
            let coordinator = ProjectCoordinator(document: ProjectDocument(contents: ProjectContents(project: .fixture())), measurer: FakeTextMeasurer())
            await coordinator.start()
            coordinator.handle(.addTemplate(duplicating: nil))
            
            let template = try #require(coordinator.currentTemplate)
            #expect(template.layouts[.phone]?.device.bezel == .pinned(installed.id))
            #expect(template.layouts[.pad]?.device.bezel == .matchTarget)
            #expect(coordinator.document.contents.bezels[installed.id]?.info == installed)
            
            // A newer bezel is offered, but the template keeps its own.
            _ = try library.importBezel(data: TestImages.bezel().pngData()!, name: "iPhone 19 Pro Max", deviceClass: .phone, model: "iPhone 19 Pro Max", color: "Black")
            await coordinator.loadBezels()
            
            #expect(coordinator.currentTemplate?.layouts[.phone]?.device.bezel == .pinned(installed.id))
            #expect(coordinator.issues.contains { $0.kind == .newerBezel(installed.id, newer: "phone-iphone-19-pro-max") })
        }
    }
    
    @Test func aNewProjectPinsItsTemplatesLibraryDefaults() throws {
        let fileManager = InMemoryFileManager()
        let library = BezelLibrary(libraryURL: URL(filePath: "/Library"), fileManager: fileManager)
        let installed = try library.importBezel(data: TestImages.bezel().pngData()!, name: "iPhone 18 Pro Max", deviceClass: .phone, model: "iPhone 18 Pro Max", color: "Black")
        var contents = ProjectContents(project: .empty(devices: [.phone, .watch], style: StarterTemplateSet.darkGlow.style()))
        
        BezelPinning.pinLibraryDefaults(in: &contents, catalog: library.load()) { try? library.imageData(for: $0) }
        
        let straight = try #require(contents.project.style.template(.straight))
        #expect(straight.layouts[.phone]?.device.bezel == .pinned(installed.id))
        #expect(straight.layouts[.pad]?.device.bezel == .matchTarget)
        #expect(straight.layouts[.watch]?.device.bezel == BezelChoice.none)
        #expect(contents.bezels.keys.sorted() == [installed.id])
    }
    
    /// Regression test: Library Default drew a plain frame once a class had several bezels and none was chosen as its
    /// default, which is what downloading one of Apple's disk images leaves.
    @Test func libraryDefaultWithoutADefaultDrawsTheBestMatch() {
        let pro = bezel("pro", model: "iPhone 18 Pro Max")
        let wide = bezel("wide", model: "iPhone 18", screen: PixelRect(x: 0, y: 0, width: 500, height: 900))
        let catalog = BezelCatalog(bezels: [pro.id: pro, wide.id: wide])
        
        #expect(catalog.bezel(for: .matchTarget, deviceClass: .phone, aspectRatio: 1320.0 / 2868.0)?.id == "pro")
        #expect(catalog.bezel(for: .matchTarget, deviceClass: .pad, aspectRatio: 0.75) == nil)
    }
    
    /// A project opens with the bezels it pins even when the library doesn't have them.
    @Test func aProjectDrawsItsEmbeddedBezelWithoutTheLibrary() throws {
        var project = Project.fixture()
        let info = bezel("phone-embedded", model: "iPhone 18 Pro Max")
        project.style.updateTemplate(.straight) { $0.layouts[.phone]?.device.bezel = .pinned(info.id) }
        let contents = ProjectContents(project: project, bezels: [info.id: EmbeddedBezel(info: info, png: TestImages.bezel().pngData()!)])
        
        let reopened = try ProjectPackage.read(ProjectPackage.write(contents, previous: nil))
        #expect(reopened.bezels == contents.bezels)
        
        let coordinator = ProjectCoordinator(document: ProjectDocument(contents: reopened), measurer: FakeTextMeasurer())
        let set = coordinator.project.mainLineup
        let scene = try #require(coordinator.scene(for: CellID(setID: set.id, slideID: set.slideIDs[0], targetID: "iphone-dynamic-island-large")))
        
        #expect(scene.device?.frame == .bezel)
        #expect(coordinator.images(for: scene)[scene.device?.bezel] != nil)
        #expect(coordinator.images(for: scene)[scene.device?.mask] != nil)
    }
}
