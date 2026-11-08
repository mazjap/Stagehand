import StagehandCore
import StagehandModel
import SwiftUI

/// The selected slide's template, devices, text, extra content and capture for the selected device class and locale,
/// and where the selected canvas element sits.
struct SlideInspector: View {
    @Bindable private var coordinator: ProjectCoordinator
    @Bindable private var canvas: CanvasCoordinator
    private let runs: RunStatusSource?
    @State private var imageElement: ElementID?
    
    init(coordinator: ProjectCoordinator, canvas: CanvasCoordinator, runs: RunStatusSource?) {
        self.coordinator = coordinator
        self.canvas = canvas
        self.runs = runs
        self.imageElement = nil
    }
    
    var body: some View {
        if let slide = coordinator.currentSlide {
            let device = coordinator.currentDeviceClass
            let locale = coordinator.selection.locale
            let source = coordinator.project.sourceLocale
            let resolved = Resolver.layout(for: slide, style: coordinator.project.style, device: device)
            
            InspectorSection("Slide") {
                InspectorRow("Title") {
                    TextField("Title", text: Binding(get: { slide.title }, set: { coordinator.handle(.renameSlide(slide.id, $0)) }))
                        .labelsHidden()
                }
                
                InspectorRow("Devices") {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(coordinator.project.devices, id: \.self) { candidate in
                            Toggle(candidate.displayName, isOn: Binding(get: { slide.isOn(candidate) }, set: { coordinator.handle(.setSlideOn(slide.id, candidate, $0)) }))
                        }
                    }
                }
                
                let others = coordinator.project.sets(containing: slide.id).filter { $0.id != coordinator.selection.setID }
                
                if !others.isEmpty {
                    InspectorRow("Shared") {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Also in \(others.map(\.name).joined(separator: ", "))")
                                .font(.callout)
                            
                            Button("Make Independent Copy") { coordinator.handle(.makeIndependentCopy(slide.id)) }
                                .controlSize(.small)
                        }
                    }
                }
            }
            
            Divider()
            
