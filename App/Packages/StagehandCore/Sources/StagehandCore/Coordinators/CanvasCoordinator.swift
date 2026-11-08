import CoreGraphics
import Foundation
import Observation
import StagehandModel

/// The canvas's coordinator: what's selected, and turning drags, handles, rotations and arrow keys into edits.
///
/// In the template editor, every move edits the template's layout for the class, and every slide using the template
/// follows. On a slide, elements follow their template and are locked: a move asks the project coordinator to confirm
/// detaching (``ProjectCoordinator/Intent/requestDetach(_:)``) and changes nothing. Once an element is detached on a
/// class, moves edit the slide's own placement there. Drags snap to the canvas and the other elements unless snapping
/// is off, and each gesture is one undo step.
@Observable
@MainActor
public final class CanvasCoordinator {
    public typealias Element = ElementRef
    
    public enum Intent {
        case select(Element?)
        
        /// A drag's translation in canvas pixels, from where it started.
        case drag(Element, translation: CGSize, snapping: Bool, tolerance: Double)
        
        /// Dragging one of an element's handles, named by the point it's at, in canvas pixels from where it started.
        /// Devices and images scale around the opposite handle; text only resizes from its leading and trailing edges.
        case resize(Element, handle: BoxAnchor, translation: CGSize, snapping: Bool, tolerance: Double)
        
        /// Degrees from where the rotation started, for the selected device or image.
        case rotate(degrees: Double)
        
        /// A multiple of the width when the pinch started, for the selected device or image.
        case magnify(Double)
        case endGesture
        
        /// Arrow keys: steps in each direction, ten times as far with Shift.
        case arrow(dx: Int, dy: Int, fast: Bool)
        
        /// Which point of the element its position places. The element stays where it is.
        case setAnchor(Element, BoxAnchor)
        
        /// Moves the element's anchor point to a point in canvas pixels.
        case setPosition(Element, CGPoint)
        
        /// Resizes the element to a width in canvas pixels, around its anchor.
        case setWidth(Element, Double)
        
        /// A device's or image's rotation in degrees.
        case setRotation(Element, Double)
        
        /// The size of the area the canvas is shown in, in points, which zooming and panning stay inside.
        case setViewport(CGSize)
        
        /// One step in or out, around the middle of the view (⌘+ and ⌘−).
        case zoomIn
        case zoomOut
        
        /// Back to the whole canvas, centered (⌘0).
        case zoomToFit
        
        /// Zooms by a factor (⌘-scroll), keeping the point under `around` (in points from the view's center) still.
        case zoom(by: Double, around: CGPoint)
        
        /// Moves the canvas in the view (scrolling), in points.
        case pan(by: CGSize)
        
        /// Preview: the slide alone, as it exports, without outlines, handles, guides or anything past its edges.
        /// Gestures and arrow keys don't edit while it's on.
        case setPreviewing(Bool)
        case togglePreview
    }
    
    /// Where the selected element is, for the inspector's anchor grid and fields.
    public struct Arrangement: Hashable, Sendable {
        public var element: Element
        public var anchor: BoxAnchor
        
        /// The anchor point, in canvas pixels.
        public var point: CGPoint
        
        /// Before rotation, in canvas pixels.
        public var size: CGSize
        public var rotation: Double?
    }
    
    /// One arrow key press, in fractions of the canvas.
    public static let arrowStep = 0.0025
    
    public private(set) var selected: Element? = .device
    
    /// The lines the current drag snapped to.
    public private(set) var guides: [SnapGuide] = []
    
    /// How far the canvas is zoomed, as a multiple of the size that fits the view (1).
    public internal(set) var zoom: Double = 1
    
    /// How far the canvas's center is from the view's center, in points.
    public internal(set) var pan: CGSize = .zero
    
    /// Whether the canvas shows only the slide, as it exports (``Intent/setPreviewing(_:)``).
    public private(set) var isPreviewing = false
    
    /// The view's size in points, from ``Intent/setViewport(_:)``.
    public internal(set) var viewport: CGSize = .zero
    
    let project: ProjectCoordinator
    
    /// What the gesture started from.
    @ObservationIgnored private var start: (scene: ResolvedScene, placement: ElementPlacement)?
    
    /// Set when a gesture on a locked element asked to detach, so the rest of the gesture is ignored.
    @ObservationIgnored private var refused = false
    
    public init(project: ProjectCoordinator) {
        self.project = project
    }
    
