import Foundation
import StagehandModel

extension Style {
    /// A dark style with an orange accent and glow, and Straight, Tilted and Zoomed templates. Straight has a layout
    /// for iPhone, iPad, Apple Watch and Mac, Tilted for iPhone and iPad, and Zoomed for iPhone.
    ///
    /// The iPhone's Tilted layout runs off the canvas's right edge.
    public static func fixture(id: UUID = UUID(uuidString: "5A1B0C7E-2D3F-4A5B-8C6D-7E8F9A0B1C2D")!) -> Style {
        let glow = Glow(colorToken: "glow", blur: 0.07, opacity: 0.75, spread: 1.02)
        
        let phoneText = (
            primary: TextPlacement(position: NormPoint(x: 0.5, y: 0.055), width: 0.84),
            secondary: TextPlacement(position: NormPoint(x: 0.5, y: 0.175), width: 0.8)
        )
        let padText = (
            primary: TextPlacement(position: NormPoint(x: 0.5, y: 0.05), width: 0.8),
            secondary: TextPlacement(position: NormPoint(x: 0.5, y: 0.14), width: 0.76)
        )
        
        func phone(_ device: DevicePlacement) -> TemplateLayout {
            TemplateLayout(primary: phoneText.primary, secondary: phoneText.secondary, device: device)
        }
        
        func pad(_ device: DevicePlacement) -> TemplateLayout {
            TemplateLayout(primary: padText.primary, secondary: padText.secondary, device: device)
        }
        
        let watch = TemplateLayout(
            primary: TextPlacement(position: NormPoint(x: 0.5, y: 0.04), width: 0.88),
            secondary: TextPlacement(position: NormPoint(x: 0.5, y: 0.24), width: 0.84),
            device: DevicePlacement(position: NormPoint(x: 0.5, y: 0.66), width: 0.7, bezel: .none, bareCornerRadius: 0.22)
        )
        
        let mac = TemplateLayout(
            primary: TextPlacement(position: NormPoint(x: 0.5, y: 0.06), width: 0.7),
            secondary: TextPlacement(position: NormPoint(x: 0.5, y: 0.16), width: 0.6),
            device: DevicePlacement(position: NormPoint(x: 0.5, y: 0.6), width: 0.72, bezel: .none, glow: glow, bareCornerRadius: 0.012)
        )
        
        let templates = [
            Template(id: .straight, name: "Straight", layouts: [
                .phone: phone(DevicePlacement(position: NormPoint(x: 0.5, y: 0.63), width: 0.8, glow: glow)),
                .pad: pad(DevicePlacement(position: NormPoint(x: 0.5, y: 0.6), width: 0.78, glow: glow)),
                .watch: watch,
                .mac: mac,
            ]),
            Template(id: .tilted, name: "Tilted", layouts: [
                .phone: phone(DevicePlacement(position: NormPoint(x: 0.62, y: 0.64), width: 0.86, rotation: 9, glow: glow)),
                .pad: pad(DevicePlacement(position: NormPoint(x: 0.55, y: 0.62), width: 0.8, rotation: 6, glow: glow)),
            ]),
            Template(id: .zoomed, name: "Zoomed", layouts: [
                .phone: phone(DevicePlacement(position: NormPoint(x: 0.5, y: 0.78), width: 1.25, glow: glow)),
            ]),
        ]
        
        return Style(
            id: id,
            name: "Dark Glow",
            colors: [
                "background": RGBA(hex: "#14161A")!,
                "backgroundEnd": RGBA(hex: "#22262D")!,
                "accent": RGBA(hex: "#FFA43C")!,
                "subline": RGBA(hex: "#C9CDD4")!,
                "glow": RGBA(hex: "#FFA43C")!,
            ],
            background: Varying(.linearGradient(tokens: ["background", "backgroundEnd"], angle: 0)),
            primary: TextStyle(
                font: Varying(.systemHeavy),
                size: Varying(0.085, overrides: [.pad: 0.06, .watch: 0.1, .mac: 0.04]),
                colorToken: Varying("accent"),
                letterCase: Varying(.uppercase),
                tracking: Varying(0.02)
            ),
            secondary: TextStyle(
                font: Varying(.systemMedium),
                size: Varying(0.042, overrides: [.pad: 0.03, .watch: 0.06, .mac: 0.02]),
                colorToken: Varying("subline")
            ),
            templates: templates
        )
    }
}
