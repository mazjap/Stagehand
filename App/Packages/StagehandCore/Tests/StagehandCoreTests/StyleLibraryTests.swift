import Dependencies
import DependenciesTestSupport
import Foundation
@testable import StagehandCore
import StagehandModel
import Testing

@Suite struct StylePackageTests {
    @Test func aStyleRoundTripsThroughItsPackage() throws {
        var original = StylePackage.newStyle(named: "Tilted Hero")
        original.fonts = ["PressStart2P-Regular.ttf": TestResources.data("PressStart2P-Regular.ttf")]
        
        let files = try StylePackage.files(original)
        let read = try StylePackage.read(files: files)
        
        #expect(files["style.json"] != nil)
        #expect(files["previews/preview/phone/en-US.png"] != nil)
        #expect(read == original)
        #expect(try StylePackage.read(files: FileWrapper(packageFiles: files).packageFiles) == original)
    }
    
    @Test func aNewStyleHasPreviewSlidesAndScreensForEveryClass() throws {
        let contents = StylePackage.newStyle()
        let set = try #require(contents.project.sets.first)
        
        #expect(contents.project.slides(in: set).count == 3)
        #expect(set.devices == [.phone, .pad, .watch])
        #expect(contents.project.slides(in: set).map { $0.template.base } == [.straight, .tilted, .zoomed])
        #expect(DeviceClass.allCases.allSatisfy { device in contents.captures.records.keys.contains { $0.deviceClass == device } })
    }
    
    @Test func aStyleDocumentsPreviewsResolveWithoutAMissingCapture() throws {
        let contents = StylePackage.newStyle()
        let set = try #require(contents.project.sets.first)
        let slide = try #require(contents.project.slides(in: set).first)
        let scene = Resolver.resolve(ResolveRequest(slide: slide, style: contents.project.style, target: DeviceTable.target("ipad-13"), locale: "en-US", sourceLocale: "en-US", captures: CaptureCatalog(index: contents.captures)))
        
        #expect(!scene.flags.contains { if case .missingCapture = $0 { true } else { false } })
    }
}

@Suite struct StyleLibraryTests {
    private let fileManager = InMemoryFileManager()
    
    private var library: StyleLibrary {
        StyleLibrary(libraryURL: URL(filePath: "/Library"), fileManager: fileManager)
    }
    
    @Test func savingAsNewMakesANewStyle() throws {
        let base = try library.save(.fixture(), fonts: [:], asNewVersion: false)
        let listed = library.list()
        
        #expect(base.version == 1)
        #expect(base.styleID != Style.fixture().id)
        #expect(listed.map(\.name) == ["Dark Glow"])
        #expect(listed.first?.url.lastPathComponent == "Dark Glow.stagehandstyle")
        
        try library.save(.fixture(), fonts: [:], asNewVersion: false)
        #expect(library.list().map(\.url.lastPathComponent).sorted() == ["Dark Glow 2.stagehandstyle", "Dark Glow.stagehandstyle"])
    }
    
    @Test func savingAsANewVersionBumpsItInPlace() throws {
        let first = try library.save(.fixture(), fonts: [:], asNewVersion: false)
        var changed = first.snapshot
        changed.colors["accent"] = RGBA(hex: "#3C9DFF")
        let second = try library.save(changed, fonts: ["A.ttf": Data([1])], asNewVersion: true)
        
        #expect(second.styleID == first.styleID)
        #expect(second.version == 2)
        #expect(library.list().count == 1)
        
        let loaded = try library.load(try #require(library.style(id: first.styleID)))
        #expect(loaded.project.style.colors["accent"] == RGBA(hex: "#3C9DFF"))
        #expect(loaded.fonts == ["A.ttf": Data([1])])
    }
}

@Suite struct StyleMergeTests {
    private let base = Style.fixture()
    
    @Test func aChangeOnlyInTheLibraryIsTaken() throws {
        var library = base
        library.version = 2
        library.colors["accent"] = RGBA(hex: "#3C9DFF")
        
        let result = try StyleMerge.merge(base: base, library: library, project: base)
        #expect(result.conflicts.isEmpty)
        #expect(result.merged.colors["accent"] == RGBA(hex: "#3C9DFF"))
        #expect(result.merged.version == 2)
    }
    
    @Test func aChangeOnlyInTheProjectIsKept() throws {
        var project = base
        project.primary.size.base = 0.09
        
        let result = try StyleMerge.merge(base: base, library: base, project: project)
        #expect(result.conflicts.isEmpty)
        #expect(result.merged.primary.size.base == 0.09)
    }
    
    @Test func aChangeInBothIsAConflictThatKeepsTheProjectsUnlessPicked() throws {
        var library = base
        library.primary.size.base = 0.07
        var project = base
        project.primary.size.base = 0.09
        
        let result = try StyleMerge.merge(base: base, library: library, project: project)
        let conflict = try #require(result.conflicts.first)
        #expect(result.conflicts.count == 1)
        #expect(StyleMerge.displayPath(conflict.path) == "primary › size › base")
        #expect(result.merged.primary.size.base == 0.09)
        
        let picked = try StyleMerge.merge(base: base, library: library, project: project, resolutions: [conflict.path: .library])
        #expect(picked.merged.primary.size.base == 0.07)
    }
    
