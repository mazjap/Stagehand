import CoreGraphics
import Foundation
import StagehandModel

/// A named arrangement, like "Straight" or "Tilted", with its own layout for each device class.
///
/// Every template places the three standard elements (Primary Text, Secondary Text and the Main Device) and can add
/// extra text, device and image elements. Slides made from a template follow it: moving an element here moves it on
/// every slide that uses this template, except where a slide is detached (``Detachment``).
public struct Template: Codable, Hashable, Sendable, Identifiable {
    public var id: TemplateID
    public var name: String
    
    /// The extra elements' definitions. Each class's layout places the ones that show there.
    public var elements: [TemplateElement]
    
    /// A class without a layout can't use this template. Nothing is borrowed from another class.
    public var layouts: [DeviceClass: TemplateLayout]
    
    /// The text the template editor shows, and a new slide made from it starts with. Slides never write it back.
    public var placeholder: TemplatePlaceholder
    
    public init(
        id: TemplateID = .make(),
        name: String,
        elements: [TemplateElement] = [],
        layouts: [DeviceClass: TemplateLayout] = [:],
        placeholder: TemplatePlaceholder = .standard
    ) {
        self.id = id
        self.name = name
        self.elements = elements
        self.layouts = layouts
        self.placeholder = placeholder
    }
    
    // MARK: - Codable
    
    private enum CodingKeys: String, CodingKey {
        case id, name, elements, layouts, placeholder
    }
    
    // NOTE: - `placeholder` came after format 3 shipped, so a file without one gets the standard placeholder. Adding
    // a key with a default needs no format bump; renaming one would.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(TemplateID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        elements = try container.decode([TemplateElement].self, forKey: .elements)
        layouts = try container.decode([DeviceClass: TemplateLayout].self, forKey: .layouts)
        placeholder = try container.decodeIfPresent(TemplatePlaceholder.self, forKey: .placeholder) ?? .standard
    }
    
    // MARK: - Functions
    
    public func element(_ id: ElementID) -> TemplateElement? {
        elements.first { $0.id == id }
    }
}

/// A template's stand-in text: what its editor shows in place of a slide's, and what a new slide starts with.
public struct TemplatePlaceholder: Codable, Hashable, Sendable {
    public var primary: String
    public var secondary: String
    
    public init(primary: String, secondary: String) {
        self.primary = primary
        self.secondary = secondary
    }
    
    public static let standard = TemplatePlaceholder(primary: "Your headline", secondary: "A line about what this screen shows")
    
    public func text(_ role: TextRole) -> String {
        switch role {
        case .primary: primary
        case .secondary: secondary
        }
    }
}

/// One template's layout on one device class.
public struct TemplateLayout: Codable, Hashable, Sendable {
    public var primary: TextPlacement
    public var secondary: TextPlacement
    public var device: DevicePlacement
    
    /// Standard elements this layout doesn't draw. They keep their placement, so showing one again puts it back.
    public var hiddenElements: [StandardElement]
    
    /// The extra elements that show on this class, by ID.
    public var extras: [ElementID: ElementPlacement]
    
    public init(
        primary: TextPlacement,
        secondary: TextPlacement,
        device: DevicePlacement,
        hiddenElements: [StandardElement] = [],
        extras: [ElementID: ElementPlacement] = [:]
    ) {
        self.primary = primary
        self.secondary = secondary
        self.device = device
        self.hiddenElements = hiddenElements
        self.extras = extras
    }
    
    /// A headline at the top, a line under it, and the device below: what a blank template starts from.
    public static let standard = TemplateLayout(
        primary: TextPlacement(position: NormPoint(x: 0.5, y: 0.05), width: 0.84),
        secondary: TextPlacement(position: NormPoint(x: 0.5, y: 0.17), width: 0.8),
        device: DevicePlacement(position: NormPoint(x: 0.5, y: 0.62), width: 0.78)
    )
    
    // MARK: - Functions
    
    public func isHidden(_ element: StandardElement) -> Bool {
        hiddenElements.contains(element)
    }
    
    public mutating func setHidden(_ element: StandardElement, _ hidden: Bool) {
        hiddenElements.removeAll { $0 == element }
        
        if hidden {
            hiddenElements.append(element)
            hiddenElements.sort { $0.rawValue < $1.rawValue }
        }
    }
    
