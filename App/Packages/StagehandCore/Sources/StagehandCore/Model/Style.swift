import CoreGraphics
import Foundation
import StagehandModel

/// A project's look, shown as a "Template Set": color tokens, a background, the two text styles, and the templates.
///
/// The code keeps the name `Style` (as do `.stagehandstyle` files and the library's `Styles/` folder), since renaming
/// a saved file type breaks files that already exist.
public struct Style: Codable, Hashable, Sendable, Identifiable {
    public var id: UUID
    public var name: String
    
    /// Bumped on each save to the library.
    public var version: Int
    
    /// Color tokens, like `background`, `accent`, `subline` and `glow`.
    public var colors: [String: RGBA]
    public var background: Varying<Fill>
    public var primary: TextStyle
    public var secondary: TextStyle
    
    /// In the order the editor lists them. Saved as an object keyed by ID plus `templateOrder`, so a three-way merge
    /// sees each template's changes on their own.
    public var templates: [Template]
    
    public init(
        id: UUID = UUID(),
        name: String,
        version: Int = 1,
        colors: [String: RGBA],
        background: Varying<Fill>,
        primary: TextStyle,
        secondary: TextStyle,
        templates: [Template]
    ) {
        self.id = id
        self.name = name
        self.version = version
        self.colors = colors
        self.background = background
        self.primary = primary
        self.secondary = secondary
        self.templates = templates
    }
    
    // MARK: - Coding
    
    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case version
        case colors
        case background
        case primary
        case secondary
        case templates
        case templateOrder
    }
    
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(UUID.self, forKey: .id)
        self.name = try container.decode(String.self, forKey: .name)
        self.version = try container.decode(Int.self, forKey: .version)
        self.colors = try container.decode([String: RGBA].self, forKey: .colors)
        self.background = try container.decode(Varying<Fill>.self, forKey: .background)
        self.primary = try container.decode(TextStyle.self, forKey: .primary)
        self.secondary = try container.decode(TextStyle.self, forKey: .secondary)
        
        // NOTE: - Files from before text wrapped also have `autoFitMinimum` and `autoFitScope`, which are ignored:
        // text is always drawn at its style's size now.
        
        let templates = try container.decode([TemplateID: Template].self, forKey: .templates)
        let order = try container.decodeIfPresent([TemplateID].self, forKey: .templateOrder) ?? []
        let ordered = order.compactMap { templates[$0] }
        let rest = templates.values.filter { !order.contains($0.id) }.sorted { $0.id < $1.id }
        self.templates = ordered + rest
    }
    
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(version, forKey: .version)
        try container.encode(colors, forKey: .colors)
        try container.encode(background, forKey: .background)
        try container.encode(primary, forKey: .primary)
        try container.encode(secondary, forKey: .secondary)
        try container.encode(Dictionary(templates.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first }), forKey: .templates)
        try container.encode(templates.map(\.id), forKey: .templateOrder)
    }
    
    // MARK: - Functions
    
    public func textStyle(_ role: TextRole) -> TextStyle {
        switch role {
        case .primary: primary
        case .secondary: secondary
        }
    }
    
    public mutating func updateTextStyle(_ role: TextRole, _ body: (inout TextStyle) -> Void) {
        switch role {
        case .primary: body(&primary)
        case .secondary: body(&secondary)
        }
    }
    
    /// A color token's value, or ``RGBA/missing``.
    public func color(_ token: String) -> RGBA {
        colors[token] ?? .missing
    }
    
    public func template(_ id: TemplateID) -> Template? {
        templates.first { $0.id == id }
    }
    
    public mutating func updateTemplate(_ id: TemplateID, _ body: (inout Template) -> Void) {
        guard let index = templates.firstIndex(where: { $0.id == id }) else {
            return
        }
        
        body(&templates[index])
    }
    
    /// The templates a class can use: the ones with a layout for it.
    public func templates(for device: DeviceClass) -> [Template] {
        templates.filter { $0.layouts[device] != nil }
    }
    
    /// The template and layout a slide that asks for a template gets on a class: that template when it has a layout
    /// there, or else the first one that does. `nil` when no template has a layout for the class.
    public func resolvedTemplate(_ requested: TemplateID, for device: DeviceClass) -> (template: Template, layout: TemplateLayout, fellBack: Bool)? {
        if let template = template(requested), let layout = template.layouts[device] {
            return (template, layout, false)
        }
        
        if let template = templates(for: device).first, let layout = template.layouts[device] {
            return (template, layout, true)
        }
        
        return nil
    }
    
    /// Every class some template has a layout for.
    public var deviceClasses: [DeviceClass] {
        DeviceClass.allCases.filter { device in templates.contains { $0.layouts[device] != nil } }
    }
    
    /// Every font the style uses.
    public var fonts: Set<FontSpec> {
        var fonts = Set<FontSpec>()
        
        for style in [primary, secondary] {
            fonts.insert(style.font.base)
            fonts.formUnion(style.font.overrides.values)
        }
        
        return fonts
    }
    
    /// Every bezel a template pins.
    public var pinnedBezels: Set<BezelID> {
        var ids = Set<BezelID>()
        
        for template in templates {
            for layout in template.layouts.values {
                for placement in [ElementPlacement.device(layout.device)] + Array(layout.extras.values) {
                    if case let .pinned(id) = placement.device?.bezel {
                        ids.insert(id)
                    }
                }
            }
        }
        
        return ids
    }
}

