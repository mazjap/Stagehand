import CoreGraphics
import Dependencies
import DependenciesTestSupport
import Foundation
@testable import StagehandCore
import StagehandModel
import Testing

/// Templates in the project coordinator: adding, deleting and laying them out per device, extra elements, and how
/// slides follow them.
@MainActor
@Suite(.dependencies) struct TemplateTests {
    private func make(_ project: Project = .fixture()) -> (ProjectCoordinator, UndoManager) {
        let coordinator = ProjectCoordinator(document: ProjectDocument(contents: ProjectContents(project: project)), measurer: FakeTextMeasurer())
        let undo = UndoManager()
        undo.groupsByEvent = false
        coordinator.undoManager = undo
        let set = coordinator.project.mainLineup
        
        if let first = set.slideIDs.first {
            coordinator.handle(.selectCell(CellID(setID: set.id, slideID: first, targetID: "iphone-dynamic-island-large")))
        }
        
        return (coordinator, undo)
    }
    
    @Test func aSlideCanUseOneTemplateOnIPhoneAndAnotherOnIPad() throws {
        let (coordinator, _) = make()
        let set = coordinator.project.mainLineup
        let padCell = CellID(setID: set.id, slideID: set.slideIDs[0], targetID: "ipad-13")
        
        coordinator.handle(.setSlideTemplate(.zoomed, scope: .override))
        
        #expect(coordinator.currentSlide?.template[.phone] == .zoomed)
        #expect(coordinator.currentSlide?.template[.pad] == .straight)
        #expect(coordinator.canvasScene?.device?.size.width == 1.25 * 1320)
        #expect(coordinator.scene(for: padCell)?.device?.size.width == 0.78 * 2064)
    }
    
    @Test func changingASlidesTemplateClearsItsDetachmentsOnThatClass() {
        let (coordinator, _) = make()
        coordinator.handle(.detach(.device))
        coordinator.handle(.selectTarget("ipad-13"))
        coordinator.handle(.detach(.primary))
        coordinator.handle(.selectTarget("iphone-dynamic-island-large"))
        #expect(coordinator.currentSlide?.detachments.keys.count == 2)
        
        coordinator.handle(.setSlideTemplate(.tilted, scope: .override))
        
        #expect(coordinator.currentSlide?.detachments[.phone] == nil)
        #expect(coordinator.currentSlide?.detachments[.pad]?.primary != nil)
    }
    
    @Test func deletingATemplateMovesItsSlidesToTheFirstRemainingOne() {
        let (coordinator, undo) = make()
        let bring = coordinator.project.slideOrder[1]
        
        coordinator.handle(.deleteTemplate(.tilted))
        
        #expect(coordinator.project.style.templates.map(\.id) == [.straight, .zoomed])
        #expect(coordinator.project.slides[bring]?.template[.phone] == .straight)
        
        undo.undo()
        #expect(coordinator.project.slides[bring]?.template[.phone] == .tilted)
    }
    
    @Test func aProjectWithNoSlidesOpensOnItsFirstTemplate() {
        let (coordinator, _) = make(.empty(devices: [.phone, .watch]))
        
        #expect(coordinator.isEditingTemplate)
        #expect(coordinator.mode == .canvas)
        #expect(coordinator.canvasScene?.primary?.string == "YOUR HEADLINE")
        #expect(Set(coordinator.currentTemplate.map { Array($0.layouts.keys) } ?? []) == [.phone, .watch])
        
        let (fixture, _) = make()
        #expect(!fixture.isEditingTemplate)
    }
    
    @Test func theLastTemplateCantBeDeleted() {
        let (coordinator, _) = make(.empty())
        let id = coordinator.project.style.templates[0].id
        
        coordinator.handle(.deleteTemplate(id))
        
        #expect(coordinator.project.style.templates.count == 1)
        #expect(coordinator.alert?.title == "Can't Delete the Last Template")
    }
    
    @Test func aNewTemplateHasALayoutForEveryDeviceAndOpensInTheEditor() throws {
        let (coordinator, _) = make()
        coordinator.handle(.addTemplate(duplicating: nil))
        let template = try #require(coordinator.currentTemplate)
        
        #expect(template.name == "Untitled Template")
        #expect(Set(template.layouts.keys) == [.phone, .pad])
        #expect(coordinator.isEditingTemplate)
        #expect(coordinator.mode == .canvas)
        
        coordinator.handle(.addTemplate(duplicating: .tilted))
        #expect(coordinator.currentTemplate?.name == "Tilted Copy")
        #expect(coordinator.currentTemplate?.layouts == coordinator.project.style.template(.tilted)?.layouts)
    }
    