    public func textPlacement(_ role: TextRole) -> TextPlacement {
        switch role {
        case .primary: primary
        case .secondary: secondary
        }
    }
    
    /// An element's placement, or `nil` for an extra element that doesn't show on this class.
    public func placement(for element: ElementRef) -> ElementPlacement? {
        switch element {
        case .primary: .text(primary)
        case .secondary: .text(secondary)
        case .device: .device(device)
        case let .extra(id): extras[id]
        }
    }
    
    /// Sets an element's placement. A placement of the wrong kind for a standard element is ignored.
    public mutating func setPlacement(_ placement: ElementPlacement, for element: ElementRef) {
        switch (element, placement) {
        case let (.primary, .text(text)): primary = text
        case let (.secondary, .text(text)): secondary = text
        case let (.device, .device(device)): self.device = device
        case let (.extra(id), placement): extras[id] = placement
        default: break
        }
    }
}

/// The three elements every template has. They can be hidden, but not deleted, so a slide's text and capture carry
/// across templates.
public enum StandardElement: String, Codable, Hashable, Sendable, CaseIterable {
    case primary
    case secondary
    case device
    
    public var displayName: String {
        switch self {
        case .primary: "Primary Text"
        case .secondary: "Secondary Text"
        case .device: "Main Device"
        }
    }
    
    public var ref: ElementRef {
        switch self {
        case .primary: .primary
        case .secondary: .secondary
        case .device: .device
        }
    }
}

/// An extra element's ID, unique within its template.
public typealias ElementID = String

/// Any element of a template: a standard one, or an extra one by ID.
public enum ElementRef: Hashable, Sendable {
    case primary
    case secondary
    case device
    case extra(ElementID)
    
    public static func text(_ role: TextRole) -> ElementRef {
        switch role {
        case .primary: .primary
        case .secondary: .secondary
        }
    }
    
    /// The text role of a standard text element.
    public var textRole: TextRole? {
        switch self {
        case .primary: .primary
        case .secondary: .secondary
        case .device, .extra: nil
        }
    }
    
    public var standard: StandardElement? {
        switch self {
        case .primary: .primary
        case .secondary: .secondary
        case .device: .device
        case .extra: nil
        }
    }
}

/// An extra element's definition: what kind it is, and its name in the editor.
public struct TemplateElement: Codable, Hashable, Sendable, Identifiable {
    public enum Kind: String, Codable, Hashable, Sendable, CaseIterable {
        /// Text, in one of the style's text styles.
        case text
        
        /// Another device, showing a capture.
        case device
        
        /// An image from the project's `assets/`.
        case image
        
        public var displayName: String {
            switch self {
            case .text: "Text"
            case .device: "Device"
            case .image: "Image"
            }
        }
    }
    
    public var id: ElementID
    public var name: String
    public var kind: Kind
    
    /// The text style a text element uses.
    public var textStyle: TextRole
    
    public init(id: ElementID = UUID().uuidString.lowercased(), name: String, kind: Kind, textStyle: TextRole = .secondary) {
        self.id = id
        self.name = name
        self.kind = kind
        self.textStyle = textStyle
    }
    
    // MARK: - Functions
    
    /// A starting placement for this kind of element, near the canvas's center.
    public func defaultPlacement() -> ElementPlacement {
        switch kind {
        case .text: .text(TextPlacement(position: NormPoint(x: 0.5, y: 0.3), width: 0.7))
        case .device: .device(DevicePlacement(position: NormPoint(x: 0.7, y: 0.7), width: 0.5))
        case .image: .image(ImagePlacement(position: NormPoint(x: 0.5, y: 0.5), width: 0.3))
        }
    }
}

/// Where an element sits.
public enum ElementPlacement: Codable, Hashable, Sendable {
    case text(TextPlacement)
    case device(DevicePlacement)
    case image(ImagePlacement)
    
    // MARK: - Computed Properties
    
    public var text: TextPlacement? {
        if case let .text(placement) = self { placement } else { nil }
    }
    
    public var device: DevicePlacement? {
        if case let .device(placement) = self { placement } else { nil }
    }
    
