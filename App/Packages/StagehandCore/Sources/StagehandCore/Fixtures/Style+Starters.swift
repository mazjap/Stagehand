import Foundation
import StagehandModel

/// The template sets New Project offers besides the library's. They're built in code, like the fixtures, and have a
/// layout for every device class, so adding a device later never finds a template without one.
public enum StarterTemplateSet: String, CaseIterable, Identifiable, Sendable {
    case darkGlow
    case lightClean
    case boldColor
    
    public var id: String {
        rawValue
    }
    
    public var name: String {
        switch self {
        case .darkGlow: "Dark Glow"
        case .lightClean: "Light and Clean"
        case .boldColor: "Bold Color"
        }
    }
    
    public var summary: String {
        switch self {
        case .darkGlow: "A dark gradient, an orange headline and a glow behind the device. Straight, Tilted and Zoomed."
        case .lightClean: "A light background with dark text. Straight and Zoomed."
        case .boldColor: "A bright gradient with white text. Straight and Tilted."
        }
    }
    
    // MARK: - Functions
    
    /// The template set, with a new ID.
    public func style() -> Style {
        var style: Style
        
        switch self {
        case .darkGlow:
            style = .fixture(id: UUID())
        case .lightClean:
            style = .fixture(id: UUID())
            style.name = name
            style.colors = [
                "background": RGBA(hex: "#F5F5F7")!,
                "backgroundEnd": RGBA(hex: "#FFFFFF")!,
                "accent": RGBA(hex: "#1D1D1F")!,
                "subline": RGBA(hex: "#6E6E73")!,
                "glow": RGBA(hex: "#000000")!,
            ]
            style.primary.letterCase = Varying(.asWritten)
            style.primary.tracking = Varying(0)
            style.templates.removeAll { $0.id == .tilted }
            Self.removeGlows(from: &style)
        case .boldColor:
            style = .fixture(id: UUID())
            style.name = name
            style.colors = [
                "background": RGBA(hex: "#FF5F3C")!,
                "backgroundEnd": RGBA(hex: "#FFB03C")!,
                "accent": RGBA(hex: "#FFFFFF")!,
                "subline": RGBA(hex: "#FFF4E8")!,
                "glow": RGBA(hex: "#7A1F00")!,
            ]
            style.background = Varying(.linearGradient(tokens: ["background", "backgroundEnd"], angle: 30))
            style.templates.removeAll { $0.id == .zoomed }
        }
        
        style.name = name
        
        for index in style.templates.indices {
            style.templates[index].completeLayouts(for: DeviceClass.allCases)
        }
        
        return style
    }
    
    private static func removeGlows(from style: inout Style) {
        for index in style.templates.indices {
            for device in style.templates[index].layouts.keys {
                style.templates[index].layouts[device]?.device.glow = nil
            }
        }
    }
}

extension Style {
    /// A template set with one blank template, laid out for each of some devices: what Start from Scratch makes.
    public static func blank(for devices: [DeviceClass]) -> Style {
        var style = Style.fixture(id: UUID())
        style.name = "Untitled Template Set"
        
        var template = Template(name: "Untitled Template")
        
        for device in devices {
            template.layouts[device] = Template.blankLayout(for: device)
        }
        
        style.templates = [template]
        return style
    }
}

extension Template {
    /// The class whose layout is the best start for another's: the iPhone Duo's displays and the iPad are shaped
    /// alike, and the iPhone is the next closest to all of them.
    public static func similarClasses(to device: DeviceClass) -> [DeviceClass] {
        switch device {
        case .phone: [.duoOuter, .pad, .duoInner]
        case .duoOuter: [.duoInner, .pad, .phone]
        case .duoInner: [.duoOuter, .pad, .phone]
        case .pad: [.duoInner, .duoOuter, .phone]
        case .watch: [.phone]
        case .mac: [.pad]
        }
    }
    
    /// A starting layout for a class with nothing to copy.
    public static func blankLayout(for device: DeviceClass) -> TemplateLayout {
        var layout = TemplateLayout.standard
        
        switch device {
        case .watch:
            layout.device = DevicePlacement(position: NormPoint(x: 0.5, y: 0.66), width: 0.7, bezel: .none, bareCornerRadius: 0.22)
            layout.secondary.lineLimit = 1
        case .mac:
            layout.device = DevicePlacement(position: NormPoint(x: 0.5, y: 0.6), width: 0.72, bezel: .none, bareCornerRadius: 0.012)
            layout.primary.lineLimit = 1
            layout.secondary.lineLimit = 1
        case .phone, .duoOuter, .duoInner, .pad:
            break
        }
        
        return layout
    }
    
    /// Gives each class without a layout a copy of the most similar class's, or a blank one.
    public mutating func completeLayouts(for devices: [DeviceClass]) {
        for device in devices where layouts[device] == nil {
            let source = Self.similarClasses(to: device).first { layouts[$0] != nil }
            layouts[device] = source.flatMap { layouts[$0] } ?? Self.blankLayout(for: device)
        }
    }
}
