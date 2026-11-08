import StagehandCore
import StagehandModel
import SwiftUI

/// The template set (the style): its colors, background and text styles. Each template's layouts are in the
/// Template inspector, which shows while a template is open.
struct StyleInspector: View {
    @Bindable private var coordinator: ProjectCoordinator
    @State private var newToken = ""
    
    init(coordinator: ProjectCoordinator) {
        self.coordinator = coordinator
    }
    
    private var style: Style {
        coordinator.project.style
    }
    
    private var device: DeviceClass {
        coordinator.currentDeviceClass
    }
    
    var body: some View {
        InspectorSection("Template Set") {
            InspectorRow("Name") {
                TextField("Name", text: Binding(get: { style.name }, set: { name in coordinator.handle(.editStyle("Rename Template Set") { style, _ in style.name = name }) }))
                    .labelsHidden()
            }
            
            LibraryRows(coordinator: coordinator)
        }
        
        Divider()
        
        InspectorSection("Colors") {
            ForEach(style.colors.keys.sorted(), id: \.self) { token in
                InspectorRow(token) {
                    HStack {
                        ColorPicker(token, selection: Binding(get: { style.color(token).color }, set: { color in
                            coordinator.handle(.editStyle("Change Color") { style, _ in style.colors[token] = RGBA(color) })
                        }))
                        .labelsHidden()
                        
                        Text(style.color(token).hex)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                } badge: {
                    Button {
                        coordinator.handle(.editStyle("Remove Color") { style, _ in style.colors[token] = nil })
                    } label: {
                        Image(systemName: "minus.circle")
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("Remove \(token)")
                    .help("Remove \(token)")
                }
            }
            
            InspectorRow("New Token") {
                TextField("Name", text: $newToken)
                    .labelsHidden()
                    .onSubmit(addToken)
            } badge: {
                Button(action: addToken) {
                    Image(systemName: "plus.circle")
                }
                .buttonStyle(.borderless)
                .disabled(newToken.trimmingCharacters(in: .whitespaces).isEmpty)
                .accessibilityLabel("Add Color Token")
            }
        }
        
        Divider()
        
        InspectorSection("Background") {
            FillRows(coordinator: coordinator)
        }
        
        ForEach(TextRole.allCases, id: \.self) { role in
            Divider()
            TextStyleEditor(coordinator: coordinator, role: role)
        }
    }
    
    private func addToken() {
        let token = newToken.trimmingCharacters(in: .whitespaces)
        
        guard !token.isEmpty else {
            return
        }
        
        coordinator.handle(.editStyle("Add Color") { style, _ in style.colors[token] = .white })
        newToken = ""
    }
}

/// Where the template set came from in the library, whether there's a newer version, and saving it back.
private struct LibraryRows: View {
    @Bindable private var coordinator: ProjectCoordinator
    
    init(coordinator: ProjectCoordinator) {
        self.coordinator = coordinator
    }
    
    var body: some View {
        let base = coordinator.project.basedOn
        
        InspectorRow("Library") {
            Text(base.map { "\($0.snapshot.name), version \($0.version)" } ?? "Not in the library")
                .foregroundStyle(base == nil ? .secondary : .primary)
        }
        
        if let update = coordinator.baseUpdate {
            InspectorRow("") {
                VStack(alignment: .leading, spacing: 4) {
                    Label("Base updated to version \(update.version)", systemImage: "arrow.down.circle")
                        .foregroundStyle(.tint)
                    
                    Button("Pull Changes…") { coordinator.handle(.prepareMerge) }
                        .controlSize(.small)
                }
            }
        }
        
        InspectorRow("") {
            Menu("Save to Library") {
                if let base {
                    Button("As Version \(base.version + 1) of \(base.snapshot.name)") {
                        coordinator.handle(.saveStyleToLibrary(asNewVersion: true))
                    }
                }
                
                Button("As a New Template Set") {
                    coordinator.handle(.saveStyleToLibrary(asNewVersion: false))
                }
            }
            .fixedSize()
        }
        
        if let message = coordinator.libraryMessage {
            InspectorRow("") {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// The background fill for the selected class: its kind with the link badge, then its tokens.
private struct FillRows: View {
    @Bindable private var coordinator: ProjectCoordinator
    
    init(coordinator: ProjectCoordinator) {
        self.coordinator = coordinator
    }
    
    var body: some View {
        let device = coordinator.currentDeviceClass
        let background = coordinator.project.style.background
        let fill = background[device]
        let tokens = coordinator.project.style.colors.keys.sorted()
        
        VaryingRow(
            "Fill",
            isOverridden: background.isOverridden(for: device),
            deviceClass: device,
            onOverride: { coordinator.handle(.editStyle("Override Fill") { style, device in style.background.override(for: device) }) },
            onRevert: { coordinator.handle(.editStyle("Revert to Shared") { style, device in style.background.revert(device) }) }
        ) {
            Picker("Kind", selection: Binding(get: { Self.kind(of: fill) }, set: { set(Self.changing(fill, to: $0)) })) {
                Text("Color").tag(0)
                Text("Linear Gradient").tag(1)
                Text("Radial Gradient").tag(2)
            }
            .labelsHidden()
        }
        
        ForEach(Array(fill.tokens.enumerated()), id: \.offset) { index, token in
            InspectorRow(fill.tokens.count == 1 ? "Color" : index == 0 ? "From" : "To") {
                Picker("Color", selection: Binding(get: { token }, set: { set(Self.setting($0, at: index, in: fill)) })) {
                    ForEach(tokens, id: \.self) { Text($0).tag($0) }
                }
                .labelsHidden()
            }
        }
        
        if case let .linearGradient(stops, angle) = fill {
            NumberField("Angle", value: Binding(get: { angle }, set: { set(.linearGradient(tokens: stops, angle: $0)) }), digits: 0, unit: "°")
        }
    }
    
    private func set(_ fill: Fill) {
        coordinator.handle(.editStyle("Change Fill") { style, device in style.background.set(fill, for: device) })
    }
    
    static func kind(of fill: Fill) -> Int {
        switch fill {
        case .color: 0
        case .linearGradient: 1
        case .radialGradient: 2
        }
    }
    
    static func changing(_ fill: Fill, to kind: Int) -> Fill {
        let tokens = fill.tokens
        let pair = tokens.count > 1 ? tokens : tokens + tokens
        
        return switch kind {
        case 0: .color(token: tokens.first ?? "background")
        case 1: .linearGradient(tokens: pair, angle: 0)
        default: .radialGradient(tokens: pair, center: NormPoint(x: 0.5, y: 0.4), radius: 0.9)
        }
    }
    
    static func setting(_ token: String, at index: Int, in fill: Fill) -> Fill {
        var tokens = fill.tokens
        tokens[index] = token
        
        return switch fill {
        case .color: .color(token: token)
        case let .linearGradient(_, angle): .linearGradient(tokens: tokens, angle: angle)
        case let .radialGradient(_, center, radius): .radialGradient(tokens: tokens, center: center, radius: radius)
        }
    }
}

/// One text role's font, size, color, case, tracking and line spacing.
private struct TextStyleEditor: View {
    @Bindable private var coordinator: ProjectCoordinator
    private let role: TextRole
    
    init(coordinator: ProjectCoordinator, role: TextRole) {
        self.coordinator = coordinator
        self.role = role
    }
    
    private var textStyle: TextStyle {
        coordinator.project.style.textStyle(role)
    }
    
    private var device: DeviceClass {
        coordinator.currentDeviceClass
    }
    
    var body: some View {
        InspectorSection("\(role.displayName) Text") {
            row("Font", \.font) { font in
                FontMenu(
                    selection: font.wrappedValue,
                    documentFonts: coordinator.fontNames,
                    families: coordinator.systemFontFamilies,
                    onSelect: { coordinator.handle(.useFont(role, $0)) }
                )
            }
            
            row("Size", \.size) { size in
                // NOTE: - Stored as a fraction of the canvas's width; shown in points on the target the canvas shows.
                SliderField(
                    value: size,
                    in: 0.01...0.2,
                    typedRange: 0.001...1,
                    display: .points(canvasWidth: coordinator.currentCanvasWidth)
                ) { editing in
                    coordinator.handle(editing ? .beginGesture("Change Size") : .endGesture)
                }
                .help("In points on \(coordinator.currentTarget?.name ?? device.displayName), where a point is a pixel of the screenshot")
            }
            
            row("Color", \.colorToken) { token in
                Picker("Color", selection: token) {
                    ForEach(coordinator.project.style.colors.keys.sorted(), id: \.self) { Text($0).tag($0) }
                }
                .labelsHidden()
            }
            
            row("Case", \.letterCase) { letterCase in
                Picker("Case", selection: letterCase) {
                    Text("Aa").tag(LetterCase.asWritten).help("As Written")
                    Text("AA").tag(LetterCase.uppercase).help("Uppercase")
                    Text("aa").tag(LetterCase.lowercase).help("Lowercase")
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
            
            row("Tracking", \.tracking) { tracking in
                SliderField(value: tracking, in: -0.05...0.3) { editing in
                    coordinator.handle(editing ? .beginGesture("Change Tracking") : .endGesture)
                }
            }
            
            row("Line Spacing", \.lineSpacing) { spacing in
                SliderField(value: spacing, in: -0.2...0.6) { editing in
                    coordinator.handle(editing ? .beginGesture("Change Line Spacing") : .endGesture)
                }
            }
        }
    }
    
    private func row<Value, Control: View>(_ label: String, _ keyPath: WritableKeyPath<TextStyle, Varying<Value>>, @ViewBuilder control: (Binding<Value>) -> Control) -> some View {
        let role = role
        let value = textStyle[keyPath: keyPath]
        
        return VaryingRow(
            label,
            isOverridden: value.isOverridden(for: device),
            deviceClass: device,
            onOverride: { coordinator.handle(.editStyle("Override \(label)") { style, device in style.updateTextStyle(role) { $0[keyPath: keyPath].override(for: device) } }) },
            onRevert: { coordinator.handle(.editStyle("Revert to Shared") { style, device in style.updateTextStyle(role) { $0[keyPath: keyPath].revert(device) } }) }
        ) {
            control(Binding {
                value[device]
            } set: { newValue in
                coordinator.handle(.editStyle("Change \(label)") { style, device in style.updateTextStyle(role) { $0[keyPath: keyPath].set(newValue, for: device) } })
            })
        }
    }
}

#Preview {
    @Previewable @State var coordinator = ProjectCoordinator(document: ProjectDocument(contents: ProjectContents(project: .fixture())))
    
    ScrollView {
        VStack(alignment: .leading, spacing: 14) {
            StyleInspector(coordinator: coordinator)
        }
        .padding()
    }
    .frame(width: 340, height: 900)
}