    public var image: ImagePlacement? {
        if case let .image(placement) = self { placement } else { nil }
    }
}

/// Where an image sits: an anchor point of its frame, which it rotates and scales around. Its height follows the
/// image's aspect ratio.
public struct ImagePlacement: Codable, Hashable, Sendable {
    /// In fractions of the canvas.
    public var position: NormPoint
    public var anchor: BoxAnchor
    
    /// A fraction of the canvas width.
    public var width: Double
    
    /// Degrees, clockwise.
    public var rotation: Double
    
    /// A fraction of the image's width.
    public var cornerRadius: Double
    
    public init(position: NormPoint, anchor: BoxAnchor = .center, width: Double, rotation: Double = 0, cornerRadius: Double = 0) {
        self.position = position
        self.anchor = anchor
        self.width = width
        self.rotation = rotation
        self.cornerRadius = cornerRadius
    }
}

/// A slide's own placements on one device class, which no longer follow its template there.
///
/// A slide is only detached after the user confirms it. Changing the slide's template on that class clears its
/// detachment, since the placements were the old template's.
public struct Detachment: Codable, Hashable, Sendable {
    public var primary: TextPlacement?
    public var secondary: TextPlacement?
    public var device: DevicePlacement?
    public var extras: [ElementID: ElementPlacement]
    
    public init(
        primary: TextPlacement? = nil,
        secondary: TextPlacement? = nil,
        device: DevicePlacement? = nil,
        extras: [ElementID: ElementPlacement] = [:]
    ) {
        self.primary = primary
        self.secondary = secondary
        self.device = device
        self.extras = extras
    }
    
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.primary = try container.decodeIfPresent(TextPlacement.self, forKey: .primary)
        self.secondary = try container.decodeIfPresent(TextPlacement.self, forKey: .secondary)
        self.device = try container.decodeIfPresent(DevicePlacement.self, forKey: .device)
        self.extras = try container.decodeIfPresent([ElementID: ElementPlacement].self, forKey: .extras) ?? [:]
    }
    
    // MARK: - Functions
    
    public var isEmpty: Bool {
        primary == nil && secondary == nil && device == nil && extras.isEmpty
    }
    
    /// The elements that are detached.
    public var elements: [ElementRef] {
        var elements: [ElementRef] = []
        
        if primary != nil { elements.append(.primary) }
        if secondary != nil { elements.append(.secondary) }
        if device != nil { elements.append(.device) }
        
        return elements + extras.keys.sorted().map(ElementRef.extra)
    }
    
    public func placement(for element: ElementRef) -> ElementPlacement? {
        switch element {
        case .primary: primary.map(ElementPlacement.text)
        case .secondary: secondary.map(ElementPlacement.text)
        case .device: device.map(ElementPlacement.device)
        case let .extra(id): extras[id]
        }
    }
    
    /// Sets or (with `nil`) removes an element's own placement.
    public mutating func setPlacement(_ placement: ElementPlacement?, for element: ElementRef) {
        switch element {
        case .primary: primary = placement?.text
        case .secondary: secondary = placement?.text
        case .device: device = placement?.device
        case let .extra(id): extras[id] = placement
        }
    }
    
    /// A template layout with these placements laid over it.
    public func applied(to layout: TemplateLayout) -> TemplateLayout {
        var result = layout
        result.primary = primary ?? layout.primary
        result.secondary = secondary ?? layout.secondary
        result.device = device ?? layout.device
        
        for (id, placement) in extras where layout.extras[id] != nil {
            result.extras[id] = placement
        }
        
        return result
    }
}

/// A slide's content for an extra element.
public enum ElementContent: Codable, Hashable, Sendable {
    /// For a text element.
    case text(Varying<Localized>)
    
    /// For a device element: the capture key.
    case capture(Varying<String>)
    
    /// For an image element: a file name in the project's `assets/`.
    case image(String)
    
    // MARK: - Computed Properties
    
    public var text: Varying<Localized>? {
        if case let .text(text) = self { text } else { nil }
    }
    
    public var captureKey: Varying<String>? {
        if case let .capture(key) = self { key } else { nil }
    }
    
    public var imageName: String? {
        if case let .image(name) = self { name } else { nil }
    }
}
