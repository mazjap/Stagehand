import Foundation
import StagehandModel

extension Project {
    /// A project with three slides on iPhone and iPad, the second using the Tilted template on iPhone.
    public static func fixture() -> Project {
        let readTheLand = Slide(
            id: UUID(uuidString: "00000000-0000-0000-0000-00000000A001")!,
            title: "Read the Land",
            primary: Varying(["en-US": "Read the land"]),
            secondary: Varying(["en-US": "Topo maps with every trail, peak and spring"]),
            captureKey: Varying("read-the-land")
        )
        
        let bringIt = Slide(
            id: UUID(uuidString: "00000000-0000-0000-0000-00000000A002")!,
            title: "Bring It Along",
            primary: Varying(["en-US": "Bring it along"]),
            secondary: Varying(["en-US": "Offline maps for when the signal drops"]),
            captureKey: Varying("bring-it-along"),
            template: Varying(.straight, overrides: [.phone: .tilted])
        )
        
        let markTheWay = Slide(
            id: UUID(uuidString: "00000000-0000-0000-0000-00000000A003")!,
            title: "Mark the Way",
            primary: Varying(["en-US": "Mark the way"]),
            secondary: Varying(["en-US": "Pins, notes and photos on every route"]),
            captureKey: Varying("mark-the-way")
        )
        
        return Project(
            name: "TrekPoint",
            style: .fixture(),
            devices: [.phone, .pad],
            targets: ["iphone-dynamic-island-large", "ipad-13"],
            slides: [readTheLand.id: readTheLand, bringIt.id: bringIt, markTheWay.id: markTheWay],
            slideOrder: [readTheLand.id, bringIt.id, markTheWay.id],
            bundleID: "com.mazjap.TrekPoint"
        )
    }
    
    /// A new document: no slides yet, on the devices chosen in New Project (iPhone alone by default), with a template
    /// set (a blank one by default).
    public static func empty(devices: [DeviceClass] = [.phone], style: Style? = nil) -> Project {
        Project(name: "Untitled", style: style ?? .blank(for: devices), devices: devices)
    }
    
    /// A slide made from a template, with placeholder text and a capture key from its title.
    public static func newSlide(title: String, template: TemplateID, locale: LocaleID, placeholder: TemplatePlaceholder = .standard) -> Slide {
        Slide(
            title: title,
            primary: Varying([locale: placeholder.primary]),
            secondary: Varying([locale: placeholder.secondary]),
            captureKey: Varying(title.slugified),
            template: Varying(template)
        )
    }
}

extension Date {
    /// Noon UTC on October 27, 2026, so formatted dates don't depend on the machine's time zone.
    public static let sampleDate = Date(timeIntervalSince1970: 1_793_102_400)
}
