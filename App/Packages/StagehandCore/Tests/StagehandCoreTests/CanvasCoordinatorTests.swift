import CoreGraphics
import Dependencies
import DependenciesTestSupport
import Foundation
@testable import StagehandCore
import StagehandModel
import Testing

@MainActor
@Suite(.dependencies) struct CanvasCoordinatorTests {
    /// The fixture project with its first slide selected on iPhone, and, unless `onSlide`, the Straight template open
    /// in the template editor.
    private func make(onSlide: Bool = false) -> (ProjectCoordinator, CanvasCoordinator, UndoManager) {
        let project = ProjectCoordinator(document: ProjectDocument(contents: ProjectContents(project: .fixture())), measurer: FakeTextMeasurer())
        let undo = UndoManager()
        undo.groupsByEvent = false
        project.undoManager = undo
        let set = project.project.mainLineup
        project.handle(.selectCell(CellID(setID: set.id, slideID: set.slideIDs[0], targetID: "iphone-dynamic-island-large")))
        
        if !onSlide {
            project.handle(.selectTemplate(.straight))
        }
        
        return (project, CanvasCoordinator(project: project), undo)
    }
    
    private func scene(_ project: ProjectCoordinator) -> ResolvedScene {
        project.canvasScene!
    }
    
    private func device(_ project: ProjectCoordinator) -> ResolvedDevice {
        scene(project).device!
    }
    
    private func straightLayout(_ project: ProjectCoordinator) -> TemplateLayout? {
        project.project.style.template(.straight)?.layouts[.phone]
    }
    
    @Test func resizingFromACornerKeepsTheOppositeCornerInPlace() throws {
        let (project, canvas, undo) = make()
        let original = straightLayout(project)
        let before = device(project)
        let fixed = Resolver.devicePoint(.topLeading, center: before.center, size: before.size, rotation: 0)
        
        canvas.handle(.resize(.device, handle: .bottomTrailing, translation: CGSize(width: -100, height: -60), snapping: false, tolerance: 0))
        canvas.handle(.resize(.device, handle: .bottomTrailing, translation: CGSize(width: -200, height: -120), snapping: false, tolerance: 0))
        canvas.handle(.endGesture)
        
        let after = device(project)
        let corner = Resolver.devicePoint(.topLeading, center: after.center, size: after.size, rotation: 0)
        
        #expect(after.size.width < before.size.width)
        #expect(abs(after.size.width / after.size.height - before.size.width / before.size.height) < 0.0001)
        #expect(abs(corner.x - fixed.x) < 0.01)
        #expect(abs(corner.y - fixed.y) < 0.01)
        
        undo.undo()
        #expect(straightLayout(project) == original)
    }
    
    @Test func resizingFromAnEdgeKeepsTheOppositeEdge() throws {
        let (project, canvas, _) = make()
        let before = device(project)
        
        canvas.handle(.resize(.device, handle: .leading, translation: CGSize(width: 80, height: 0), snapping: false, tolerance: 0))
        canvas.handle(.endGesture)
        
        let after = device(project)
        #expect(abs((after.center.x + after.size.width / 2) - (before.center.x + before.size.width / 2)) < 0.01)
        #expect(abs(after.size.width - (before.size.width - 80)) < 0.01)
    }
    
    @Test func textResizesOnlyFromItsSidesAndKeepsItsHeight() throws {
        let (project, canvas, _) = make()
        let before = try #require(scene(project).primary?.frame)
        
        canvas.handle(.resize(.primary, handle: .leading, translation: CGSize(width: 50, height: 300), snapping: false, tolerance: 0))
        canvas.handle(.resize(.primary, handle: .leading, translation: CGSize(width: 100, height: 300), snapping: false, tolerance: 0))
        canvas.handle(.endGesture)
        
        let after = try #require(scene(project).primary?.frame)
        #expect(abs(after.maxX - before.maxX) < 0.01)
        #expect(abs(after.width - (before.width - 100)) < 0.01)
        #expect(abs(after.height - before.height) < 0.01)
        #expect(abs(after.minY - before.minY) < 0.01)
        
        canvas.handle(.resize(.primary, handle: .top, translation: CGSize(width: 0, height: 200), snapping: false, tolerance: 0))
        canvas.handle(.endGesture)
        #expect(scene(project).primary?.frame == after)
    }
    
    @Test func dragsSnapToTheCanvasCenterUnlessSnappingIsOff() throws {
        let (project, canvas, _) = make()
        let before = device(project)
        
        canvas.handle(.drag(.device, translation: CGSize(width: 6, height: 0), snapping: true, tolerance: 10))
        #expect(canvas.guides.contains(SnapGuide(axis: .vertical, position: 660)))
        canvas.handle(.endGesture)
        #expect(abs(device(project).center.x - before.center.x) < 0.01)
        #expect(canvas.guides.isEmpty)
        
        canvas.handle(.drag(.device, translation: CGSize(width: 6, height: 0), snapping: false, tolerance: 10))
        canvas.handle(.endGesture)
        #expect(abs(device(project).center.x - (before.center.x + 6)) < 0.01)
    }
    