    // MARK: - Computed Properties
    
    /// Whether an element follows its template here, so moving it needs the user to detach it first.
    public func isLocked(_ element: Element) -> Bool {
        guard !project.isEditingTemplate, let slide = project.currentSlide else {
            return false
        }
        
        return !slide.isDetached(element, on: project.currentDeviceClass)
    }
    
    /// The selected element's anchor, position and size.
    public var arrangement: Arrangement? {
        guard let selected, let scene = project.canvasScene, let placement = placement(of: selected) else {
            return nil
        }
        
        if let text = placement.text, let frame = scene.frame(of: selected) {
            return Arrangement(
                element: selected,
                anchor: text.anchor,
                point: CGPoint(x: frame.minX + text.anchor.unit.x * frame.width, y: frame.minY + text.anchor.unit.y * frame.height),
                size: frame.size,
                rotation: nil
            )
        }
        
        guard let box = Self.box(of: selected, in: scene) else {
            return nil
        }
        
        return Arrangement(
            element: selected,
            anchor: placement.anchor,
            point: Resolver.devicePoint(placement.anchor, center: box.center, size: box.size, rotation: box.rotation),
            size: box.size,
            rotation: box.rotation
        )
    }
    
    // MARK: - Intents
    
    public func handle(_ intent: Intent) {
        // NOTE: - The view's size arrives before there's a scene to show, so it's kept either way.
        if case let .setViewport(size) = intent {
            // NOTE: - Only when it changes: setting an observed property redraws even when it's equal.
            if viewport != size {
                viewport = size
                setPan(clampedPan(pan))
            }
            
            return
        }
        
        switch intent {
        case let .setPreviewing(isOn):
            setPreviewing(isOn)
            return
        case .togglePreview:
            setPreviewing(!isPreviewing)
            return
        case .drag, .resize, .rotate, .magnify, .arrow:
            // NOTE: - Nothing's drawn to grab while previewing, so a gesture or nudge would move what can't be seen.
            if isPreviewing {
                return
            }
        default:
            break
        }
        
        guard project.canvasScene != nil else {
            return
        }
        
        switch intent {
        case .setViewport, .setPreviewing, .togglePreview:
            break
        case .zoomIn:
            zoom(to: zoom * Self.zoomStep, around: .zero)
        case .zoomOut:
            zoom(to: zoom / Self.zoomStep, around: .zero)
        case .zoomToFit:
            zoom = 1
            pan = .zero
        case let .zoom(factor, anchor):
            zoom(to: zoom * factor, around: anchor)
        case let .pan(delta):
            setPan(clampedPan(CGSize(width: pan.width + delta.width, height: pan.height + delta.height)))
        case let .select(element):
            // NOTE: - The Arrange fields show the selected element, so a value typed there lands before it changes.
            if element != selected {
                project.commitPendingEdits()
            }
            
            selected = element
        case let .drag(element, translation, snapping, tolerance):
            drag(element, translation: translation, snapping: snapping, tolerance: tolerance)
        case let .resize(element, handle, translation, snapping, tolerance):
            resize(element, handle: handle, translation: translation, snapping: snapping, tolerance: tolerance)
        case let .rotate(degrees):
            guard let element = selected, let start = begin("Rotate", element), start.placement.text == nil else { return }
            var placement = start.placement
            placement.rotation = start.placement.rotation + degrees
            write("Rotate", placement, for: element)
        case let .magnify(factor):
            guard let element = selected, let start = begin("Resize", element), start.placement.text == nil else { return }
            var placement = start.placement
            placement.width = max(0.02, start.placement.width * factor)
            write("Resize", placement, for: element)
        case .endGesture:
            start = nil
            refused = false
            guides = []
            project.handle(.endGesture)
        case let .arrow(dx, dy, fast):
            arrow(dx: dx, dy: dy, fast: fast)
        case let .setAnchor(element, anchor):
            setAnchor(element, anchor)
        case let .setPosition(element, point):
            setPosition(element, point)
        case let .setWidth(element, width):
            setWidth(element, width)
        case let .setRotation(element, degrees):
            guard allowsEdit(element), var placement = placement(of: element), placement.text == nil else { return }
            placement.rotation = degrees
            write("Rotate", placement, for: element)
        }
    }
    
    private func setPreviewing(_ isOn: Bool) {
        guard isPreviewing != isOn else {
            return
        }
        
        isPreviewing = isOn
        guides = []
    }
    
