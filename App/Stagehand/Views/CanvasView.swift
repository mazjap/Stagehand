import StagehandCore
import StagehandModel
import SwiftUI

/// One slide (or, in the template editor, one template) on one target. Drag an element to move it, pinch or rotate
/// on a trackpad, and use the arrow keys (with Shift for 10×) to nudge whatever's selected. Scroll to pan, and zoom
/// with ⌘-scroll, ⌘+ and ⌘− (⌘0 fits the canvas again); zooming out leaves room to drag things past the canvas.
///
/// In the template editor every move edits the template. On a slide, elements follow their template: a move asks
/// first (Edit Template Instead, Detach This Slide, or Cancel), and only a detached element moves on its own.
struct CanvasView: View {
    /// Gestures measure in this fixed space, so a handle that moves as it's dragged doesn't jitter.
    static let space = "canvas"
    
    /// How close, in points on screen, an edge has to come to snap.
    static let snapDistance: Double = 6
    
    @Bindable private var coordinator: ProjectCoordinator
    @Bindable private var canvas: CanvasCoordinator
    @FocusState private var isFocused: Bool
    @State private var modifiers: EventModifiers = []
    
    init(coordinator: ProjectCoordinator, canvas: CanvasCoordinator) {
        self.coordinator = coordinator
        self.canvas = canvas
    }
    
