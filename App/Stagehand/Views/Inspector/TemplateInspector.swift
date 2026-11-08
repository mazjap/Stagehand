import StagehandCore
import StagehandModel
import SwiftUI

/// The template open in the template editor: its name, its layout on each of the project's devices, the elements it
/// shows, and the selected element's placement, text settings and bezel. Every slide using the template follows.
struct TemplateInspector: View {
    @Bindable private var coordinator: ProjectCoordinator
    @Bindable private var canvas: CanvasCoordinator
    @State private var bezelUpdate: BezelUpdate?
    
    init(coordinator: ProjectCoordinator, canvas: CanvasCoordinator) {
        self.coordinator = coordinator
        self.canvas = canvas
        self.bezelUpdate = nil
    }
    
    var body: some View {
        if let template = coordinator.currentTemplate {
            let device = coordinator.currentDeviceClass
            
            InspectorSection("Template") {
                InspectorRow("Name") {
                    TextField("Name", text: Binding(get: { template.name }, set: { coordinator.handle(.renameTemplate(template.id, $0)) }))
                        .labelsHidden()
                }
                
                InspectorRow("Used By") {
                    let count = coordinator.slides(using: template.id).count
                    Text(count == 1 ? "1 slide" : "\(count) slides")
                        .foregroundStyle(.secondary)
                }
                
                InspectorRow("") {
                    HStack {
                        Button("New Slide") { coordinator.handle(.addSlide(template: template.id)) }
                        Button("Duplicate") { coordinator.handle(.addTemplate(duplicating: template.id)) }
                    }
                    .controlSize(.small)
                }
            }
            
            Divider()
            
            InspectorSection("Placeholder Text") {
                ForEach(TextRole.allCases, id: \.self) { role in
                    InspectorRow(role.displayName) {
                        TextField(role.displayName, text: Binding(get: { template.placeholder.text(role) }, set: { coordinator.handle(.setPlaceholder(template.id, role, $0)) }), axis: .vertical)
                            .labelsHidden()
                    }
                }
                
                Text("Shown here in place of a slide's text, and what a new slide starts with. Slides' own text never changes it.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                
                let overflowing = coordinator.placeholderOverflow(template.id, targetID: coordinator.selection.targetID)
                
                if !overflowing.isEmpty {
                    Label("The \(overflowing.map { $0.displayName.lowercased() }.joined(separator: " and ")) placeholder is longer than fits at the size slides use on \(device.displayName). Slides with text this long shrink; shorten it, or make the text smaller in the Template Set.", systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            
            Divider()
            
            InspectorSection("Layout") {
                InspectorRow("Device") {
                    Picker("Device", selection: Binding(get: { device }, set: { select($0) })) {
                        ForEach(coordinator.project.devices, id: \.self) { candidate in
                            Text(template.layouts[candidate] == nil ? "\(candidate.displayName) (none yet)" : candidate.displayName).tag(candidate)
                        }
                    }
                    .labelsHidden()
                }
                
                if template.layouts[device] == nil {
                    MissingLayoutRows(template: template, device: device) { source in
                        coordinator.handle(.addTemplateLayout(device, from: source))
                    }
                }
            }
            
            if let layout = template.layouts[device] {
                Divider()
                
                ElementsSection(coordinator: coordinator, canvas: canvas, template: template, layout: layout)
                
                Divider()
                
                ArrangeSection(coordinator: coordinator, canvas: canvas)
                
                selectedElementRows(template: template, layout: layout)
                
                Divider()
                
                InspectorRow("") {
                    Button("Remove \(device.displayName) Layout", role: .destructive) { coordinator.handle(.removeTemplateLayout(device)) }
                        .controlSize(.small)
                }
            }
        } else {
            ContentUnavailableView("No Template", systemImage: "rectangle.on.rectangle", description: Text("Choose a template in the sidebar."))
        }
    }
    
    // MARK: - Subviews
    
    /// Text settings for a selected text element, or the bezel and glow for a selected device.
    @ViewBuilder
    private func selectedElementRows(template: Template, layout: TemplateLayout) -> some View {
        let element = canvas.selected ?? .device
        
        switch layout.placement(for: element) {
        case let .text(placement)?:
            Divider()
            
            InspectorSection("Text Box") {
                if case let .extra(id) = element, let definition = template.element(id) {
                    InspectorRow("Style") {
                        Picker("Style", selection: Binding(get: { definition.textStyle }, set: { style in
                            coordinator.handle(.editTemplate("Change Text Style") { template, _ in
                                if let index = template.elements.firstIndex(where: { $0.id == id }) {
                                    template.elements[index].textStyle = style
                                }
                            })
                        })) {
                            ForEach(TextRole.allCases, id: \.self) { Text($0.displayName).tag($0) }
                        }
                        .labelsHidden()
                    }
                }
                
                TextPlacementRows(placement: placement) { edited in
                    coordinator.handle(.editTemplate("Change Text Layout") { template, device in
                        template.layouts[device]?.setPlacement(.text(edited), for: element)
                    })
                }
            }
        case let .device(placement)?:
            Divider()
            
            InspectorSection("Device") {
                if case let .pinned(id) = placement.bezel, let newer = coordinator.bezels.newerBezel(than: id), let pinned = coordinator.bezels.bezels[id] {
                    NewerBezelNotice(pinned: pinned, newer: newer) {
                        bezelUpdate = BezelUpdate(element: element, pinned: pinned, newer: newer)
                    }
                }
                
                DevicePlacementRows(
                    placement: placement,
                    deviceClass: coordinator.currentDeviceClass,
                    tokens: coordinator.project.style.colors.keys.sorted(),
                    bezels: coordinator.bezels,
                    onBezel: { coordinator.handle(.setBezel(element, $0)) }
                ) { edited in
                    coordinator.handle(.editTemplate("Change Device") { template, device in
                        template.layouts[device]?.setPlacement(.device(edited), for: element)
                    })
                }
            }
            .sheet(item: $bezelUpdate) { update in
                UpdateBezelSheet(update: update, images: coordinator.imageStore) {
                    coordinator.handle(.setBezel(update.element, .pinned(update.newer.id)))
                    bezelUpdate = nil
                } onDismiss: {
                    bezelUpdate = nil
                }
            }
        case .image?, nil:
            EmptyView()
        }
    }
    
    private func select(_ device: DeviceClass) {
        if let target = coordinator.project.targets.first(where: { DeviceTable.standard.target(id: $0)?.deviceClass == device }) {
            coordinator.handle(.selectTarget(target))
        }
    }
}

/// A class the template has no layout for: start from another class's (the most alike first), or blank.
private struct MissingLayoutRows: View {
    private let template: Template
    private let device: DeviceClass
    private let onAdd: (DeviceClass?) -> Void
    
    init(template: Template, device: DeviceClass, onAdd: @escaping (DeviceClass?) -> Void) {
        self.template = template
        self.device = device
        self.onAdd = onAdd
    }
    
    var body: some View {
        let sources = Template.similarClasses(to: device).filter { template.layouts[$0] != nil }
        
        VStack(alignment: .leading, spacing: 8) {
            Text("No \(device.displayName) layout yet. Slides using \(template.name) use another template on \(device.displayName) until it has one.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            
            ForEach(sources, id: \.self) { source in
                Button("Start from \(source.displayName)'s Layout") { onAdd(source) }
            }
            
            Button("Start Blank") { onAdd(nil) }
        }
    }
}

/// The standard elements (shown or hidden on this class) and the extra ones (placed on this class or not).
private struct ElementsSection: View {
    @Bindable private var coordinator: ProjectCoordinator
    @Bindable private var canvas: CanvasCoordinator
    private let template: Template
    private let layout: TemplateLayout
    
    init(coordinator: ProjectCoordinator, canvas: CanvasCoordinator, template: Template, layout: TemplateLayout) {
        self.coordinator = coordinator
        self.canvas = canvas
        self.template = template
        self.layout = layout
    }
    
    var body: some View {
        InspectorSection("Elements · \(coordinator.currentDeviceClass.displayName)") {
            ForEach(StandardElement.allCases, id: \.self) { element in
                Toggle(element.displayName, isOn: Binding(get: { !layout.isHidden(element) }, set: { coordinator.handle(.setElementShown(element.ref, $0)) }))
            }
            
            ForEach(template.elements) { element in
                HStack {
                    Toggle(isOn: Binding(get: { layout.extras[element.id] != nil }, set: { coordinator.handle(.setElementShown(.extra(element.id), $0)) })) {
                        TextField("Name", text: Binding(get: { element.name }, set: { name in
                            coordinator.handle(.editTemplate("Rename Element") { template, _ in
                                if let index = template.elements.firstIndex(where: { $0.id == element.id }) {
                                    template.elements[index].name = name
                                }
                            })
                        }))
                        .textFieldStyle(.plain)
                    }
                    
                    Text(element.kind.displayName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    Button {
                        coordinator.handle(.removeElement(element.id))
                    } label: {
                        Image(systemName: "minus.circle")
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("Remove \(element.name)")
                    .help("Removes it from every device, and its content from every slide")
                }
            }
            
            Menu {
                ForEach(TemplateElement.Kind.allCases, id: \.self) { kind in
                    Button(kind.displayName) { coordinator.handle(.addElement(kind)) }
                }
            } label: {
                Label("Add Element", systemImage: "plus")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
    }
}

struct TextPlacementRows: View {
    private let placement: TextPlacement
    private let onChange: (TextPlacement) -> Void
    
    init(placement: TextPlacement, onChange: @escaping (TextPlacement) -> Void) {
        self.placement = placement
        self.onChange = onChange
    }
    
    var body: some View {
        InspectorRow("Alignment") {
            Picker("Alignment", selection: binding(\.alignment)) {
                Image(systemName: "text.alignleft").tag(TextAlign.leading).accessibilityLabel("Leading")
                Image(systemName: "text.aligncenter").tag(TextAlign.center).accessibilityLabel("Center")
                Image(systemName: "text.alignright").tag(TextAlign.trailing).accessibilityLabel("Trailing")
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        }
        
        InspectorRow("Vertical") {
            Picker("Vertical", selection: binding(\.verticalAlignment)) {
                Text("Top").tag(VerticalAlign.top)
                Text("Middle").tag(VerticalAlign.center)
                Text("Bottom").tag(VerticalAlign.bottom)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        }
        
        InspectorRow("Lines") {
            Stepper(value: binding(\.lineLimit), in: 1...6) {
                Text("\(placement.lineLimit)")
                    .monospacedDigit()
            }
        }
    }
    
    private func binding<T>(_ keyPath: WritableKeyPath<TextPlacement, T>) -> Binding<T> {
        Binding {
            placement[keyPath: keyPath]
        } set: { value in
            var edited = placement
            edited[keyPath: keyPath] = value
            onChange(edited)
        }
    }
}

/// A device's bezel (this class's bezels, newest first), corners without one, and glow.
struct DevicePlacementRows: View {
    private let placement: DevicePlacement
    private let deviceClass: DeviceClass
    private let tokens: [String]
    private let bezels: BezelCatalog
    private let onBezel: (BezelChoice) -> Void
    private let onChange: (DevicePlacement) -> Void
    
    init(
        placement: DevicePlacement,
        deviceClass: DeviceClass,
        tokens: [String],
        bezels: BezelCatalog,
        onBezel: @escaping (BezelChoice) -> Void,
        onChange: @escaping (DevicePlacement) -> Void
    ) {
        self.placement = placement
        self.deviceClass = deviceClass
        self.tokens = tokens
        self.bezels = bezels
        self.onBezel = onBezel
        self.onChange = onChange
    }
    
    var body: some View {
        let choices = bezels.bezels.values
            .filter { $0.deviceClass == deviceClass }
            .sorted { ($0.generation ?? 0, $0.displayName) > ($1.generation ?? 0, $1.displayName) }
        
        InspectorRow("Bezel") {
            Picker("Bezel", selection: Binding(get: { placement.bezel }, set: { onBezel($0) })) {
                Text("Library Default").tag(BezelChoice.matchTarget)
                Text("None").tag(BezelChoice.none)
                
                if !choices.isEmpty {
                    Divider()
                }
                
                ForEach(choices) { bezel in
                    Text(bezel.displayName).tag(BezelChoice.pinned(bezel.id))
                }
            }
            .labelsHidden()
        }
        
        if choices.isEmpty, placement.bezel != .none {
            Text("No \(deviceClass.displayName) bezels in the library yet. Download them in the Library window (Window › Library).")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        
        if placement.bezel == .none {
            InspectorRow("Corners") {
                SliderField(value: binding(\.bareCornerRadius), in: 0...0.3)
            }
        }
        
        InspectorRow("Glow") {
            Toggle("Glow", isOn: Binding(get: { placement.glow != nil }, set: { on in
                var edited = placement
                edited.glow = on ? Glow(colorToken: tokens.first { $0 == "glow" } ?? tokens.first ?? "glow") : nil
                onChange(edited)
            }))
            .labelsHidden()
            .toggleStyle(.switch)
            .controlSize(.small)
        }
        
        if let glow = placement.glow {
            InspectorRow("Glow Color") {
                Picker("Glow Color", selection: glowBinding(glow, \.colorToken)) {
                    ForEach(tokens, id: \.self) { Text($0).tag($0) }
                }
                .labelsHidden()
            }
            
            InspectorRow("Blur") {
                SliderField(value: glowBinding(glow, \.blur), in: 0...0.3)
            }
            
            InspectorRow("Spread") {
                SliderField(value: glowBinding(glow, \.spread), in: 0.8...1.4, digits: 0)
            }
            
            InspectorRow("Opacity") {
                SliderField(value: glowBinding(glow, \.opacity), in: 0...1, digits: 0)
            }
        }
    }
    
    private func binding<T>(_ keyPath: WritableKeyPath<DevicePlacement, T>) -> Binding<T> {
        Binding {
            placement[keyPath: keyPath]
        } set: { value in
            var edited = placement
            edited[keyPath: keyPath] = value
            onChange(edited)
        }
    }
    
    private func glowBinding<T>(_ glow: Glow, _ keyPath: WritableKeyPath<Glow, T>) -> Binding<T> {
        Binding {
            glow[keyPath: keyPath]
        } set: { value in
            var edited = placement
            edited.glow?[keyPath: keyPath] = value
            onChange(edited)
        }
    }
}

// MARK: - Updating Bezels

/// A pinned bezel and the newer one offered in its place.
struct BezelUpdate: Identifiable {
    var element: ElementRef
    var pinned: BezelInfo
    var newer: BezelInfo
    
    var id: BezelID {
        newer.id
    }
}

/// Says a newer bezel is available. Nothing changes until it's updated by hand.
private struct NewerBezelNotice: View {
    private let pinned: BezelInfo
    private let newer: BezelInfo
    private let onUpdate: () -> Void
    
    init(pinned: BezelInfo, newer: BezelInfo, onUpdate: @escaping () -> Void) {
        self.pinned = pinned
        self.newer = newer
        self.onUpdate = onUpdate
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Newer bezel available", systemImage: "sparkles")
                .font(.callout.weight(.medium))
            
            Text("\(newer.displayName) is in the library. This template keeps \(pinned.displayName) until you update it.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            
            Button("Update Bezel…", action: onUpdate)
                .controlSize(.small)
        }
        .padding(8)
        .background(.blue.opacity(0.1), in: RoundedRectangle(cornerRadius: 6))
    }
}

/// The pinned bezel and the newer one side by side, with what changes between them, before switching.
struct UpdateBezelSheet: View {
    private let update: BezelUpdate
    private let images: ImageStore
    private let onConfirm: () -> Void
    private let onDismiss: () -> Void
    
    init(update: BezelUpdate, images: ImageStore, onConfirm: @escaping () -> Void, onDismiss: @escaping () -> Void) {
        self.update = update
        self.images = images
        self.onConfirm = onConfirm
        self.onDismiss = onDismiss
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Update Bezel")
                .font(.title2.bold())
            
            HStack(alignment: .top, spacing: 24) {
                column("Now", update.pinned)
                
                Image(systemName: "arrow.right")
                    .font(.title)
                    .foregroundStyle(.secondary)
                    .frame(maxHeight: .infinity)
                    .accessibilityHidden(true)
                
                column("Newer", update.newer)
            }
            .frame(height: 280)
            
            ForEach(update.pinned.changes(to: update.newer), id: \.self) { change in
                Label(Self.warning(change), systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
            
            Text("Every slide using this template's layout changes. The device keeps its width and position, so check the layout after updating.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            
            HStack {
                Spacer()
                
                Button("Cancel", role: .cancel, action: onDismiss)
                    .keyboardShortcut(.cancelAction)
                
                Button("Update", action: onConfirm)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 520)
    }
    
    private func column(_ title: String, _ bezel: BezelInfo) -> some View {
        VStack(spacing: 8) {
            Text(title)
                .font(.headline)
            
            if let image = images.image(bezel.imageRef) {
                Image(decorative: image, scale: 1)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else {
                RoundedRectangle(cornerRadius: 12)
                    .fill(.quaternary)
            }
            
            Text(bezel.displayName)
                .font(.caption)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }
    
    private static func warning(_ change: BezelInfo.Change) -> String {
        switch change {
        case .screenShape: "The screen's shape changes, so captures from the old size won't fill it the same way."
        case .frameSize: "The frame around the screen is a different size, so the device will look larger or smaller at the same width."
        }
    }
}

#Preview {
    @Previewable @State var coordinator = ProjectCoordinator(document: ProjectDocument(contents: ProjectContents(project: .fixture())))
    
    ScrollView {
        VStack(alignment: .leading, spacing: 14) {
            TemplateInspector(coordinator: coordinator, canvas: CanvasCoordinator(project: coordinator))
        }
        .padding()
    }
    .frame(width: 340, height: 900)
    .onAppear { coordinator.handle(.selectTemplate(.straight)) }
}
