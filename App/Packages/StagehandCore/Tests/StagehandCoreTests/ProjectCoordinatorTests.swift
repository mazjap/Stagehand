import CoreGraphics
import Dependencies
import DependenciesTestSupport
import Foundation
@testable import StagehandCore
import StagehandModel
import Testing

@MainActor
@Suite(.dependencies) struct ProjectCoordinatorTests {
    private func makeCoordinator(_ project: Project = .fixture()) -> (ProjectCoordinator, UndoManager) {
        let coordinator = ProjectCoordinator(document: ProjectDocument(contents: ProjectContents(project: project)), measurer: FakeTextMeasurer())
        let undo = UndoManager()
        undo.groupsByEvent = false
        coordinator.undoManager = undo
        return (coordinator, undo)
    }
    
    private func select(_ coordinator: ProjectCoordinator, slide index: Int, target: String) {
        let set = coordinator.project.sets[0]
        coordinator.handle(.selectCell(CellID(setID: set.id, slideID: set.slideIDs[index], targetID: target)))
    }
    
    @Test func aSharedEditChangesEveryClass() {
        let (coordinator, _) = makeCoordinator()
        select(coordinator, slide: 0, target: "iphone-dynamic-island-large")
        
        coordinator.handle(.editStyle("Change Size") { style, device in style.secondary.size.set(0.05, for: device) })
        
        #expect(coordinator.project.style.secondary.size[.phone] == 0.05)
        #expect(coordinator.project.style.secondary.size[.watch] == 0.06)
        #expect(coordinator.project.style.secondary.size.base == 0.05)
    }
    
    @Test func anOverrideChangesOnlyItsOwnClass() {
        let (coordinator, _) = makeCoordinator()
        select(coordinator, slide: 0, target: "ipad-13")
        
        // The iPad already overrides the primary size, so the edit stays on the iPad.
        coordinator.handle(.editStyle("Change Size") { style, device in style.primary.size.set(0.07, for: device) })
        
        #expect(coordinator.project.style.primary.size[.pad] == 0.07)
        #expect(coordinator.project.style.primary.size[.phone] == 0.085)
    }
    
    @Test func textEditsGoToTheSharedTextUnlessOverridden() throws {
        let (coordinator, _) = makeCoordinator()
        select(coordinator, slide: 0, target: "ipad-13")
        coordinator.handle(.setText(.primary, "Read the hills"))
        
        let slide = try #require(coordinator.currentSlide)
        #expect(slide.primary.base["en-US"] == "Read the hills")
        
        coordinator.handle(.overrideText(.primary))
        coordinator.handle(.setText(.primary, "Read"))
        let overridden = try #require(coordinator.currentSlide)
        #expect(overridden.primary.text(for: .pad, locale: "en-US", source: "en-US")?.text == "Read")
        #expect(overridden.primary.text(for: .phone, locale: "en-US", source: "en-US")?.text == "Read the hills")
        
        coordinator.handle(.revertText(.primary))
        #expect(coordinator.currentSlide?.primary.overrides.isEmpty == true)
    }
    
    @Test func undoReversesAWholeDragInOneStep() {
        let (coordinator, undo) = makeCoordinator()
        select(coordinator, slide: 0, target: "iphone-dynamic-island-large")
        let before = coordinator.project
        
        coordinator.handle(.beginGesture("Move Device"))
        
        for _ in 0..<5 {
            coordinator.handle(.editSlide("Move Device") { slide, device in
                slide.detachments[device, default: Detachment()].device = DevicePlacement(position: NormPoint(x: 0.5, y: 0.5 + Double(slide.detachments.count) * 0.01), width: 0.8)
            })
            coordinator.handle(.editStyle("Move Device") { style, device in style.secondary.size.set(style.secondary.size[device] + 0.001, for: device) })
        }
        
        coordinator.handle(.endGesture)
        
        #expect(abs(coordinator.project.style.secondary.size[.phone] - 0.047) < 0.0001)
        #expect(undo.undoActionName == "Move Device")
        
        undo.undo()
        #expect(coordinator.project == before)
        #expect(!undo.canUndo)
        
        undo.redo()
        #expect(abs(coordinator.project.style.secondary.size[.phone] - 0.047) < 0.0001)
    }
    