    var body: some View {
        VStack(spacing: 0) {
            GeometryReader { proxy in
                if let scene = coordinator.canvasScene {
                    let scale = CanvasCoordinator.scale(canvas: scene.canvas, viewport: proxy.size, zoom: canvas.zoom)
                    let gestures = CanvasGestures(scale: scale, snapping: !modifiers.contains(.command), onIntent: canvas.handle)
                    
                    ZStack(alignment: .topLeading) {
                        // NOTE: - Faded and unclipped underneath, so whatever's dragged past an edge stays visible.
                        if !canvas.isPreviewing {
                            SceneView(scene: scene, images: coordinator.images(for: scene), clipsToCanvas: false)
                                .scaleEffect(scale, anchor: .topLeading)
                                .frame(width: scene.canvas.width * scale, height: scene.canvas.height * scale, alignment: .topLeading)
                                .opacity(0.3)
                                .allowsHitTesting(false)
                        }
                        
                        SceneView(scene: scene, images: coordinator.images(for: scene))
                            .scaleEffect(scale, anchor: .topLeading)
                            .frame(width: scene.canvas.width * scale, height: scene.canvas.height * scale, alignment: .topLeading)
                            .onTapGesture { canvas.handle(.select(nil)) }
                        
                        // NOTE: - Preview shows the slide alone, as it exports.
                        if !canvas.isPreviewing {
                            ForEach(handles(in: scene), id: \.element) { handle in
                                switch handle.shape {
                                case let .box(center, size, rotation):
                                    BoxHandles(
                                        element: handle.element,
                                        name: handle.name,
                                        center: center,
                                        size: size,
                                        rotation: rotation,
                                        gestures: gestures,
                                        isSelected: canvas.selected == handle.element,
                                        isLocked: canvas.isLocked(handle.element)
                                    )
                                case let .text(frame):
                                    TextHandles(
                                        element: handle.element,
                                        name: handle.name,
                                        frame: frame,
                                        gestures: gestures,
                                        isSelected: canvas.selected == handle.element,
                                        isLocked: canvas.isLocked(handle.element)
                                    )
                                }
                            }
                            
                            GuideLines(guides: canvas.guides, canvas: scene.canvas, scale: scale)
                        }
                    }
                    .frame(width: scene.canvas.width * scale, height: scene.canvas.height * scale, alignment: .topLeading)
                    .coordinateSpace(.named(Self.space))
                    .background(Color.black.opacity(0.001))
                    .shadow(color: .black.opacity(0.25), radius: 12, y: 4)
                    .offset(canvas.pan)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .gesture(rotateAndMagnify)
                } else {
                    ContentUnavailableView("Nothing Selected", systemImage: "rectangle.portrait", description: Text("Choose a slide and a target."))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .background(.background.secondary)
            .clipped()
            .dropDestination(for: URL.self) { urls, _ in
                coordinator.handle(.importCapturesToCanvas(DroppedFile.load(from: urls)))
            }
            .overlay(alignment: .bottom) {
                if !coordinator.importIssues.isEmpty {
                    ImportIssuesBanner(issues: coordinator.importIssues, onDismiss: { coordinator.handle(.dismissImportIssues) })
                        .padding()
                }
            }
            .onGeometryChange(for: CGSize.self) { $0.size } action: { canvas.handle(.setViewport($0)) }
            .canvasScrolling(
                onPan: { canvas.handle(.pan(by: $0)) },
                onZoom: { canvas.handle(.zoom(by: $0, around: $1)) }
            )
            .focusable()
            .focused($isFocused)
            .focusEffectDisabled()
            .onKeyPress(keys: [.upArrow, .downArrow, .leftArrow, .rightArrow]) { press in
                let fast = press.modifiers.contains(.shift)
                
                switch press.key {
                case .upArrow: canvas.handle(.arrow(dx: 0, dy: -1, fast: fast))
                case .downArrow: canvas.handle(.arrow(dx: 0, dy: 1, fast: fast))
                case .leftArrow: canvas.handle(.arrow(dx: -1, dy: 0, fast: fast))
                default: canvas.handle(.arrow(dx: 1, dy: 0, fast: fast))
                }
                
                return .handled
            }
            .onKeyPress(.escape) {
                guard canvas.isPreviewing else {
                    return .ignored
                }
                
                canvas.handle(.setPreviewing(false))
                return .handled
            }
            .onKeyPress(characters: ["="]) { press in
                // NOTE: - ⌘+ is ⌘⇧= on most keyboards, so ⌘= zooms in too, like it does in other apps.
                guard press.modifiers == .command else {
                    return .ignored
                }
                
                canvas.handle(.zoomIn)
                return .handled
            }
            .trackingModifiers(.command, into: $modifiers)
            .onAppear { isFocused = true }
            
            CanvasBar(coordinator: coordinator, canvas: canvas)
        }
        .alert(
            detachTitle,
            isPresented: Binding(get: { coordinator.pendingDetach != nil }, set: { if !$0 { coordinator.handle(.cancelDetach) } }),
            presenting: coordinator.pendingDetach
        ) { element in
            Button("Edit Template Instead") {
                coordinator.handle(.cancelDetach)
                
                if let template = slideTemplate {
                    coordinator.handle(.selectTemplate(template.id))
                    canvas.handle(.select(element))
                }
            }
            
            Button("Detach This Slide") { coordinator.handle(.detach(element)) }
            Button("Cancel", role: .cancel) { coordinator.handle(.cancelDetach) }
        } message: { element in
            Text("This slide follows the \(slideTemplate?.name ?? "") template on \(coordinator.currentDeviceClass.displayName). Moving \(name(of: element)) only on this slide makes it different from the other slides using the template, and it stops following the template's changes there.")
        }
    }
    
    // MARK: - Helpers
    
    private var slideTemplate: Template? {
        coordinator.currentSlide.flatMap { Resolver.layout(for: $0, style: coordinator.project.style, device: coordinator.currentDeviceClass).template }
    }
    
    private var detachTitle: String {
        "Detach This Slide from \(slideTemplate?.name ?? "Its Template")?"
    }
    
    private func name(of element: ElementRef) -> String {
        switch element {
        case .primary: "the primary text"
        case .secondary: "the secondary text"
        case .device: "the device"
        case let .extra(id): (slideTemplate?.element(id)?.name).map { "“\($0)”" } ?? "this element"
        }
    }
    
    /// Every element on the canvas with its outline: devices and images as rotated boxes, text as a box.
    private func handles(in scene: ResolvedScene) -> [CanvasHandle] {
        let template = coordinator.currentTemplate ?? slideTemplate
        var handles: [CanvasHandle] = []
        
        for extra in scene.extrasBehind {
            let name = template?.element(extra.id)?.name ?? "Element"
            
            switch extra.content {
            case let .device(device): handles.append(CanvasHandle(element: .extra(extra.id), name: name, shape: .box(device.center, device.size, device.rotation)))
            case let .image(image): handles.append(CanvasHandle(element: .extra(extra.id), name: name, shape: .box(image.center, image.size, image.rotation)))
            case .text: break
            }
        }
        
        if let device = scene.device {
            handles.append(CanvasHandle(element: .device, name: "Device", shape: .box(device.center, device.size, device.rotation)))
        }
        
        for role in TextRole.allCases {
            if let text = scene.text(role) {
                handles.append(CanvasHandle(element: .text(role), name: "\(role.displayName) Text", shape: .text(text.frame)))
            }
        }
        
        for extra in scene.extrasInFront {
            if case let .text(text) = extra.content {
                handles.append(CanvasHandle(element: .extra(extra.id), name: template?.element(extra.id)?.name ?? "Text", shape: .text(text.frame)))
            }
        }
        
        return handles
    }
    
    private var rotateAndMagnify: some Gesture {
        SimultaneousGesture(
            RotateGesture()
                .onChanged { canvas.handle(.rotate(degrees: $0.rotation.degrees)) }
                .onEnded { _ in canvas.handle(.endGesture) },
            MagnifyGesture()
                .onChanged { canvas.handle(.magnify($0.magnification)) }
                .onEnded { _ in canvas.handle(.endGesture) }
        )
    }
}

/// Makes the canvas's drags, in the fixed canvas space and in canvas pixels.
private struct CanvasGestures {
    let scale: Double
    let snapping: Bool
    let onIntent: (CanvasCoordinator.Intent) -> Void
    
    func move(_ element: CanvasCoordinator.Element) -> some Gesture {
        DragGesture(minimumDistance: 1, coordinateSpace: .named(CanvasView.space))
            .onChanged { value in
                onIntent(.select(element))
                onIntent(.drag(element, translation: pixels(value.translation), snapping: snapping, tolerance: CanvasView.snapDistance / scale))
            }
            .onEnded { _ in onIntent(.endGesture) }
    }
    
    func resize(_ element: CanvasCoordinator.Element, _ handle: BoxAnchor) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named(CanvasView.space))
            .onChanged { value in
                onIntent(.resize(element, handle: handle, translation: pixels(value.translation), snapping: snapping, tolerance: CanvasView.snapDistance / scale))
            }
            .onEnded { _ in onIntent(.endGesture) }
    }
    
