import StagehandCore
import StagehandModel
import SwiftUI

/// Where the selected canvas element sits: which of its points is placed, that point's position, and its size.
///
/// In the template editor this edits the template. On a slide, an element that follows its template is locked: the
/// section says so, with Detach This Slide and Edit Template; a detached one has Reset to Template.
struct ArrangeSection: View {
    @Bindable private var coordinator: ProjectCoordinator
    @Bindable private var canvas: CanvasCoordinator
    
    init(coordinator: ProjectCoordinator, canvas: CanvasCoordinator) {
        self.coordinator = coordinator
        self.canvas = canvas
    }
    
    var body: some View {
        let elements = availableElements
        
        InspectorSection("Arrange") {
            InspectorRow("Element") {
                Picker("Element", selection: Binding(get: { canvas.selected ?? .device }, set: { canvas.handle(.select($0)) })) {
                    ForEach(elements, id: \.ref) { element in
                        Text(element.name).tag(element.ref)
                    }
                }
                .labelsHidden()
            }
            
            if let arrangement = canvas.arrangement {
                let element = arrangement.element
                let isLocked = canvas.isLocked(element)
                
                if isLocked {
                    lockedNotice(element)
                }
                
                Group {
                    InspectorRow("Anchor") {
                        HStack(alignment: .top, spacing: 10) {
                            AnchorGrid(selection: arrangement.anchor) { canvas.handle(.setAnchor(element, $0)) }
                            
                            Text(arrangement.anchor.displayName)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    
                    PairField(
                        "Position",
                        "X", Binding(get: { arrangement.point.x }, set: { canvas.handle(.setPosition(element, CGPoint(x: $0, y: arrangement.point.y))) }),
                        "Y", Binding(get: { arrangement.point.y }, set: { canvas.handle(.setPosition(element, CGPoint(x: arrangement.point.x, y: $0))) })
                    )
                    
                    InspectorRow("Size") {
                        HStack(spacing: 6) {
                            HStack(spacing: 3) {
                                Text("W")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                
                                TextField("Width", value: Binding<Double>(get: { arrangement.size.width }, set: { canvas.handle(.setWidth(element, $0)) }), format: .number.precision(.fractionLength(0)))
                                    .labelsHidden()
                                    .multilineTextAlignment(.trailing)
                                    .monospacedDigit()
                            }
                            .frame(maxWidth: .infinity)
                            
                            Text("H \(Int(arrangement.size.height.rounded()))")
                                .font(.caption)
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .help(arrangement.rotation == nil ? "Follows the font size and line limit" : "Follows the width and the element's shape")
                        }
                    }
                    
                    if let rotation = arrangement.rotation {
                        NumberField("Rotation", value: Binding(get: { rotation }, set: { canvas.handle(.setRotation(element, $0)) }), digits: 1, unit: "°")
                    }
                }
                .disabled(isLocked)
                
                Text(caption(for: element, isLocked: isLocked))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                
                if !coordinator.isEditingTemplate, coordinator.currentSlide?.isDetached(element, on: coordinator.currentDeviceClass) == true {
                    InspectorRow("") {
                        Button("Reset to Template") { coordinator.handle(.reattach(element)) }
                    }
                }
            }
        }
    }
    
    // MARK: - Subviews
    
    private func lockedNotice(_ element: ElementRef) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Follows the \(templateName) template", systemImage: "lock.fill")
                .font(.callout.weight(.medium))
            
            Text("Moving it on this slide detaches it, so only this slide stops following the template on \(coordinator.currentDeviceClass.displayName).")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            
            HStack {
                Button("Edit Template") {
                    if let template = currentTemplateID {
                        coordinator.handle(.selectTemplate(template))
                    }
                }
                
                Button("Detach This Slide") { coordinator.handle(.detach(element)) }
            }
            .controlSize(.small)
        }
        .padding(8)
        .background(.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 6))
    }
    
    // MARK: - Helpers
    
    private struct ElementChoice {
        var ref: ElementRef
        var name: String
    }
    
    /// The standard elements this layout shows, then its extra ones.
    private var availableElements: [ElementChoice] {
        let device = coordinator.currentDeviceClass
        let template = coordinator.currentTemplate ?? coordinator.currentSlide.flatMap { Resolver.layout(for: $0, style: coordinator.project.style, device: device).template }
        let layout = template?.layouts[device]
        let standard = StandardElement.allCases
            .filter { layout?.isHidden($0) != true }
            .map { ElementChoice(ref: $0.ref, name: $0.displayName) }
        let extras = (template?.elements ?? [])
            .filter { layout?.extras[$0.id] != nil }
            .map { ElementChoice(ref: .extra($0.id), name: $0.name) }
        return standard + extras
    }
    
    private var currentTemplateID: TemplateID? {
        let device = coordinator.currentDeviceClass
        return coordinator.currentSlide.flatMap { Resolver.layout(for: $0, style: coordinator.project.style, device: device).template?.id }
    }
    
    private var templateName: String {
        currentTemplateID.flatMap(coordinator.project.style.template)?.name ?? "slide's"
    }
    
    private func caption(for element: ElementRef, isLocked: Bool) -> String {
        let device = coordinator.currentDeviceClass.displayName
        
        if coordinator.isEditingTemplate {
            return "In pixels of this target. This is the template's \(device) layout: every slide using it moves too."
        }
        
        if isLocked {
            return "In pixels of this target."
        }
        
        return "In pixels of this target. This slide places it on its own on \(device); Reset to Template puts it back."
    }
}

#Preview {
    @Previewable @State var coordinator = ProjectCoordinator(document: ProjectDocument(contents: ProjectContents(project: .fixture())))
    
    ScrollView {
        ArrangeSection(coordinator: coordinator, canvas: CanvasCoordinator(project: coordinator))
            .padding()
    }
    .frame(width: 340, height: 500)
}
