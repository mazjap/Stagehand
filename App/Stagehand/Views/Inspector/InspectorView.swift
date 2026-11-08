import StagehandCore
import SwiftUI

/// The selected slide (or, in the template editor, the template), the template set, and the project.
struct InspectorView: View {
    enum Tab: String, CaseIterable, Identifiable {
        case slide = "Slide"
        case template = "Template"
        case templateSet = "Template Set"
        case project = "Project"
        
        var id: String {
            rawValue
        }
    }
    
    @Bindable private var coordinator: ProjectCoordinator
    @Bindable private var canvas: CanvasCoordinator
    private let runs: RunStatusSource?
    @State private var tab: Tab
    
    init(coordinator: ProjectCoordinator, canvas: CanvasCoordinator, runs: RunStatusSource?) {
        self.coordinator = coordinator
        self.canvas = canvas
        self.runs = runs
        self.tab = coordinator.isEditingTemplate ? .template : .slide
    }
    
    /// The first tab follows what the canvas edits: the template in the template editor, or else the slide.
    private var tabs: [Tab] {
        [coordinator.isEditingTemplate ? .template : .slide, .templateSet, .project]
    }
    
    var body: some View {
        VStack(spacing: 0) {
            Picker("Inspector", selection: $tab) {
                ForEach(tabs) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(10)
            
            Divider()
            
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    switch tab {
                    case .slide: SlideInspector(coordinator: coordinator, canvas: canvas, runs: runs)
                    case .template: TemplateInspector(coordinator: coordinator, canvas: canvas)
                    case .templateSet: StyleInspector(coordinator: coordinator)
                    case .project: ProjectInspector(coordinator: coordinator)
                    }
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .onChange(of: coordinator.isEditingTemplate) { _, isEditingTemplate in
            if tab == .slide || tab == .template {
                tab = isEditingTemplate ? .template : .slide
            } else if isEditingTemplate {
                tab = .template
            }
        }
    }
}

#Preview {
    @Previewable @State var coordinator = ProjectCoordinator(document: ProjectDocument(contents: ProjectContents(project: .fixture())))
    
    InspectorView(coordinator: coordinator, canvas: CanvasCoordinator(project: coordinator), runs: nil)
        .frame(width: 340, height: 800)
}