    private func pixels(_ size: CGSize) -> CGSize {
        CGSize(width: size.width / scale, height: size.height / scale)
    }
}

/// One element's outline on the canvas.
private struct CanvasHandle {
    enum Shape {
        /// A device or image, which rotates and scales around its anchor.
        case box(CGPoint, CGSize, Double)
        
        /// A text box, whose height follows its font size.
        case text(CGRect)
    }
    
    var element: ElementRef
    var name: String
    var shape: Shape
}

/// A device's or image's outline and its eight handles, on its rotated frame.
private struct BoxHandles: View {
    private let element: ElementRef
    private let name: String
    private let center: CGPoint
    private let size: CGSize
    private let rotation: Double
    private let gestures: CanvasGestures
    private let isSelected: Bool
    private let isLocked: Bool
    
    init(element: ElementRef, name: String, center: CGPoint, size: CGSize, rotation: Double, gestures: CanvasGestures, isSelected: Bool, isLocked: Bool) {
        self.element = element
        self.name = name
        self.center = center
        self.size = size
        self.rotation = rotation
        self.gestures = gestures
        self.isSelected = isSelected
        self.isLocked = isLocked
    }
    
    var body: some View {
        let scale = gestures.scale
        
        Rectangle()
            .fill(Color.white.opacity(0.001))
            .overlay {
                if isSelected {
                    Rectangle().strokeBorder(isLocked ? Color.orange : Color.accentColor, style: StrokeStyle(lineWidth: 1.5, dash: isLocked ? [5, 3] : []))
                }
            }
            .frame(width: size.width * scale, height: size.height * scale)
            .rotationEffect(.degrees(rotation))
            .position(x: center.x * scale, y: center.y * scale)
            .gesture(gestures.move(element))
            .onTapGesture { gestures.onIntent(.select(element)) }
            .accessibilityLabel(name)
        
        if isSelected {
            if isLocked {
                LockBadge()
                    .position(x: center.x * scale, y: center.y * scale)
            } else {
                ForEach(BoxAnchor.allCases.filter { $0 != .center }, id: \.self) { handle in
                    let point = Resolver.devicePoint(handle, center: center, size: size, rotation: rotation)
                    
                    HandleView(rotation: rotation)
                        .position(x: point.x * scale, y: point.y * scale)
                        .gesture(gestures.resize(element, handle))
                        .accessibilityLabel("Resize from \(handle.displayName)")
                }
            }
        }
    }
}

/// A text box's outline, with handles on its leading and trailing edges. Its height follows its font size.
private struct TextHandles: View {
    private let element: ElementRef
    private let name: String
    private let frame: CGRect
    private let gestures: CanvasGestures
    private let isSelected: Bool
    private let isLocked: Bool
    
