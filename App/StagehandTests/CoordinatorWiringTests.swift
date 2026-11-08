import Foundation
import StagehandCore
import StagehandModel
import Testing
import UniformTypeIdentifiers

/// The app's coordinators wired to a document, inside the app.
@MainActor
@Suite struct CoordinatorWiringTests {
    @Test func aNewDocumentOpensWithAnEmptyProjectOnIPhone() {
        let document = ProjectDocument()
        #expect(document.project.sets.count == 1)
        #expect(document.project.devices == [.phone])
        #expect(document.project.slides.isEmpty)
        #expect(ProjectDocument.readableContentTypes == [.stagehandProject])
    }
    
    @Test func theProjectTypeIsAPackage() {
        #expect(UTType.stagehandProject.conforms(to: .package))
        #expect(UTType.stagehandProject.preferredFilenameExtension == "stagehand")
    }
    
    @Test func theCanvasMovesATemplatesDeviceAsOneUndoStep() {
        let document = ProjectDocument(contents: ProjectContents(project: .fixture()))
        let project = ProjectCoordinator(document: document)
        let canvas = CanvasCoordinator(project: project)
        let undo = UndoManager()
        undo.groupsByEvent = false
        project.undoManager = undo
        
        let set = project.project.mainLineup
        project.handle(.selectCell(CellID(setID: set.id, slideID: set.slideIDs[0], targetID: set.targets[0])))
        project.handle(.selectTemplate(.straight))
        let before = project.project.style.template(.straight)?.layouts[.phone]?.device.position
        
        canvas.handle(.drag(.device, translation: CGSize(width: 66, height: 0), snapping: false, tolerance: 0))
        canvas.handle(.drag(.device, translation: CGSize(width: 132, height: 286.8), snapping: false, tolerance: 0))
        canvas.handle(.endGesture)
        
        let after = project.project.style.template(.straight)?.layouts[.phone]?.device.position
        #expect(abs((after?.x ?? 0) - ((before?.x ?? 0) + 0.1)) < 0.0001)
        #expect(abs((after?.y ?? 0) - ((before?.y ?? 0) + 0.1)) < 0.0001)
        
        undo.undo()
        #expect(project.project.style.template(.straight)?.layouts[.phone]?.device.position == before)
    }
    
    @Test func aSlidesDeviceMovesOnlyAfterDetaching() {
        let project = ProjectCoordinator(document: ProjectDocument(contents: ProjectContents(project: .fixture())))
        let canvas = CanvasCoordinator(project: project)
        let set = project.project.mainLineup
        project.handle(.selectCell(CellID(setID: set.id, slideID: set.slideIDs[0], targetID: set.targets[0])))
        
        canvas.handle(.drag(.device, translation: CGSize(width: 66, height: 0), snapping: false, tolerance: 0))
        canvas.handle(.endGesture)
        #expect(project.pendingDetach == .device)
        #expect(project.currentSlide?.detachments.isEmpty == true)
        
        project.handle(.detach(.device))
        canvas.handle(.drag(.device, translation: CGSize(width: 66, height: 0), snapping: false, tolerance: 0))
        canvas.handle(.endGesture)
        
        let template = project.project.style.template(.straight)?.layouts[.phone]?.device.position.x ?? 0
        #expect(abs((project.currentSlide?.detachments[.phone]?.device?.position.x ?? 0) - (template + 0.05)) < 0.0001)
    }
}