    // MARK: - Gestures
    
    private func drag(_ element: Element, translation: CGSize, snapping: Bool, tolerance: Double) {
        guard let start = begin("Move", element), let original = start.scene.frame(of: element) else {
            return
        }
        
        let canvas = start.scene.canvas
        let moved = original.offsetBy(dx: translation.width, dy: translation.height)
        var offset = CGSize.zero
        
        if snapping {
            let result = Snapper.snap(moved, to: targets(excluding: element, in: start.scene), tolerance: tolerance)
            offset = result.offset
            guides = result.guides
        } else {
            guides = []
        }
        
        let total = CGSize(width: translation.width + offset.width, height: translation.height + offset.height)
        var placement = start.placement
        
        if case var .text(text) = placement {
            text.setFrame(original.offsetBy(dx: total.width, dy: total.height), in: canvas)
            placement = .text(text)
        } else {
            placement.position = NormPoint(
                x: start.placement.position.x + total.width / canvas.width,
                y: start.placement.position.y + total.height / canvas.height
            )
        }
        
        write("Move", placement, for: element)
    }
    
    private func resize(_ element: Element, handle: BoxAnchor, translation: CGSize, snapping: Bool, tolerance: Double) {
        guard let start = begin("Resize", element) else {
            return
        }
        
        if case let .text(text) = start.placement {
            resizeText(element, text, handle: handle, translation: translation, start: start.scene, snapping: snapping, tolerance: tolerance)
        } else {
            resizeBox(element, start.placement, handle: handle, translation: translation, start: start.scene, snapping: snapping, tolerance: tolerance)
        }
    }
    
    /// Text resizes only horizontally: its height follows its font size.
    private func resizeText(_ element: Element, _ text: TextPlacement, handle: BoxAnchor, translation: CGSize, start scene: ResolvedScene, snapping: Bool, tolerance: Double) {
        guard handle.resizesHorizontally, let original = scene.frame(of: element) else {
            return
        }
        
        let trailing = handle.unit.x == 1
        var edge = (trailing ? original.maxX : original.minX) + translation.width
        guides = []
        
        if snapping {
            let probe = CGRect(x: edge, y: original.minY, width: 0, height: original.height)
            let result = Snapper.snap(probe, xEdges: [.min], yEdges: [], to: targets(excluding: element, in: scene), tolerance: tolerance)
            edge += result.offset.width
            guides = result.guides
        }
        
        let minimumWidth = 20.0
        let frame = trailing
            ? CGRect(x: original.minX, y: original.minY, width: max(minimumWidth, edge - original.minX), height: original.height)
            : CGRect(x: min(edge, original.maxX - minimumWidth), y: original.minY, width: max(minimumWidth, original.maxX - edge), height: original.height)
        
        var resized = text
        resized.setFrame(frame, in: scene.canvas)
        write("Resize", .text(resized), for: element)
    }
    
    /// A device or image scales in proportion around the handle opposite the one being dragged.
    private func resizeBox(_ element: Element, _ placement: ElementPlacement, handle: BoxAnchor, translation: CGSize, start scene: ResolvedScene, snapping: Bool, tolerance: Double) {
        guard handle != .center, let box = Self.box(of: element, in: scene) else {
            return
        }
        
        let (hx, hy) = handle.direction
        let local = Resolver.rotate(CGPoint(x: translation.width, y: translation.height), degrees: -box.rotation)
        let vector = CGPoint(x: hx * box.size.width, y: hy * box.size.height)
        let length = vector.x * vector.x + vector.y * vector.y
        var scale = max(0.05, ((vector.x + local.x) * vector.x + (vector.y + local.y) * vector.y) / length)
        guides = []
        
        // Snapping the moving edges only makes sense while the box is upright.
        if snapping, abs(box.rotation.truncatingRemainder(dividingBy: 360)) < 0.01 {
            let candidate = Self.scaled(box, handle: handle, scale: scale)
            let xEdges: [Snapper.Edge] = hx > 0 ? [.max] : hx < 0 ? [.min] : []
            let yEdges: [Snapper.Edge] = hy > 0 ? [.max] : hy < 0 ? [.min] : []
            let result = Snapper.snap(candidate.bounds, xEdges: xEdges, yEdges: yEdges, to: targets(excluding: element, in: scene), tolerance: tolerance)
            let byX = hx != 0 && result.offset.width != 0 ? scale + result.offset.width * hx / box.size.width : nil
            let byY = hy != 0 && result.offset.height != 0 ? scale + result.offset.height * hy / box.size.height : nil
            
            if let byX, byY == nil || abs(byX - scale) <= abs(byY! - scale) {
                scale = byX
                guides = result.guides.filter { $0.axis == .vertical }
            } else if let byY {
                scale = byY
                guides = result.guides.filter { $0.axis == .horizontal }
            }
        }
        
        let resized = Self.scaled(box, handle: handle, scale: scale)
        let anchorPoint = Resolver.devicePoint(placement.anchor, center: resized.center, size: resized.size, rotation: box.rotation)
        var updated = placement
        updated.width = placement.width * scale
        updated.position = NormPoint(x: anchorPoint.x / scene.canvas.width, y: anchorPoint.y / scene.canvas.height)
        write("Resize", updated, for: element)
    }
    