    init(element: ElementRef, name: String, frame: CGRect, gestures: CanvasGestures, isSelected: Bool, isLocked: Bool) {
        self.element = element
        self.name = name
        self.frame = frame
        self.gestures = gestures
        self.isSelected = isSelected
        self.isLocked = isLocked
    }
    
    var body: some View {
        let scale = gestures.scale
        let color = isSelected ? (isLocked ? Color.orange : Color.accentColor) : Color.white.opacity(0.25)
        
        Rectangle()
            .fill(Color.white.opacity(0.001))
            .overlay {
                Rectangle().strokeBorder(color, style: StrokeStyle(lineWidth: isSelected ? 1.5 : 1, dash: isSelected && !isLocked ? [] : [4, 3]))
            }
            .frame(width: frame.width * scale, height: frame.height * scale)
            .position(x: frame.midX * scale, y: frame.midY * scale)
            .gesture(gestures.move(element))
            .onTapGesture { gestures.onIntent(.select(element)) }
            .accessibilityLabel(name)
        
        if isSelected {
            if isLocked {
                LockBadge()
                    .position(x: frame.maxX * scale + 12, y: frame.minY * scale)
            } else {
                ForEach([BoxAnchor.leading, .trailing], id: \.self) { handle in
                    HandleView(rotation: 0, isBar: true)
                        .position(x: (handle == .leading ? frame.minX : frame.maxX) * scale, y: frame.midY * scale)
                        .gesture(gestures.resize(element, handle))
                        .accessibilityLabel("Resize from \(handle.displayName)")
                }
            }
        }
    }
}

/// Shows that a selected element follows its template, so moving it asks to detach.
private struct LockBadge: View {
    var body: some View {
        Image(systemName: "lock.fill")
            .font(.caption.weight(.semibold))
            .foregroundStyle(.white)
            .padding(5)
            .background(.orange, in: Circle())
            .help("Follows its template. Moving it asks to detach this slide.")
            .accessibilityLabel("Follows its template")
            .allowsHitTesting(false)
    }
}

/// A resize handle: a square on a corner or edge, or a bar for text's sides.
private struct HandleView: View {
    private let rotation: Double
    private let isBar: Bool
    
    init(rotation: Double, isBar: Bool = false) {
        self.rotation = rotation
        self.isBar = isBar
    }
    
    var body: some View {
        RoundedRectangle(cornerRadius: isBar ? 2 : 1.5)
            .fill(.white)
            .strokeBorder(Color.accentColor, lineWidth: 1.5)
            .frame(width: isBar ? 6 : 9, height: isBar ? 18 : 9)
            .rotationEffect(.degrees(rotation))
            .frame(width: 22, height: 22)
            .contentShape(Rectangle())
            .pointerHoverEffect()
    }
}

/// The lines the current drag snapped to.
private struct GuideLines: View {
    private let guides: [SnapGuide]
    private let canvas: CGSize
    private let scale: Double
    
    init(guides: [SnapGuide], canvas: CGSize, scale: Double) {
        self.guides = guides
        self.canvas = canvas
        self.scale = scale
    }
    
    var body: some View {
        Path { path in
            for guide in guides {
                let position = guide.position * scale
                
                switch guide.axis {
                case .vertical:
                    path.move(to: CGPoint(x: position, y: 0))
                    path.addLine(to: CGPoint(x: position, y: canvas.height * scale))
                case .horizontal:
                    path.move(to: CGPoint(x: 0, y: position))
                    path.addLine(to: CGPoint(x: canvas.width * scale, y: position))
                }
            }
        }
        .stroke(Color.pink, lineWidth: 1)
        .allowsHitTesting(false)
    }
}

/// The target picker and slide stepper under the canvas.
private struct CanvasBar: View {
    @Bindable private var coordinator: ProjectCoordinator
    @Bindable private var canvas: CanvasCoordinator
    
    init(coordinator: ProjectCoordinator, canvas: CanvasCoordinator) {
        self.coordinator = coordinator
        self.canvas = canvas
    }
    