    @Test func aClassesLayoutCanStartFromAnothersOrBlank() throws {
        let (coordinator, _) = make()
        coordinator.handle(.addDevice(.duoInner, includeExistingSlides: true))
        coordinator.handle(.selectTemplate(.straight))
        
        #expect(coordinator.issues.contains { $0.kind == .templateMissingLayout(.straight, .duoInner) })
        
        coordinator.handle(.addTemplateLayout(.duoInner, from: .pad))
        let straight = try #require(coordinator.project.style.template(.straight))
        #expect(straight.layouts[.duoInner]?.primary == straight.layouts[.pad]?.primary)
        #expect(coordinator.currentDeviceClass == .duoInner)
        #expect(!coordinator.issues.contains { $0.kind == .templateMissingLayout(.straight, .duoInner) })
        
        coordinator.handle(.selectTemplate(.tilted))
        coordinator.handle(.addTemplateLayout(.duoInner, from: nil))
        #expect(coordinator.project.style.template(.tilted)?.layouts[.duoInner] == Template.blankLayout(for: .duoInner))
    }
    
    @Test func extraElementsAreAddedPlacedFilledAndRemoved() throws {
        let (coordinator, _) = make()
        coordinator.handle(.selectTemplate(.straight))
        coordinator.handle(.addElement(.text))
        let element = try #require(coordinator.currentTemplate?.elements.first)
        
        #expect(element.name == "Text 1")
        #expect(coordinator.currentTemplate?.layouts[.phone]?.extras[element.id] != nil)
        #expect(coordinator.currentTemplate?.layouts[.pad]?.extras[element.id] == nil)
        
        // A slide fills it in.
        let set = coordinator.project.mainLineup
        coordinator.handle(.selectCell(CellID(setID: set.id, slideID: set.slideIDs[0], targetID: "iphone-dynamic-island-large")))
        coordinator.handle(.setExtraText(element.id, "New"))
        #expect(coordinator.canvasScene?.extra(element.id) != nil)
        
        // Shown on iPad too, then removed everywhere, content included.
        coordinator.handle(.selectTemplate(.straight))
        coordinator.handle(.selectTarget("ipad-13"))
        coordinator.handle(.setElementShown(.extra(element.id), true))
        #expect(coordinator.currentTemplate?.layouts[.pad]?.extras[element.id] != nil)
        
        coordinator.handle(.removeElement(element.id))
        #expect(coordinator.currentTemplate?.elements.isEmpty == true)
        #expect(coordinator.project.slides[set.slideIDs[0]]?.extraContent.isEmpty == true)
    }
    
    @Test func hidingAStandardElementHidesItOnlyOnThatClass() {
        let (coordinator, _) = make()
        coordinator.handle(.selectTemplate(.straight))
        coordinator.handle(.setElementShown(.secondary, false))
        
        #expect(coordinator.canvasScene?.secondary == nil)
        #expect(coordinator.project.style.template(.straight)?.layouts[.pad]?.isHidden(.secondary) == false)
        
        coordinator.handle(.setElementShown(.secondary, true))
        #expect(coordinator.canvasScene?.secondary != nil)
    }
    
    @Test func everyTemplateIsPreviewedWithItsOwnPlaceholder() {
        let (coordinator, _) = make()
        coordinator.handle(.selectTemplate(.tilted))
        #expect(coordinator.canvasScene?.primary?.string == "YOUR HEADLINE")
        
        coordinator.handle(.addTemplate(duplicating: nil))
        #expect(coordinator.canvasScene?.primary?.string == "YOUR HEADLINE")
    }
    
    @Test func aFormatTwoStyleFileMigrates() throws {
        var file = try #require(try JSONSerialization.jsonObject(with: TestResources.data("formats/project-v2.json")) as? [String: Any])
        let sets = file["sets"] as! [[String: Any]]
        let slides = file["slides"] as! [String: Any]
        let order = sets[0]["slideIDs"] as! [String]
        file = [
            "formatVersion": 2,
            "style": file["style"]!,
            "previewSet": sets[0],
            "previewSlides": order.reversed().map { slides[$0]! },
            "sourceLocale": "en-US",
        ]
        
        let data = try JSONSerialization.data(withJSONObject: file)
        let contents = try StylePackage.read(files: ["style.json": data])
        
        #expect(contents.project.devices == [.phone, .pad, .duoOuter])
        #expect(contents.project.slideOrder.map(\.uuidString) == order)
        #expect(contents.project.style.template(.straight)?.layouts[.duoOuter] != nil)
    }
    