/// How one text role looks.
public struct TextStyle: Codable, Hashable, Sendable {
    public var font: Varying<FontSpec>
    
    /// A fraction of the canvas width.
    public var size: Varying<Double>
    public var colorToken: Varying<String>
    public var letterCase: Varying<LetterCase>
    
    /// Extra space between letters, in fractions of the font size (em).
    public var tracking: Varying<Double>
    
    /// Line height, as a multiple of the font's own (1 is the font's default).
    public var lineSpacing: Varying<Double>
    
    public init(
        font: Varying<FontSpec>,
        size: Varying<Double>,
        colorToken: Varying<String>,
        letterCase: Varying<LetterCase> = Varying(.asWritten),
        tracking: Varying<Double> = Varying(0),
        lineSpacing: Varying<Double> = Varying(0)
    ) {
        self.font = font
        self.size = size
        self.colorToken = colorToken
        self.letterCase = letterCase
        self.tracking = tracking
        self.lineSpacing = lineSpacing
    }
}

/// Where a text role sits: an anchor point's position and a width. Text wraps to as many lines as it needs, and the
/// box's height follows from them, so a box always fits its text. A box anchored at its top grows downward.
///
/// Files from before text wrapped also have a `lineLimit`, which is ignored.
public struct TextPlacement: Codable, Hashable, Sendable {
    /// Where the anchor point sits, in fractions of the canvas.
    public var position: NormPoint
    
    /// Which point of the box ``position`` places. A box anchored at its bottom grows upward.
    public var anchor: BoxAnchor
    
    /// A fraction of the canvas width.
    public var width: Double
    public var alignment: TextAlign
    public var verticalAlignment: VerticalAlign
    
    public init(
        position: NormPoint,
        anchor: BoxAnchor = .top,
        width: Double,
        alignment: TextAlign = .center,
        verticalAlignment: VerticalAlign = .top
    ) {
        self.position = position
        self.anchor = anchor
        self.width = width
        self.alignment = alignment
        self.verticalAlignment = verticalAlignment
    }
    
    // MARK: - Functions
    
    /// The box's height in pixels for a number of lines at a font size.
    public static func height(lines count: Int, fontSize: Double, lineHeight: Double, lineSpacing: Double) -> Double {
        let lines = Double(max(count, 1))
        return lines * fontSize * lineHeight + (lines - 1) * lineSpacing
    }
    
    /// The box on a canvas, in pixels, for a height.
    public func frame(in canvas: CGSize, height: Double) -> CGRect {
        let width = width * canvas.width
        let point = position.absolute(in: canvas)
        return CGRect(x: point.x - anchor.unit.x * width, y: point.y - anchor.unit.y * height, width: width, height: height)
    }
    
    /// Moves and resizes the box to a frame in pixels, keeping its anchor.
    public mutating func setFrame(_ frame: CGRect, in canvas: CGSize) {
        width = frame.width / canvas.width
        position = NormPoint(
            x: (frame.minX + anchor.unit.x * frame.width) / canvas.width,
            y: (frame.minY + anchor.unit.y * frame.height) / canvas.height
        )
    }
}

/// Where a device sits: an anchor point of its frame, which it rotates and scales around.
public struct DevicePlacement: Codable, Hashable, Sendable {
    /// Where the anchor point sits, in fractions of the canvas.
    public var position: NormPoint
    public var anchor: BoxAnchor
    
    /// A fraction of the canvas width. The device may run off the canvas.
    public var width: Double
    
    /// Degrees, clockwise.
    public var rotation: Double
    public var bezel: BezelChoice
    public var glow: Glow?
    
    /// Corner radius of a capture drawn without a bezel, in fractions of the device's width.
    public var bareCornerRadius: Double
    
    public init(
        position: NormPoint,
        anchor: BoxAnchor = .center,
        width: Double,
        rotation: Double = 0,
        bezel: BezelChoice = .matchTarget,
        glow: Glow? = nil,
        bareCornerRadius: Double = 0.08
    ) {
        self.position = position
        self.anchor = anchor
        self.width = width
        self.rotation = rotation
        self.bezel = bezel
        self.glow = glow
        self.bareCornerRadius = bareCornerRadius
    }
}

/// Where a project's style came from, for pulling the library's later changes.
public struct BaseStyle: Codable, Hashable, Sendable {
    public var styleID: UUID
    public var version: Int
    
    /// The library style as it was when copied, for three-way merges.
    public var snapshot: Style
    
    public init(styleID: UUID, version: Int, snapshot: Style) {
        self.styleID = styleID
        self.version = version
        self.snapshot = snapshot
    }
}