    @Test func eachEditOutsideAGestureIsItsOwnUndoStep() {
        let (coordinator, undo) = makeCoordinator()
        select(coordinator, slide: 0, target: "iphone-dynamic-island-large")
        
        coordinator.handle(.editStyle("Size") { style, device in style.secondary.size.set(style.secondary.size[device] + 0.01, for: device) })
        coordinator.handle(.editStyle("Size") { style, device in style.secondary.size.set(style.secondary.size[device] + 0.01, for: device) })
        undo.undo()
        
        #expect(abs(coordinator.project.style.secondary.size[.phone] - 0.052) < 0.0001)
    }
    
    @Test func aTextEditReRendersOnlyItsRow() async throws {
        let (coordinator, _) = makeCoordinator()
        await coordinator.start()
        let set = coordinator.project.sets[0]
        let cells = set.slideIDs.flatMap { slide in set.targets.map { CellID(setID: set.id, slideID: slide, targetID: $0) } }
        
        for cell in cells {
            #expect(coordinator.thumbnail(for: cell, width: 60) != nil)
        }
        
        let rendered = coordinator.thumbnails.renderCount
        #expect(rendered == cells.count)
        
        select(coordinator, slide: 1, target: "iphone-dynamic-island-large")
        coordinator.handle(.setText(.secondary, "Offline maps"))
        
        for cell in cells {
            _ = coordinator.thumbnail(for: cell, width: 60)
        }
        
        // Both of the slide's cells (iPhone and iPad) re-render, and nothing else.
        #expect(coordinator.thumbnails.renderCount == rendered + 2)
    }
    
    @Test func droppedCapturesAreClassifiedAndRefusalsListed() {
        let (coordinator, undo) = makeCoordinator()
        let phone = DroppedFile(name: "read-the-land.png", data: TestImages.solid(width: 1320, height: 2868).pngData()!)
        let odd = DroppedFile(name: "odd.png", data: TestImages.solid(width: 640, height: 480).pngData()!)
        
        coordinator.handle(.importCaptures([phone, odd], .sheet))
        
        let address = CaptureAddress(key: "read-the-land", deviceClass: .phone, locale: "en-US")
        #expect(coordinator.document.captures.records[address] != nil)
        #expect(coordinator.importIssues == [.unknownSize("odd.png", width: 640, height: 480)])
        #expect(coordinator.issues.contains { $0.kind == .importRefused("odd.png") })
        
        undo.undo()
        #expect(coordinator.document.captures.records.isEmpty)
    }
    