    private func arrow(dx: Int, dy: Int, fast: Bool) {
        let element = selected ?? .device
        
        guard allowsEdit(element), var placement = placement(of: element) else {
            return
        }
        
        let step = Self.arrowStep * (fast ? 10 : 1)
        placement.position = NormPoint(x: placement.position.x + Double(dx) * step, y: placement.position.y + Double(dy) * step)
        write("Nudge", placement, for: element)
    }
    
    // MARK: - Fields
    
    private func setAnchor(_ element: Element, _ anchor: BoxAnchor) {
        guard allowsEdit(element), let scene = project.canvasScene, var placement = placement(of: element) else {
            return
        }
        
        if case var .text(text) = placement, let frame = scene.frame(of: element) {
            text.anchor = anchor
            text.setFrame(frame, in: scene.canvas)
            placement = .text(text)
        } else if let box = Self.box(of: element, in: scene) {
            let point = Resolver.devicePoint(anchor, center: box.center, size: box.size, rotation: box.rotation)
            placement.anchor = anchor
            placement.position = NormPoint(x: point.x / scene.canvas.width, y: point.y / scene.canvas.height)
        }
        
        write("Change Anchor", placement, for: element)
    }
    
    private func setPosition(_ element: Element, _ point: CGPoint) {
        guard allowsEdit(element), let scene = project.canvasScene, var placement = placement(of: element) else {
            return
        }
        
        if case var .text(text) = placement, let frame = scene.frame(of: element) {
            let moved = CGRect(x: point.x - text.anchor.unit.x * frame.width, y: point.y - text.anchor.unit.y * frame.height, width: frame.width, height: frame.height)
            text.setFrame(moved, in: scene.canvas)
            placement = .text(text)
        } else {
            placement.position = NormPoint(x: point.x / scene.canvas.width, y: point.y / scene.canvas.height)
        }
        
        write("Move", placement, for: element)
    }
    
    private func setWidth(_ element: Element, _ width: Double) {
        guard width > 1, allowsEdit(element), let scene = project.canvasScene, var placement = placement(of: element) else {
            return
        }
        
        if case var .text(text) = placement, let frame = scene.frame(of: element) {
            let anchorX = frame.minX + text.anchor.unit.x * frame.width
            let resized = CGRect(x: anchorX - text.anchor.unit.x * width, y: frame.minY, width: width, height: frame.height)
            text.setFrame(resized, in: scene.canvas)
            placement = .text(text)
        } else {
            placement.width = width / scene.canvas.width
        }
        
        write("Resize", placement, for: element)
    }
    
    // MARK: - Helpers
    
    /// The element's placement where the canvas edits it: the template's layout in the template editor, or the slide's
    /// layout (its template's, with its detachments) on a slide.
    private func placement(of element: Element) -> ElementPlacement? {
        let device = project.currentDeviceClass
        
        if let template = project.currentTemplate {
            return template.layouts[device]?.placement(for: element)
        }
        
        guard let slide = project.currentSlide else {
            return nil
        }
        
        return Resolver.layout(for: slide, style: project.project.style, device: device).layout.placement(for: element)
    }
    
    /// Writes a placement: into the template's layout, or the slide's detachment.
    private func write(_ name: String, _ placement: ElementPlacement, for element: Element) {
        if project.isEditingTemplate {
            project.handle(.editTemplate(name) { template, device in
                template.layouts[device]?.setPlacement(placement, for: element)
            })
        } else {
            project.handle(.editSlide(name) { slide, device in
                slide.detachments[device, default: Detachment()].setPlacement(placement, for: element)
            })
        }
    }
    