    @Test func changingTheAnchorKeepsTheElementInPlace() throws {
        let (project, canvas, _) = make()
        let before = device(project)
        let text = try #require(scene(project).primary?.frame)
        
        canvas.handle(.setAnchor(.device, .bottomTrailing))
        canvas.handle(.setAnchor(.primary, .bottomLeading))
        
        #expect(straightLayout(project)?.device.anchor == .bottomTrailing)
        #expect(abs(device(project).center.x - before.center.x) < 0.01)
        #expect(abs(device(project).center.y - before.center.y) < 0.01)
        #expect(straightLayout(project)?.primary.anchor == .bottomLeading)
        
        let moved = try #require(scene(project).primary?.frame)
        #expect(abs(moved.minX - text.minX) < 0.01 && abs(moved.minY - text.minY) < 0.01)
    }
    
    @Test func theArrangementShowsTheAnchorPoint() throws {
        let (project, canvas, _) = make()
        canvas.handle(.select(.primary))
        canvas.handle(.setAnchor(.primary, .topLeading))
        
        let frame = try #require(scene(project).primary?.frame)
        let arrangement = try #require(canvas.arrangement)
        #expect(arrangement.anchor == .topLeading)
        #expect(arrangement.point == frame.origin)
        
        canvas.handle(.setPosition(.primary, CGPoint(x: 100, y: 200)))
        #expect(scene(project).primary?.frame.origin == CGPoint(x: 100, y: 200))
        
        canvas.handle(.setWidth(.primary, 600))
        #expect(scene(project).primary?.frame.width == 600)
        #expect(scene(project).primary?.frame.minX == 100)
    }
    
    @Test func theDevicePositionFieldMovesItsAnchorPoint() throws {
        let (project, canvas, _) = make()
        canvas.handle(.select(.device))
        canvas.handle(.setPosition(.device, CGPoint(x: 700, y: 1500)))
        
        let arrangement = try #require(canvas.arrangement)
        #expect(abs(arrangement.point.x - 700) < 0.01)
        #expect(abs(arrangement.point.y - 1500) < 0.01)
        
        canvas.handle(.setRotation(.device, 5))
        #expect(device(project).rotation == 5)
    }
    
    @Test func movingATemplatesDeviceMovesItOnEverySlideThatUsesIt() throws {
        let (project, canvas, _) = make()
        let set = project.project.mainLineup
        let cells = set.slideIDs.map { CellID(setID: set.id, slideID: $0, targetID: "iphone-dynamic-island-large") }
        let before = cells.map { project.scene(for: $0)!.device!.center }
        
        canvas.handle(.drag(.device, translation: CGSize(width: 0, height: -100), snapping: false, tolerance: 0))
        canvas.handle(.endGesture)
        
        let after = cells.map { project.scene(for: $0)!.device!.center }
        
        // The first and third slides use Straight on iPhone, and the second uses Tilted, so it doesn't move.
        #expect(abs(after[0].y - (before[0].y - 100)) < 0.01)
        #expect(abs(after[2].y - (before[2].y - 100)) < 0.01)
        #expect(after[1] == before[1])
    }
    
    @Test func movingAnElementOnASlideAsksToDetachAndChangesNothing() throws {
        let (project, canvas, _) = make(onSlide: true)
        let contents = project.document.contents
        
        canvas.handle(.drag(.device, translation: CGSize(width: 50, height: 0), snapping: false, tolerance: 0))
        canvas.handle(.drag(.device, translation: CGSize(width: 80, height: 0), snapping: false, tolerance: 0))
        
        #expect(project.pendingDetach == .device)
        #expect(project.document.contents == contents)
        
        canvas.handle(.endGesture)
        project.handle(.cancelDetach)
        canvas.handle(.arrow(dx: 1, dy: 0, fast: false))
        #expect(project.pendingDetach == .device)
        #expect(project.document.contents == contents)
    }
    