            InspectorSection("Template · \(device.displayName)") {
                VaryingRow(
                    "Template",
                    isOverridden: slide.template.isOverridden(for: device),
                    deviceClass: device,
                    onOverride: { coordinator.handle(.editSlide("Override Template") { slide, device in slide.template.override(for: device) }) },
                    onRevert: {
                        coordinator.handle(.editSlide("Revert to Shared") { slide, device in
                            slide.setTemplate(slide.template.base, for: device, scope: .override)
                        })
                    }
                ) {
                    Picker("Template", selection: Binding(get: { resolved.template?.id ?? slide.template[device] }, set: { coordinator.handle(.setSlideTemplate($0)) })) {
                        ForEach(coordinator.project.style.templates(for: device)) { template in
                            Text(template.name).tag(template.id)
                        }
                    }
                    .labelsHidden()
                }
                
                if let template = resolved.template {
                    InspectorRow("") {
                        Button("Edit \(template.name) Template") { coordinator.handle(.selectTemplate(template.id)) }
                            .controlSize(.small)
                    }
                }
                
                if resolved.fellBack, coordinator.project.style.template(slide.template[device]) != nil {
                    Text("\(coordinator.project.style.template(slide.template[device])?.name ?? "The template") has no \(device.displayName) layout, so \(resolved.template?.name ?? "another template") is used here.")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            
            Divider()
            
            InspectorSection("Text · \(locale) · \(device.displayName)") {
                ForEach(TextRole.allCases, id: \.self) { role in
                    let text = slide.text(role)
                    let resolvedText = text.text(for: device, locale: locale, source: source)
                    
                    VaryingRow(
                        role.displayName,
                        isOverridden: text.isOverridden(for: device, locale: locale),
                        deviceClass: device,
                        onOverride: { coordinator.handle(.overrideText(role)) },
                        onRevert: { coordinator.handle(.revertText(role)) }
                    ) {
                        VStack(alignment: .leading, spacing: 2) {
                            TextField(role.displayName, text: Binding(get: { resolvedText?.text ?? "" }, set: { coordinator.handle(.setText(role, $0)) }), axis: .vertical)
                                .labelsHidden()
                                .lineLimit(1...4)
                            
                            if resolvedText?.fellBackToSource == true {
                                Label("Showing the \(source) text", systemImage: "globe")
                                    .font(.caption)
                                    .foregroundStyle(.orange)
                            }
                        }
                    }
                }
                
                // The template's extra text elements that show on this class.
                ForEach(extraElements(of: resolved, kind: .text)) { element in
                    InspectorRow(element.name) {
                        TextField(element.name, text: Binding(
                            get: { slide.extraContent[element.id]?.text?.text(for: device, locale: locale, source: source)?.text ?? "" },
                            set: { coordinator.handle(.setExtraText(element.id, $0)) }
                        ), axis: .vertical)
                        .labelsHidden()
                        .lineLimit(1...3)
                    }
                }
            }
            
            Divider()
            
            ArrangeSection(coordinator: coordinator, canvas: canvas)
            
            Divider()
            
            InspectorSection("Device") {
                VaryingRow(
                    "Capture Key",
                    isOverridden: slide.captureKey.isOverridden(for: device),
                    deviceClass: device,
                    onOverride: { coordinator.handle(.editSlide("Override Capture Key") { slide, device in slide.captureKey.override(for: device) }) },
                    onRevert: { coordinator.handle(.editSlide("Revert to Shared") { slide, device in slide.captureKey.revert(device) }) }
                ) {
                    HStack(spacing: 4) {
                        TextField("Capture Key", text: Binding(get: { slide.captureKey[device] }, set: { key in
                            coordinator.handle(.editSlide("Change Capture Key") { slide, device in slide.captureKey.set(key, for: device) })
                        }))
                        .labelsHidden()
                        
                        CaptureKeyMenu(keys: coordinator.captureKeys(on: device), current: slide.captureKey[device]) { key in
                            coordinator.handle(.editSlide("Change Capture Key") { slide, device in slide.captureKey.set(key, for: device) })
                        }
                    }
                }
                
                ForEach(extraElements(of: resolved, kind: .device)) { element in
                    InspectorRow(element.name) {
                        TextField("Capture Key", text: Binding(
                            get: { slide.extraContent[element.id]?.captureKey?[device] ?? "" },
                            set: { coordinator.handle(.setExtraCapture(element.id, $0)) }
                        ))
                        .labelsHidden()
                    }
                }
                
                ForEach(extraElements(of: resolved, kind: .image)) { element in
                    InspectorRow(element.name) {
                        HStack {
                            Text(slide.extraContent[element.id]?.imageName ?? "No image")
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                            
                            Spacer()
                            
                            Button("Choose…") { imageElement = element.id }
                                .controlSize(.small)
                        }
                    }
                }
            }
            .fileImporter(isPresented: Binding(get: { imageElement != nil }, set: { if !$0 { imageElement = nil } }), allowedContentTypes: [.image]) { result in
                if let element = imageElement, case let .success(url) = result, let file = DroppedFile.load(from: [url]).first {
                    coordinator.handle(.setExtraImage(element, file))
                }
                
                imageElement = nil
            }
            
            Divider()
            
            CaptureSection(coordinator: coordinator, runs: runs, slide: slide, device: device)
        } else {
            ContentUnavailableView("No Slide", systemImage: "rectangle.portrait")
        }
    }
    
    // MARK: - Helpers
    
    /// The template's extra elements of a kind that show on this class.
    private func extraElements(of resolved: (template: Template?, layout: TemplateLayout, fellBack: Bool), kind: TemplateElement.Kind) -> [TemplateElement] {
        resolved.template?.elements.filter { $0.kind == kind && resolved.layout.extras[$0.id] != nil } ?? []
    }

}