    var body: some View {
        HStack {
            if let template = coordinator.currentTemplate {
                Label("Editing the \(template.name) template", systemImage: "rectangle.on.rectangle")
                    .font(.headline)
                
                let count = coordinator.slides(using: template.id).count
                
                Text(count == 1 ? "· 1 slide uses it" : "· \(count) slides use it")
                    .foregroundStyle(.secondary)
                
                Button("Done") { coordinator.handle(.selectTemplate(nil)) }
                    .buttonStyle(.bordered)
                    .disabled(coordinator.selection.slideID == nil)
            } else {
                Button {
                    step(-1)
                } label: {
                    Image(systemName: "chevron.left")
                }
                .accessibilityLabel("Previous Slide")
                .keyboardShortcut("[", modifiers: .command)
                
                Text(coordinator.currentSlide?.title ?? "")
                    .font(.headline)
                    .frame(minWidth: 140)
                
                Button {
                    step(1)
                } label: {
                    Image(systemName: "chevron.right")
                }
                .accessibilityLabel("Next Slide")
                .keyboardShortcut("]", modifiers: .command)
            }
            
            Spacer()
            
            Picker("Target", selection: Binding(get: { coordinator.selection.targetID ?? "" }, set: { coordinator.handle(.selectTarget($0)) })) {
                ForEach(coordinator.currentSet?.resolvedTargets() ?? []) { target in
                    Text(target.name).tag(target.id)
                }
            }
            .fixedSize()
            
            Text(coordinator.currentDeviceClass.displayName)
                .foregroundStyle(.secondary)
            
            if !canvas.isPreviewing {
                Text("Hold ⌘ to move without snapping")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .layoutPriority(-1)
            }
            
            Button {
                canvas.handle(.togglePreview)
            } label: {
                Image(systemName: canvas.isPreviewing ? "eye.fill" : "eye")
            }
            .foregroundStyle(canvas.isPreviewing ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
            .accessibilityLabel(canvas.isPreviewing ? "Stop Previewing" : "Preview")
            .help(canvas.isPreviewing ? "Show outlines and handles again (⌥⌘P or Esc)" : "Preview: hide outlines, handles and guides (⌥⌘P)")
            
            ZoomControls(canvas: canvas)
        }
        // NOTE: - One line, always: a bar that wrapped as the zoom changed would resize the canvas, which changes
        // the zoom, in a loop.
        .lineLimit(1)
        .fixedSize(horizontal: false, vertical: true)
        .buttonStyle(.borderless)
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(coordinator.isEditingTemplate ? AnyShapeStyle(.tint.opacity(0.12)) : AnyShapeStyle(.bar))
    }
    
    private func step(_ delta: Int) {
        guard let set = coordinator.currentSet, let slide = coordinator.selection.slideID, let index = set.slideIDs.firstIndex(of: slide), let target = coordinator.selection.targetID else {
            return
        }
        
        let next = (index + delta + set.slideIDs.count) % set.slideIDs.count
        coordinator.handle(.selectCell(CellID(setID: set.id, slideID: set.slideIDs[next], targetID: target)))
    }
}

/// Zoom out and in, with the canvas's size on screen (a percentage of its pixels), which fits it again when clicked.
private struct ZoomControls: View {
    @Bindable private var canvas: CanvasCoordinator
    
    init(canvas: CanvasCoordinator) {
        self.canvas = canvas
    }
    
    var body: some View {
        HStack(spacing: 4) {
            Button {
                canvas.handle(.zoomOut)
            } label: {
                Image(systemName: "minus.magnifyingglass")
            }
            .accessibilityLabel("Zoom Out")
            .help("Zoom Out (⌘−)")
            .disabled(canvas.zoom <= CanvasCoordinator.zoomRange.lowerBound)
            
            Button("\(Int((canvas.scale * 100).rounded()))%") {
                canvas.handle(.zoomToFit)
            }
            .monospacedDigit()
            .frame(width: 48)
            .help(canvas.isZoomed ? "Zoom to Fit (⌘0)" : "Fits the window")
            .disabled(!canvas.isZoomed)
            
            Button {
                canvas.handle(.zoomIn)
            } label: {
                Image(systemName: "plus.magnifyingglass")
            }
            .accessibilityLabel("Zoom In")
            .help("Zoom In (⌘+)")
            .disabled(canvas.zoom >= CanvasCoordinator.zoomRange.upperBound)
        }
    }
}

#Preview {
    @Previewable @State var coordinator = ProjectCoordinator(document: ProjectDocument(contents: ProjectContents(project: .fixture())))
    
    CanvasView(coordinator: coordinator, canvas: CanvasCoordinator(project: coordinator))
        .task {
            await coordinator.start()
            coordinator.handle(.showCanvas)
        }
        .frame(width: 700, height: 800)
}