    @Test func anOverrideAddedOnOneSideIsItsOwnPath() throws {
        var library = base
        library.secondary.size.overrides[.mac] = 0.05
        var project = base
        project.secondary.size.overrides[.duoInner] = 0.035
        
        let result = try StyleMerge.merge(base: base, library: library, project: project)
        #expect(result.conflicts.isEmpty)
        #expect(result.merged.secondary.size.overrides[.mac] == 0.05)
        #expect(result.merged.secondary.size.overrides[.duoInner] == 0.035)
        #expect(result.merged.secondary.size.overrides[.pad] == 0.03)
    }
    
    @Test func fillsMergeWhole() throws {
        var library = base
        library.background = Varying(.color(token: "accent"))
        var project = base
        project.colors["new"] = .white
        
        let result = try StyleMerge.merge(base: base, library: library, project: project)
        #expect(result.merged.background.base == .color(token: "accent"))
        #expect(result.merged.colors["new"] == .white)
    }
}

@MainActor
@Suite(.dependencies) struct LibraryFlowTests {
    @Test func aProjectSeesItsBaseUpdatedAndPullsTheChange() async throws {
        let fileManager = InMemoryFileManager()
        
        try await withDependencies {
            $0.fileManager = fileManager
        } operation: {
            let library = StyleLibrary(libraryURL: URL(filePath: "/StagehandTestLibrary"), fileManager: fileManager)
            let base = try library.save(.fixture(), fonts: [:], asNewVersion: false)
            var project = Project.fixture()
            project.style = base.snapshot
            project.basedOn = base
            project.style.primary.size.base = 0.09
            
            var newer = base.snapshot
            newer.colors["accent"] = RGBA(hex: "#3C9DFF")
            try library.save(newer, fonts: [:], asNewVersion: true)
            
            let coordinator = ProjectCoordinator(document: ProjectDocument(contents: ProjectContents(project: project)), measurer: FakeTextMeasurer())
            await coordinator.start()
            #expect(coordinator.baseUpdate?.version == 2)
            
            coordinator.handle(.prepareMerge)
            
            for _ in 0..<100 where coordinator.project.basedOn?.version != 2 {
                try await Task.sleep(for: .milliseconds(10))
            }
            
            #expect(coordinator.project.basedOn?.version == 2)
            #expect(coordinator.project.style.colors["accent"] == RGBA(hex: "#3C9DFF"))
            #expect(coordinator.project.style.primary.size.base == 0.09)
            #expect(coordinator.baseUpdate == nil)
        }
    }
    
    @Test func newProjectFromThisCarriesTheStyleAndSkeletonButNotCaptures() throws {
        var project = Project.fixture()
        project.appLink = AppLink(project: Data(), projectPath: "/a.xcodeproj", scheme: "S", testTarget: "T")
        let address = CaptureAddress(key: "read-the-land", deviceClass: .phone, locale: "en-US")
        let contents = ProjectContents(
            project: project,
            captures: CaptureIndex(records: [address: CaptureRecord(address: address, pixelWidth: 1320, pixelHeight: 2868, targetID: nil, source: .dropped, importedAt: .sampleDate)]),
            captureFiles: [address: Data([1])],
            fonts: ["A.ttf": Data([2])]
        )
        let coordinator = ProjectCoordinator(document: ProjectDocument(contents: contents), measurer: FakeTextMeasurer())
        
        let derived = coordinator.derivedProject(name: "Flask Master", carrySkeleton: true, carryText: false)
        #expect(derived.project.style == project.style)
        #expect(derived.project.appLink == nil)
        #expect(derived.captures.records.isEmpty)
        #expect(derived.fonts == ["A.ttf": Data([2])])
        #expect(derived.project.devices == [.phone, .pad])
        
        let slides = derived.project.slides(in: derived.project.mainLineup)
        #expect(slides.count == 3)
        #expect(Set(slides.map(\.id)).isDisjoint(with: project.slides.keys))
        #expect(slides[1].template[.phone] == .tilted)
        #expect(slides.allSatisfy { $0.primary.base["en-US"] == "Headline" })
        
        let withText = coordinator.derivedProject(name: "x", carrySkeleton: true, carryText: true)
        #expect(withText.project.slides(in: withText.project.mainLineup).first?.primary.base["en-US"] == "Read the land")
        
        let styleOnly = coordinator.derivedProject(name: "x", carrySkeleton: false, carryText: false)
        #expect(styleOnly.project.slides.isEmpty)
        #expect(styleOnly.project.devices == [.phone, .pad])
    }
    
    @Test func savingTheStyleSetsTheProjectsBase() async throws {
        let fileManager = InMemoryFileManager()
        
        try await withDependencies {
            $0.fileManager = fileManager
        } operation: {
            let coordinator = ProjectCoordinator(document: ProjectDocument(contents: ProjectContents(project: .fixture())), measurer: FakeTextMeasurer())
            coordinator.handle(.saveStyleToLibrary(asNewVersion: false))
            
            for _ in 0..<100 where coordinator.project.basedOn == nil {
                try await Task.sleep(for: .milliseconds(10))
            }
            
            let base = try #require(coordinator.project.basedOn)
            #expect(base.version == 1)
            #expect(coordinator.project.style.id == base.styleID)
            #expect(StyleLibrary(libraryURL: URL(filePath: "/StagehandTestLibrary"), fileManager: fileManager).list().count == 1)
        }
    }
}