/// The capture this cell shows, and what can be done with it.
private struct CaptureSection: View {
    @Bindable private var coordinator: ProjectCoordinator
    private let runs: RunStatusSource?
    private let slide: Slide
    private let device: DeviceClass
    
    init(coordinator: ProjectCoordinator, runs: RunStatusSource?, slide: Slide, device: DeviceClass) {
        self.coordinator = coordinator
        self.runs = runs
        self.slide = slide
        self.device = device
    }
    
    var body: some View {
        let address = CaptureAddress(key: slide.captureKey[device], deviceClass: device, locale: coordinator.selection.locale)
        let record = coordinator.document.captures.records[address]
        
        InspectorSection("Capture") {
            if let record {
                InspectorRow("Size") {
                    Text("\(record.pixelWidth) × \(record.pixelHeight)")
                        .monospacedDigit()
                }
                
                InspectorRow("From") {
                    Text(record.source == .runner ? "Capture run" : "Dropped in")
                }
                
                if let shot = record.shot, let runtime = shot.simulatorRuntime {
                    InspectorRow("Simulator") {
                        Text("\(shot.simulatorModel ?? "") · \(runtime)")
                    }
                }
                
                ForEach(record.quirksToReview) { quirk in
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Corrected for \(quirk.id) on a runtime newer than any it was seen on. If it's upside down now, Apple fixed the bug.")
                            .font(.caption)
                            .foregroundStyle(.orange)
                            .fixedSize(horizontal: false, vertical: true)
                        
                        Button("Undo Quirk") { coordinator.handle(.undoQuirk(address, quirkID: quirk.id)) }
                            .controlSize(.small)
                    }
                }
            } else {
                Text("No capture for \(address.key) on \(device.displayName) in \(address.locale). Drop a screenshot on the cell, or run captures.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            
            HStack {
                if let runs, let cell = coordinator.selection.cell {
                    Button("Recapture") { runs.recapture(cell) }
                        .disabled(runs.isRunning)
                }
                
                if record != nil {
                    Button("Remove", role: .destructive) { coordinator.handle(.removeCapture(address)) }
                }
            }
            
            if let runs, let cell = coordinator.selection.cell, case let .failed(message) = runs.status(for: cell) {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// The screenshots there are for a device, by capture key, to point the slide at one. A run keys each screenshot by
/// its test's name for it (like `01-level`), and keys another slide shows are marked.
private struct CaptureKeyMenu: View {
    private let keys: [(key: String, inUse: Bool)]
    private let current: String
    private let onChoose: (String) -> Void
    
    init(keys: [(key: String, inUse: Bool)], current: String, onChoose: @escaping (String) -> Void) {
        self.keys = keys
        self.current = current
        self.onChoose = onChoose
    }
    
    var body: some View {
        Menu {
            if keys.isEmpty {
                Text("No screenshots yet")
            }
            
            ForEach(keys, id: \.key) { entry in
                Button {
                    onChoose(entry.key)
                } label: {
                    if entry.key == current {
                        Label(entry.key, systemImage: "checkmark")
                    } else {
                        Text(entry.inUse ? "\(entry.key) (used)" : entry.key)
                    }
                }
            }
        } label: {
            Image(systemName: "photo.stack")
        }
        .menuIndicator(.hidden)
        .fixedSize()
        .accessibilityLabel("Choose a Screenshot")
        .help("Show one of the screenshots there are for this device")
    }
}

#Preview {
    @Previewable @State var coordinator = ProjectCoordinator(document: ProjectDocument(contents: ProjectContents(project: .fixture())))
    
    ScrollView {
        VStack(alignment: .leading, spacing: 14) {
            SlideInspector(coordinator: coordinator, canvas: CanvasCoordinator(project: coordinator), runs: nil)
        }
        .padding()
    }
    .frame(width: 340, height: 900)
}