    /// FlaskMaster's tests write `AppStoreScreenshots/<iPhone or iPad>/<name>.png`, and TrekPoint's
    /// `Source Images/<device>/<number>. <name>.png`. Every image imports, keyed by its name, whether or not a slide
    /// uses that key yet.
    @Test func aScreenshotsFolderImportsEveryImageInIt() throws {
        let root = URL(filePath: "/Developer/FlaskMaster/AppStoreScreenshots")
        let phone = TestImages.solid(width: 1320, height: 2868).pngData()!
        let pad = TestImages.solid(width: 2064, height: 2752).pngData()!
        let files = InMemoryFileManager(files: [
            root.appending(path: "iPhone/01-level.png"): phone,
            root.appending(path: "iPhone/1. Terrain Made Clear.png"): phone,
            root.appending(path: "iPad/01-level.png"): pad,
            root.appending(path: "iPad/.DS_Store"): Data(),
            root.appending(path: "README.md"): Data(),
        ])
        
        let (coordinator, undo) = withDependencies {
            $0.fileManager = files
        } operation: {
            makeCoordinator()
        }
        
        coordinator.handle(.importScreenshotsFolder(root))
        
        let addresses = Set(coordinator.document.captures.records.keys)
        #expect(addresses == [
            CaptureAddress(key: "01-level", deviceClass: .phone, locale: "en-US"),
            CaptureAddress(key: "1-terrain-made-clear", deviceClass: .phone, locale: "en-US"),
            CaptureAddress(key: "01-level", deviceClass: .pad, locale: "en-US"),
        ])
        #expect(coordinator.importIssues.isEmpty)
        
        undo.undo()
        #expect(coordinator.document.captures.records.isEmpty)
    }
    
    @Test func textSizesReadInPointsOfTheTargetOnTheCanvas() {
        let (coordinator, _) = makeCoordinator()
        select(coordinator, slide: 0, target: "iphone-dynamic-island-large")
        
        #expect(coordinator.currentCanvasWidth == 1320)
        #expect(coordinator.points(fromFraction: 0.12) == 158.4)
        #expect(abs(coordinator.fraction(fromPoints: 158.4) - 0.12) < 1e-12)
        
        // The same stored size is more points on the wider iPad canvas, so one layout fits each class.
        select(coordinator, slide: 0, target: "ipad-13")
        #expect(coordinator.currentCanvasWidth == 2064)
        #expect(coordinator.points(fromFraction: 0.05) == 103.2)
    }
    
    @Test func captureKeysListWhatThereAreScreenshotsFor() throws {
        let (coordinator, _) = makeCoordinator()
        let set = coordinator.project.mainLineup
        coordinator.handle(.selectCell(CellID(setID: set.id, slideID: set.slideIDs[0], targetID: "iphone-dynamic-island-large")))
        let used = try #require(coordinator.currentSlide).captureKey[.phone]
        let image = TestImages.solid(width: 1320, height: 2868).pngData()!
        
        coordinator.handle(.importCapturesToCanvas([DroppedFile(name: "a.png", data: image)]))
        coordinator.document.captures.records[CaptureAddress(key: "10-stats", deviceClass: .phone, locale: "en-US")] = coordinator.document.captures.records.values.first
        coordinator.document.captures.records[CaptureAddress(key: "2-pour", deviceClass: .phone, locale: "en-US")] = coordinator.document.captures.records.values.first
        
        let keys = coordinator.captureKeys(on: .phone)
        #expect(keys.map(\.key) == ["2-pour", "10-stats", used].sorted { $0.localizedStandardCompare($1) == .orderedAscending })
        #expect(keys.first { $0.key == used }?.inUse == true)
        #expect(keys.first { $0.key == "2-pour" }?.inUse == false)
        #expect(coordinator.captureKeys(on: .pad).isEmpty)
    }
    
    @Test func aDropOnTheCanvasBecomesTheSlidesCaptureThere() throws {
        let (coordinator, _) = makeCoordinator()
        let set = coordinator.project.mainLineup
        coordinator.handle(.selectCell(CellID(setID: set.id, slideID: set.slideIDs[0], targetID: "iphone-dynamic-island-large")))
        let slide = try #require(coordinator.currentSlide)
        let screenshot = DroppedFile(name: "Simulator Screenshot.png", data: TestImages.solid(width: 1320, height: 2868).pngData()!)
        
        coordinator.handle(.importCapturesToCanvas([screenshot]))
        
        let address = CaptureAddress(key: slide.captureKey[.phone], deviceClass: .phone, locale: coordinator.selection.locale)
        #expect(coordinator.document.captures.records[address] != nil)
        #expect(coordinator.importIssues.isEmpty)
        
        // The template editor has no slide of its own to take it.
        coordinator.handle(.removeCapture(address))
        coordinator.handle(.selectTemplate(.straight))
        coordinator.handle(.importCapturesToCanvas([screenshot]))
        #expect(coordinator.document.captures.records[address] == nil)
    }
    
    /// Regression test: a file dropped on the contact sheet took its capture key from its name, so a simulator
    /// screenshot ("Simulator Screenshot - iPhone 17 Pro Max - ….png") was stored under a key no slide uses, and the
    /// drop seemed to do nothing.
    @Test func aSheetDropMatchingNoSlideIsRefusedAndSaysWhy() {
        let (coordinator, undo) = makeCoordinator()
        let screenshot = DroppedFile(name: "Simulator Screenshot - iPhone 17 Pro Max - 2026-11-07 at 10.00.00.png", data: TestImages.solid(width: 1320, height: 2868).pngData()!)
        
        coordinator.handle(.importCaptures([screenshot], .sheet))
        
        #expect(coordinator.document.captures.records.isEmpty)
        #expect(!undo.canUndo)
        #expect(coordinator.importIssues == [.noMatchingSlide(screenshot.name, key: "simulator-screenshot-iphone-17-pro-max-2026-11-07-at-10-00-00")])
    }
    
    @Test func editingASlideSharedWithAProductPageChangesItInBoth() throws {
        let (coordinator, _) = makeCoordinator()
        let main = coordinator.project.mainLineup
        coordinator.handle(.addProductPage(name: "Hikers"))
        let page = try #require(coordinator.currentSet)
        
        #expect(page.slideIDs == main.slideIDs)
        #expect(page.customProductPageID == "")
        #expect(coordinator.contactSheet.rows.first?.alsoIn == ["App Store"])
        
        coordinator.handle(.selectCell(CellID(setID: page.id, slideID: page.slideIDs[0], targetID: page.targets[0])))
        coordinator.handle(.setText(.primary, "Shared"))
        
        #expect(coordinator.project.slides[main.slideIDs[0]]?.primary.base["en-US"] == "Shared")
    }
    
    @Test func makeIndependentCopySplitsASharedSlide() throws {
        let (coordinator, _) = makeCoordinator()
        let main = coordinator.project.mainLineup
        coordinator.handle(.addProductPage(name: "Hikers"))
        let page = try #require(coordinator.currentSet)
        
        coordinator.handle(.makeIndependentCopy(page.slideIDs[0]))
        
        let split = try #require(coordinator.currentSet)
        #expect(split.slideIDs[0] != main.slideIDs[0])
        #expect(coordinator.project.mainLineup.slideIDs[0] == main.slideIDs[0])
    }
    
    @Test func aDeviceAddedLaterCanLeaveExistingSlidesOff() {
        let (coordinator, undo) = makeCoordinator(.empty())
        coordinator.handle(.addSlide())
        let first = coordinator.project.slideOrder[0]
        #expect(coordinator.project.devices == [.phone])
        
        coordinator.handle(.addDevice(.pad, includeExistingSlides: false))
        coordinator.handle(.addSlide())
        let second = coordinator.project.slideOrder[1]
        
        #expect(coordinator.project.devices == [.phone, .pad])
        #expect(coordinator.project.targets == ["iphone-dynamic-island-large", "ipad-13"])
        #expect(coordinator.project.slides[first]?.isOn(.pad) == false)
        #expect(coordinator.project.slides[second]?.isOn(.pad) == true)
        #expect(coordinator.project.slides(in: coordinator.project.mainLineup, on: .pad).map(\.id) == [second])
        
        // The blank template set has no iPad layout yet, which is flagged.
        #expect(coordinator.issues.contains { $0.kind == .noLayout(.pad) })
        
        coordinator.handle(.setSlideOn(first, .pad, true))
        #expect(coordinator.project.slides(in: coordinator.project.mainLineup, on: .pad).count == 2)
        
        undo.undo()
        undo.undo()
        undo.undo()
        #expect(coordinator.project.devices == [.phone])
    }
    
    @Test func aNewProjectStartsWithNoSlidesAndAddsThemFromTemplates() throws {
        let (coordinator, _) = makeCoordinator(.empty(devices: [.phone], style: StarterTemplateSet.darkGlow.style()))
        #expect(coordinator.project.slides.isEmpty)
        
        coordinator.handle(.addSlide(template: .tilted))
        coordinator.handle(.addSlide(template: .zoomed, at: 0))
        
        let slides = coordinator.project.slides(in: coordinator.project.mainLineup)
        #expect(slides.map { $0.template[.phone] } == [.zoomed, .tilted])
        #expect(coordinator.currentSlide?.id == slides[0].id)
    }
    
    @Test func removedSlidesWaitInDrafts() {
        let (coordinator, _) = makeCoordinator()
        let id = coordinator.project.sets[0].slideIDs[2]
        coordinator.handle(.removeSlideFromSet(id))
        
        #expect(coordinator.project.drafts.map(\.id) == [id])
        
        coordinator.handle(.addDraftToSet(id))
        #expect(coordinator.project.drafts.isEmpty)
    }
    
    @Test func exportingWritesEveryImage() async {
        let fileManager = InMemoryFileManager()
        
        await withDependencies {
            $0.fileManager = fileManager
        } operation: {
            let (coordinator, _) = makeCoordinator()
            await coordinator.start()
            let urls = coordinator.export(to: URL(filePath: "/Exports"))
            
            #expect(urls.count == 6)
            #expect(coordinator.alert == nil)
            #expect(fileManager.fileExists(at: URL(filePath: "/Exports/en-US/iphone-dynamic-island-large/02-bring-it-along.png")))
        }
    }
    
    @Test func setLevelIssuesAreListed() {
        var project = Project.fixture()
        
        for index in project.style.templates.indices {
            project.style.templates[index].layouts[.mac] = nil
        }
        
        project.devices.append(.mac)
        project.slideOrder += Array(repeating: project.slideOrder[0], count: 8)
        let (coordinator, _) = makeCoordinator(project)
        let kinds = coordinator.issues.map(\.kind)
        
        #expect(kinds.contains(.tooManySlides(count: 11)))
        #expect(kinds.contains(.noLayout(.mac)))
        #expect(kinds.contains(.requiredTargetMissing("mac")))
    }
    
    @Test func watchSizesThatDifferBetweenLocalizationsAreAnIssue() {
        let english = CaptureAddress(key: "w", deviceClass: .watch, locale: "en-US")
        let german = CaptureAddress(key: "w", deviceClass: .watch, locale: "de")
        let index = CaptureIndex(records: [
            english: CaptureRecord(address: english, pixelWidth: 422, pixelHeight: 514, targetID: "watch", source: .dropped, importedAt: .sampleDate),
            german: CaptureRecord(address: german, pixelWidth: 416, pixelHeight: 496, targetID: "watch", source: .dropped, importedAt: .sampleDate),
        ])
        
        let issues = ProjectValidator.setIssues(project: .fixture(), captures: index)
        #expect(issues.contains { $0.kind == .watchSizesDiffer(key: "w") })
    }
    
    @Test func aQuirkOnANewerRuntimeIsFlaggedAndCanBeUndone() throws {
        var project = Project.fixture()
        project.devices = [.duoInner]
        project.targets = ["iphone-duo-inner"]
        let (coordinator, _) = makeCoordinator(project)
        let address = CaptureAddress(key: "read-the-land", deviceClass: .duoInner, locale: "en-US")
        let shot = Shot(captureID: UUID(), name: "read-the-land", deviceClass: .duoInner, targetID: "iphone-duo-inner", pixelWidth: 2007, pixelHeight: 2853, simulatorModel: "iPhone19,4", simulatorRuntime: "27.2", quirksApplied: ["duo-inner-rotated-180"], capturedAt: .sampleDate)
        
        coordinator.edit("Seed") { contents in
            contents.captures.records[address] = CaptureRecord(address: address, pixelWidth: 2007, pixelHeight: 2853, targetID: "iphone-duo-inner", source: .runner, importedAt: .sampleDate, shot: shot)
            contents.captureFiles[address] = TestImages.solid(width: 2007, height: 2853).pngData()!
        }
        
        let cell = CellID(setID: project.sets[0].id, slideID: project.sets[0].slideIDs[0], targetID: "iphone-duo-inner")
        #expect(coordinator.scene(for: cell)?.flags.contains(.quirkReview(address, quirks: ["duo-inner-rotated-180"])) == true)
        
        coordinator.handle(.undoQuirk(address, quirkID: "duo-inner-rotated-180"))
        
        let record = try #require(coordinator.document.captures.records[address])
        #expect(record.quirksUndone == ["duo-inner-rotated-180"])
        #expect(record.revision == 2)
        #expect(coordinator.scene(for: cell)?.flags.contains { if case .quirkReview = $0 { true } else { false } } == false)
    }
    
    @Test func aSlideSharedWithTheWatchKeepsItsTextAndTheRestStaySeparate() throws {
        var project = Project.fixture()
        let shared = project.slideOrder[0]
        let watchOnly = Slide(title: "On Your Wrist", primary: Varying(["en-US": "On your wrist"]), secondary: Varying([:]), captureKey: Varying("wrist"), excludedDevices: [.phone, .pad])
        project.slides[watchOnly.id] = watchOnly
        project.slideOrder.append(watchOnly.id)
        project.addDevice(.watch, includeExistingSlides: false)
        project.slides[shared]?.setOn(.watch, true)
        project.slides[watchOnly.id]?.setOn(.watch, true)
        let (coordinator, _) = makeCoordinator(project)
        let main = coordinator.project.mainLineup
        
        coordinator.handle(.selectCell(CellID(setID: main.id, slideID: shared, targetID: "watch")))
        coordinator.handle(.setText(.primary, "Read anywhere"))
        
        let iOSCell = CellID(setID: main.id, slideID: shared, targetID: "iphone-dynamic-island-large")
        let watchCell = CellID(setID: main.id, slideID: shared, targetID: "watch")
        #expect(coordinator.scene(for: iOSCell)?.primary?.string == "READ ANYWHERE")
        #expect(coordinator.scene(for: watchCell)?.primary?.string == "READ ANYWHERE")
        #expect(coordinator.scene(for: watchCell)?.canvas == CGSize(width: 422, height: 514))
        #expect(coordinator.project.slides(in: main, on: .watch).map(\.id) == [shared, watchOnly.id])
        #expect(coordinator.project.slides(in: main, on: .phone).count == 3)
        #expect(coordinator.contactSheet.rows.last?.excludedDevices == [.phone, .pad])
    }
}
