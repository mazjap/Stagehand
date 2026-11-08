import Foundation
@testable import StagehandCore
import StagehandModel
import Testing

@Suite struct ModelCodingTests {
    private func roundTrip<T: Codable & Equatable>(_ value: T) throws -> T {
        let data = try FormatMigration.makeEncoder().encode(value)
        return try FormatMigration.makeDecoder().decode(T.self, from: data)
    }
    
    @Test func theProjectRoundTrips() throws {
        let project = Project.fixture()
        #expect(try roundTrip(project) == project)
    }
    
    @Test func theStyleRoundTrips() throws {
        let style = Style.fixture()
        #expect(try roundTrip(style) == style)
    }
    
    @Test func smallTypesRoundTrip() throws {
        #expect(try roundTrip(Fill.radialGradient(tokens: ["a", "b"], center: NormPoint(x: 0.5, y: 0.2), radius: 0.8)) == .radialGradient(tokens: ["a", "b"], center: NormPoint(x: 0.5, y: 0.2), radius: 0.8))
        #expect(try roundTrip(BezelChoice.pinned("phone-black")) == .pinned("phone-black"))
        #expect(try roundTrip(BezelChoice.none) == BezelChoice.none)
        #expect(try roundTrip(NormTransform(dx: 0.1, dy: -0.2, rotation: 4, scale: 1.1)) == NormTransform(dx: 0.1, dy: -0.2, rotation: 4, scale: 1.1))
        #expect(try roundTrip(RGBA(hex: "#FFA43C")!) == RGBA(hex: "#FFA43C")!)
        #expect(try roundTrip(LetterCase.uppercase) == .uppercase)
        #expect(try roundTrip(Glow(colorToken: "glow", blur: 0.05, spread: 1.1)) == Glow(colorToken: "glow", blur: 0.05, spread: 1.1))
        #expect(try roundTrip(BoxAnchor.bottomTrailing) == .bottomTrailing)
        #expect(try roundTrip(FontSpec(postScriptName: "PressStart2P-Regular")) == FontSpec(postScriptName: "PressStart2P-Regular"))
        #expect(try roundTrip(AppLocale(language: "de", region: "DE")) == AppLocale(language: "de", region: "DE"))
        #expect(try roundTrip(SimulatorSpec(deviceType: "a", runtime: "b", developerDir: "c")) == SimulatorSpec(deviceType: "a", runtime: "b", developerDir: "c"))
        #expect(try roundTrip(BaseStyle(styleID: UUID(), version: 2, snapshot: .fixture())).version == 2)
    }
    
    @Test func dictionariesKeyedByIDsAndClassesEncodeAsObjects() throws {
        let data = try FormatMigration.makeEncoder().encode(Project.fixture())
        let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let style = try #require(object["style"] as? [String: Any])
        
        let templates = try #require(style["templates"] as? [String: Any])
        let straight = try #require(templates["straight"] as? [String: Any])
        
        #expect(object["slides"] is [String: Any])
        #expect((straight["layouts"] as? [String: Any])?["phone"] != nil)
        #expect(style["templateOrder"] as? [String] == ["straight", "tilted", "zoomed"])
    }
    
    @Test func theFixtureHasAnIPhoneAndAnIPadLayout() {
        let project = Project.fixture()
        #expect(project.style.templates(for: .phone).map(\.id) == [.straight, .tilted, .zoomed])
        #expect(project.style.templates(for: .pad).map(\.id) == [.straight, .tilted])
        #expect(project.sets.map(\.devices) == [[.phone, .pad]])
        #expect(project.slides(in: project.mainLineup).count == 3)
    }
    
    @Test func everyStarterHasALayoutForEveryClass() {
        for starter in StarterTemplateSet.allCases {
            let style = starter.style()
            #expect(style.name == starter.name)
            #expect(style.templates.allSatisfy { template in DeviceClass.allCases.allSatisfy { template.layouts[$0] != nil } })
        }
    }
    
    @Test func hexColorsParse() {
        #expect(RGBA(hex: "#FFA43C") == RGBA(red: 1, green: 164.0 / 255, blue: 60.0 / 255))
        #expect(RGBA(hex: "FFA43C80")?.alpha == 128.0 / 255)
        #expect(RGBA(hex: "nope") == nil)
        #expect(RGBA(hex: "#FFA43C")?.hex == "#FFA43C")
    }
    
    @Test func slugsAreFileNameSafe() {
        #expect("Read the Land!".slugified == "read-the-land")
        #expect("  Größe & Mut ".slugified == "grosse-mut")
        #expect("!!!".slugified == "slide")
    }
}