    @Test func aDetachedElementMovesOnlyOnThatSlideAndClass() throws {
        let (project, canvas, _) = make(onSlide: true)
        let set = project.project.mainLineup
        let third = CellID(setID: set.id, slideID: set.slideIDs[2], targetID: "iphone-dynamic-island-large")
        let padCell = CellID(setID: set.id, slideID: set.slideIDs[0], targetID: "ipad-13")
        let thirdBefore = project.scene(for: third)!.device!.center
        let padBefore = project.scene(for: padCell)!.device!.center
        let before = device(project).center
        
        project.handle(.detach(.device))
        #expect(project.pendingDetach == nil)
        #expect(canvas.isLocked(.device) == false)
        #expect(canvas.isLocked(.primary))
        
        canvas.handle(.drag(.device, translation: CGSize(width: 40, height: 0), snapping: false, tolerance: 0))
        canvas.handle(.endGesture)
        
        #expect(abs(device(project).center.x - (before.x + 40)) < 0.01)
        #expect(project.scene(for: third)!.device!.center == thirdBefore)
        #expect(project.scene(for: padCell)!.device!.center == padBefore)
        
        // The template still moves the text, which isn't detached, but not the detached device.
        let text = try #require(scene(project).primary?.frame)
        project.handle(.selectTemplate(.straight))
        canvas.handle(.drag(.primary, translation: CGSize(width: 0, height: 30), snapping: false, tolerance: 0))
        canvas.handle(.endGesture)
        canvas.handle(.drag(.device, translation: CGSize(width: 0, height: 30), snapping: false, tolerance: 0))
        canvas.handle(.endGesture)
        project.handle(.selectCell(CellID(setID: set.id, slideID: set.slideIDs[0], targetID: "iphone-dynamic-island-large")))
        
        #expect(abs((scene(project).primary?.frame.minY ?? 0) - (text.minY + 30)) < 0.01)
        #expect(abs(device(project).center.x - (before.x + 40)) < 0.01)
        #expect(abs(device(project).center.y - before.y) < 0.01)
        
        project.handle(.reattach(.device))
        #expect(project.currentSlide?.detachments.isEmpty == true)
    }
    
    // MARK: - Zoom
    
    @Test func zoomingStepsAroundTheMiddleAndBackToFit() {
        let (project, canvas, undo) = make()
        let original = project.project
        canvas.handle(.setViewport(CGSize(width: 800, height: 900)))
        let fit = canvas.scale
        
        canvas.handle(.zoomOut)
        #expect(canvas.zoom == 1 / CanvasCoordinator.zoomStep)
        #expect(abs(canvas.scale - fit / CanvasCoordinator.zoomStep) < 0.0001)
        #expect(canvas.pan == .zero)
        
        canvas.handle(.zoomIn)
        #expect(canvas.zoom == 1)
        #expect(!canvas.isZoomed)
        
        // Zooming is a view setting, not an edit.
        #expect(!undo.canUndo)
        #expect(project.project == original)
    }
    
    @Test func zoomingOutGoesFarEnoughToReachPastTheCanvas() {
        let (_, canvas, _) = make()
        canvas.handle(.setViewport(CGSize(width: 800, height: 900)))
        
        for _ in 0..<30 {
            canvas.handle(.zoomOut)
        }
        
        #expect(canvas.zoom == CanvasCoordinator.zoomRange.lowerBound)
    }
    
    @Test func scrollZoomingKeepsThePointUnderThePointerStill() {
        let (project, canvas, _) = make()
        let viewport = CGSize(width: 800, height: 900)
        canvas.handle(.setViewport(viewport))
        let anchor = CGPoint(x: 150, y: -200)
        
        // The canvas pixel under the pointer, before and after.
        func pixel() -> CGPoint {
            CGPoint(x: (anchor.x - canvas.pan.width) / canvas.scale, y: (anchor.y - canvas.pan.height) / canvas.scale)
        }
        
        let before = pixel()
        canvas.handle(.zoom(by: 2, around: anchor))
        let after = pixel()
        
        #expect(canvas.zoom == 2)
        #expect(abs(before.x - after.x) < 0.001 && abs(before.y - after.y) < 0.001)
        #expect(project.canvasScene != nil)
    }
    
    @Test func panningKeepsSomeOfTheCanvasInView() {
        let (project, canvas, _) = make()
        let viewport = CGSize(width: 800, height: 900)
        canvas.handle(.setViewport(viewport))
        canvas.handle(.zoom(by: 3, around: .zero))
        canvas.handle(.pan(by: CGSize(width: 100_000, height: -100_000)))
        
        let size = scene(project).canvas
        let limitX = (size.width * canvas.scale + viewport.width) / 2 - CanvasCoordinator.panKeepsVisible
        let limitY = (size.height * canvas.scale + viewport.height) / 2 - CanvasCoordinator.panKeepsVisible
        #expect(abs(canvas.pan.width - limitX) < 0.001)
        #expect(abs(canvas.pan.height + limitY) < 0.001)
        
        canvas.handle(.zoomToFit)
        #expect(canvas.zoom == 1 && canvas.pan == .zero)
    }
    
    // MARK: - Preview
    
    @Test func previewTogglesAndStopsGesturesFromEditing() {
        let (project, canvas, undo) = make()
        let original = straightLayout(project)
        
        canvas.handle(.togglePreview)
        #expect(canvas.isPreviewing)
        
        canvas.handle(.drag(.device, translation: CGSize(width: 120, height: 0), snapping: false, tolerance: 0))
        canvas.handle(.endGesture)
        canvas.handle(.arrow(dx: 1, dy: 0, fast: true))
        #expect(straightLayout(project) == original)
        #expect(!undo.canUndo)
        
        canvas.handle(.togglePreview)
        #expect(!canvas.isPreviewing)
        
        canvas.handle(.arrow(dx: 1, dy: 0, fast: true))
        #expect(straightLayout(project) != original)
    }
}
