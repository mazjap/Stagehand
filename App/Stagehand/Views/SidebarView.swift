import StagehandCore
import StagehandModel
import SwiftUI

/// The template set's templates, the current lineup's slides in order, the Drafts tray, and the lineups (the App Store
/// page and custom product pages). Templates drag onto the slide list (or the contact sheet) to make slides.
struct SidebarView: View {
    @Bindable private var coordinator: ProjectCoordinator
    
    init(coordinator: ProjectCoordinator) {
        self.coordinator = coordinator
    }
    
    var body: some View {
        List {
            templatesSection
            slidesSection
            draftsSection
            lineupsSection
        }
    }
    
    // MARK: - Sections
    
    private var templatesSection: some View {
        Section("Templates") {
            ForEach(coordinator.project.style.templates) { template in
                TemplateRow(
                    template: template,
                    devices: coordinator.project.devices,
                    isSelected: template.id == coordinator.selection.templateID
                )
                .contentShape(Rectangle())
                .onTapGesture { coordinator.handle(.selectTemplate(template.id)) }
                .pointerHoverEffect()
                .draggable(TemplateDrag.payload(template.id))
                .contextMenu {
                    Button("New Slide from Template") { coordinator.handle(.addSlide(template: template.id)) }
                    Button("Duplicate Template") { coordinator.handle(.addTemplate(duplicating: template.id)) }
                    Divider()
                    Button("Delete Template", role: .destructive) { coordinator.handle(.deleteTemplate(template.id)) }
                        .disabled(coordinator.project.style.templates.count == 1)
                }
            }
            .onMove { offsets, destination in
                coordinator.handle(.moveTemplates(offsets, to: destination))
            }
            
            Button {
                coordinator.handle(.addTemplate(duplicating: nil))
            } label: {
                Label("New Template", systemImage: "plus")
            }
            .buttonStyle(.borderless)
        }
    }
    
    @ViewBuilder
    private var slidesSection: some View {
        if let set = coordinator.currentSet {
            Section(set.id == ShotSet.mainID ? "Slides" : "Slides in \(set.name)") {
                if coordinator.contactSheet.rows.isEmpty {
                    Label("Drag a template here", systemImage: "square.and.arrow.down")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        .dropDestination(for: String.self) { items, _ in
                            _ = addSlides(from: items, at: 0)
                        }
                }
                
                ForEach(coordinator.contactSheet.rows) { row in
                    SlideRow(
                        row: row,
                        isSelected: row.slideID == coordinator.selection.slideID && !coordinator.isEditingTemplate,
                        detachedOn: detachedDevices(row.slideID)
                    )
                    .contentShape(Rectangle())
                    .onTapGesture { select(row.slideID) }
                    .pointerHoverEffect()
                    .contextMenu {
                        Button("Duplicate Slide") {
                            select(row.slideID)
                            coordinator.handle(.duplicateSlide)
                        }
                        
                        if !row.alsoIn.isEmpty {
                            Button("Make Independent Copy") { coordinator.handle(.makeIndependentCopy(row.slideID)) }
                        }
                        
                        Divider()
                        Button("Move to Drafts") { coordinator.handle(.removeSlideFromSet(row.slideID)) }
                    }
                }
                .onMove { offsets, destination in
                    coordinator.handle(.moveSlides(offsets, to: destination))
                }
                .dropDestination(for: String.self) { items, index in
                    _ = addSlides(from: items, at: index)
                }
                
                Menu {
                    ForEach(coordinator.project.style.templates) { template in
                        Button(template.name) { coordinator.handle(.addSlide(template: template.id)) }
                    }
                } label: {
                    Label("New Slide", systemImage: "plus")
                }
                .menuStyle(.borderlessButton)
            }
        }
    }
    
    @ViewBuilder
    private var draftsSection: some View {
        let drafts = coordinator.project.drafts
        
        if !drafts.isEmpty {
            Section("Drafts") {
                ForEach(drafts) { slide in
                    Text(slide.title)
                        .foregroundStyle(.secondary)
                        .contextMenu {
                            Button("Add to \(coordinator.currentSet?.name ?? "Slides")") { coordinator.handle(.addDraftToSet(slide.id)) }
                            Button("Delete", role: .destructive) { coordinator.handle(.deleteDraft(slide.id)) }
                        }
                }
            }
        }
    }
    