    /// Regression test: a number field commits its value when it loses focus, which happened after a click in the
    /// sidebar had already selected another template, so the value landed on that template instead. Selecting now
    /// ends the edit in progress first (`commitPendingEdits`, which the app wires to the field editor).
    @Test func anEditInProgressLandsOnTheTemplateItWasTypedFor() throws {
        let (coordinator, _) = make()
        coordinator.handle(.selectTemplate(.straight))
        
        // What the field would send when it loses focus: its value, for whatever template is selected then.
        var pending: (() -> Void)? = {
            coordinator.handle(.editTemplate("Change Text Layout") { template, device in
                template.layouts[device]?.primary.width = 0.42
            })
        }
        
        coordinator.commitPendingEdits = {
            pending?()
            pending = nil
        }
        
        coordinator.handle(.selectTemplate(.tilted))
        pending?()
        
        #expect(coordinator.project.style.template(.straight)?.layouts[.phone]?.primary.width == 0.42)
        #expect(coordinator.project.style.template(.tilted)?.layouts[.phone]?.primary.width != 0.42)
    }
    
    /// Regression test: the same for the Arrange fields when another element is selected on the canvas.
    @Test func anArrangeEditInProgressLandsOnTheElementItWasTypedFor() throws {
        let (coordinator, _) = make()
        coordinator.handle(.selectTemplate(.straight))
        let canvas = CanvasCoordinator(project: coordinator)
        canvas.handle(.select(.primary))
        let before = coordinator.project.style.template(.straight)?.layouts[.phone]?.secondary.width
        
        var pending: (() -> Void)? = {
            canvas.handle(.setWidth(canvas.selected ?? .device, 500))
        }
        
        coordinator.commitPendingEdits = {
            pending?()
            pending = nil
        }
        
        canvas.handle(.select(.secondary))
        pending?()
        
        #expect(coordinator.project.style.template(.straight)?.layouts[.phone]?.secondary.width == before)
        #expect(coordinator.project.style.template(.straight)?.layouts[.phone]?.primary.width != nil)
    }
    
    // MARK: - Placeholders
    
    /// Regression test: the template editor drew the first slide that used the template, with its text and
    /// screenshot, so editing that slide looked like editing the template.
    @Test func theTemplateEditorShowsItsPlaceholderNotASlide() throws {
        let (coordinator, _) = make()
        coordinator.handle(.setText(.primary, "Read the Land"))
        coordinator.handle(.selectTemplate(.straight))
        
        let scene = try #require(coordinator.canvasScene)
        #expect(scene.primary?.string.lowercased() == TemplatePlaceholder.standard.primary.lowercased())
        #expect(scene.device?.capture == nil)
        
        coordinator.handle(.setPlaceholder(.straight, .primary, "Big Idea"))
        #expect(coordinator.canvasScene?.primary?.string.lowercased() == "big idea")
        #expect(coordinator.project.slides.values.allSatisfy { $0.primary.base.values.contains("Big Idea") == false })
    }
    
    @Test func aNewSlideStartsWithItsTemplatesPlaceholder() throws {
        let (coordinator, _) = make()
        coordinator.handle(.setPlaceholder(.tilted, .primary, "Pin Every Find"))
        coordinator.handle(.setPlaceholder(.tilted, .secondary, "Markers with photos"))
        coordinator.handle(.addSlide(template: .tilted))
        
        let slide = try #require(coordinator.currentSlide)
        #expect(slide.primary.base[coordinator.project.sourceLocale] == "Pin Every Find")
        #expect(slide.secondary.base[coordinator.project.sourceLocale] == "Markers with photos")
        
        // Editing the slide leaves the template's placeholder alone.
        coordinator.handle(.setText(.primary, "Something Else"))
        #expect(coordinator.project.style.template(.tilted)?.placeholder.primary == "Pin Every Find")
    }
    
    @Test func aTemplateSavedWithoutAPlaceholderGetsTheStandardOne() throws {
        var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(Template(name: "Old"))) as! [String: Any]
        json.removeValue(forKey: "placeholder")
        let template = try JSONDecoder().decode(Template.self, from: JSONSerialization.data(withJSONObject: json))
        
        #expect(template.placeholder == .standard)
        #expect(template.name == "Old")
    }
}