    /// Whether the element can be edited now. A locked one asks the user to detach it (once per gesture).
    private func allowsEdit(_ element: Element) -> Bool {
        guard isLocked(element) else {
            return true
        }
        
        if !refused {
            refused = true
            project.handle(.requestDetach(element))
        }
        
        return false
    }
    
    /// Starts a gesture's undo step the first time it's called, and returns what it started from.
    @discardableResult
    private func begin(_ name: String, _ element: Element) -> (scene: ResolvedScene, placement: ElementPlacement)? {
        if let start {
            return start
        }
        
        guard !refused, allowsEdit(element), let scene = project.canvasScene, let placement = placement(of: element) else {
            return nil
        }
        
        project.handle(.beginGesture(name))
        start = (scene, placement)
        return start
    }
    
    private func targets(excluding element: Element, in scene: ResolvedScene) -> Snapper.Targets {
        let others = scene.elements.filter { $0 != element }.compactMap { scene.frame(of: $0) }
        return Snapper.Targets(canvas: scene.canvas, others: others)
    }
    
    /// A device's or image's center, size and rotation in a scene.
    static func box(of element: Element, in scene: ResolvedScene) -> (center: CGPoint, size: CGSize, rotation: Double)? {
        switch element {
        case .device:
            return scene.device.map { ($0.center, $0.size, $0.rotation) }
        case let .extra(id):
            return switch scene.extra(id)?.content {
            case let .device(device): (device.center, device.size, device.rotation)
            case let .image(image): (image.center, image.size, image.rotation)
            case .text, nil: nil
            }
        case .primary, .secondary:
            return nil
        }
    }
    
    /// A box scaled around the handle opposite one.
    static func scaled(_ box: (center: CGPoint, size: CGSize, rotation: Double), handle: BoxAnchor, scale: Double) -> (center: CGPoint, size: CGSize, bounds: CGRect) {
        let (hx, hy) = handle.direction
        let fixed = CGPoint(x: -hx * box.size.width / 2 * (1 - scale), y: -hy * box.size.height / 2 * (1 - scale))
        let shift = Resolver.rotate(fixed, degrees: box.rotation)
        let center = CGPoint(x: box.center.x + shift.x, y: box.center.y + shift.y)
        let size = CGSize(width: box.size.width * scale, height: box.size.height * scale)
        return (center, size, ResolvedDevice.boundingBox(center: center, size: size, rotation: box.rotation))
    }
}

// MARK: - Computed Properties

extension ElementPlacement {
    /// Where the anchor point sits, in fractions of the canvas.
    var position: NormPoint {
        get {
            switch self {
            case let .text(placement): placement.position
            case let .device(placement): placement.position
            case let .image(placement): placement.position
            }
        }
        set {
            switch self {
            case var .text(placement): placement.position = newValue; self = .text(placement)
            case var .device(placement): placement.position = newValue; self = .device(placement)
            case var .image(placement): placement.position = newValue; self = .image(placement)
            }
        }
    }
    
    var anchor: BoxAnchor {
        get {
            switch self {
            case let .text(placement): placement.anchor
            case let .device(placement): placement.anchor
            case let .image(placement): placement.anchor
            }
        }
        set {
            switch self {
            case var .text(placement): placement.anchor = newValue; self = .text(placement)
            case var .device(placement): placement.anchor = newValue; self = .device(placement)
            case var .image(placement): placement.anchor = newValue; self = .image(placement)
            }
        }
    }
    
    /// A fraction of the canvas width.
    var width: Double {
        get {
            switch self {
            case let .text(placement): placement.width
            case let .device(placement): placement.width
            case let .image(placement): placement.width
            }
        }
        set {
            switch self {
            case var .text(placement): placement.width = newValue; self = .text(placement)
            case var .device(placement): placement.width = newValue; self = .device(placement)
            case var .image(placement): placement.width = newValue; self = .image(placement)
            }
        }
    }
    
    /// Degrees, clockwise. Text doesn't rotate.
    var rotation: Double {
        get {
            switch self {
            case .text: 0
            case let .device(placement): placement.rotation
            case let .image(placement): placement.rotation
            }
        }
        set {
            switch self {
            case .text: break
            case var .device(placement): placement.rotation = newValue; self = .device(placement)
            case var .image(placement): placement.rotation = newValue; self = .image(placement)
            }
        }
    }
}