    private var lineupsSection: some View {
        Section("Lineups") {
            ForEach(coordinator.project.sets) { set in
                LineupRow(set: set, isSelected: set.id == coordinator.selection.setID)
                    .contentShape(Rectangle())
                    .onTapGesture { coordinator.handle(.selectSet(set.id)) }
                    .pointerHoverEffect()
                    .contextMenu {
                        if set.id != ShotSet.mainID {
                            Button("Delete Custom Product Page", role: .destructive) { coordinator.handle(.deleteSet(set.id)) }
                        }
                    }
            }
            
            Button {
                coordinator.handle(.addProductPage(name: "Custom Product Page \(coordinator.project.productPages.count + 1)"))
            } label: {
                Label("Add Custom Product Page", systemImage: "plus")
            }
            .buttonStyle(.borderless)
        }
    }
    
    // MARK: - Helpers
    
    private func select(_ slideID: Slide.ID) {
        guard let set = coordinator.currentSet, let target = coordinator.selection.targetID ?? set.targets.first else {
            return
        }
        
        let mode = coordinator.mode
        coordinator.handle(.selectCell(CellID(setID: set.id, slideID: slideID, targetID: target)))
        
        if mode == .contactSheet {
            coordinator.handle(.showContactSheet)
        }
    }
    
    private func addSlides(from items: [String], at index: Int) -> Bool {
        let templates = items.compactMap(TemplateDrag.templateID)
        
        for (offset, template) in templates.enumerated() {
            coordinator.handle(.addSlide(template: template, at: index + offset))
        }
        
        return !templates.isEmpty
    }
    
    private func detachedDevices(_ slideID: Slide.ID) -> [DeviceClass] {
        let detachments = coordinator.project.slides[slideID]?.detachments ?? [:]
        return DeviceClass.allCases.filter { detachments[$0] != nil }
    }
}

/// A template dragged from the sidebar, as a string, so any drop destination for text can take it.
enum TemplateDrag {
    private static let prefix = "stagehand-template:"
    
    static func payload(_ id: TemplateID) -> String {
        prefix + id.rawValue
    }
    
    static func templateID(_ payload: String) -> TemplateID? {
        payload.hasPrefix(prefix) ? TemplateID(rawValue: String(payload.dropFirst(prefix.count))) : nil
    }
}

private struct TemplateRow: View {
    private let template: Template
    private let devices: [DeviceClass]
    private let isSelected: Bool
    
    init(template: Template, devices: [DeviceClass], isSelected: Bool) {
        self.template = template
        self.devices = devices
        self.isSelected = isSelected
    }
    
    var body: some View {
        let missing = devices.filter { template.layouts[$0] == nil }
        
        HStack {
            Label(template.name, systemImage: "rectangle.on.rectangle")
            
            Spacer()
            
            if !missing.isEmpty {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.yellow)
                    .help("No layout for \(missing.map(\.displayName).joined(separator: ", ")) yet")
                    .accessibilityLabel("Missing layouts")
            }
        }
        .fontWeight(isSelected ? .semibold : .regular)
        .foregroundStyle(isSelected ? AnyShapeStyle(.tint) : AnyShapeStyle(.primary))
    }
}

private struct LineupRow: View {
    private let set: ShotSet
    private let isSelected: Bool
    
    init(set: ShotSet, isSelected: Bool) {
        self.set = set
        self.isSelected = isSelected
    }
    
    var body: some View {
        HStack {
            Label(set.name, systemImage: set.id == ShotSet.mainID ? "app.badge" : "rectangle.stack")
            Spacer()
            Text("\(set.slideIDs.count)")
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .fontWeight(isSelected ? .semibold : .regular)
        .foregroundStyle(isSelected ? AnyShapeStyle(.tint) : AnyShapeStyle(.primary))
    }
}

private struct SlideRow: View {
    private let row: ContactSheetState.Row
    private let isSelected: Bool
    private let detachedOn: [DeviceClass]
    
    init(row: ContactSheetState.Row, isSelected: Bool, detachedOn: [DeviceClass]) {
        self.row = row
        self.isSelected = isSelected
        self.detachedOn = detachedOn
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(row.number). \(row.title)")
                .fontWeight(isSelected ? .semibold : .regular)
            
            if !row.alsoIn.isEmpty {
                Text("Also in \(row.alsoIn.joined(separator: ", "))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            if !detachedOn.isEmpty {
                Label("Detached on \(detachedOn.map(\.displayName).joined(separator: ", "))", systemImage: "link.badge.plus")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
        .foregroundStyle(isSelected ? AnyShapeStyle(.tint) : AnyShapeStyle(.primary))
    }
}

#Preview {
    @Previewable @State var coordinator = ProjectCoordinator(document: ProjectDocument(contents: ProjectContents(project: .fixture())))
    
    SidebarView(coordinator: coordinator)
        .frame(width: 260, height: 600)
}
