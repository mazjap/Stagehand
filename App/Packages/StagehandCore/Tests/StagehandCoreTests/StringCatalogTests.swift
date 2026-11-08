import Foundation
@testable import StagehandCore
import StagehandModel
import Testing

@Suite struct StringCatalogTests {
    private func project() -> Project {
        var project = Project.fixture()
        let id = project.slideOrder[0]
        project.slides[id]?.primary = Varying(
            ["en-US": "Read the land", "de": "Lies das Land"],
            overrides: [.watch: ["en-US": "Read it"], .duoInner: ["en-US": "Read the whole land"]]
        )
        return project
    }
    
    @Test func textAndOverridesSurviveARoundTrip() throws {
        let original = project()
        let data = try StringCatalog.export(original)
        
        var blank = original
        for id in blank.slides.keys {
            blank.slides[id]?.primary = Varying([:])
            blank.slides[id]?.secondary = Varying([:])
        }
        
        let imported = try StringCatalog.importCatalog(data, into: blank)
        #expect(imported.slides == original.slides)
    }
    
    @Test func extraTextElementsRoundTripUnderTheirNames() throws {
        var original = project()
        let badge = TemplateElement(id: "badge", name: "Badge", kind: .text)
        let clash = TemplateElement(id: "clash", name: "Primary", kind: .text)
        original.style.updateTemplate(.straight) { $0.elements = [badge, clash] }
        let id = original.slideOrder[0]
        original.slides[id]?.extraContent = [
            "badge": .text(Varying(["en-US": "New", "de": "Neu"], overrides: [.watch: ["en-US": "!"]])),
            "clash": .text(Varying(["en-US": "Not the headline"])),
        ]
        
        let data = try StringCatalog.export(original)
        let keys = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])["strings"] as? [String: Any]
        #expect(keys?["read-the-land.badge"] != nil)
        #expect(keys?["read-the-land.extra-primary"] != nil)
        
        var blank = original
        blank.slides[id]?.extraContent = [:]
        let imported = try StringCatalog.importCatalog(data, into: blank)
        #expect(imported.slides[id]?.extraContent == original.slides[id]?.extraContent)
        #expect(imported.slides[id]?.primary == original.slides[id]?.primary)
    }
    
    @Test func keysAreSlugAndRole() throws {
        let data = try StringCatalog.export(project())
        let catalog = try JSONDecoder().decode(StringCatalog.Catalog.self, from: data)
        
        #expect(catalog.sourceLanguage == "en-US")
        #expect(catalog.strings["read-the-land.primary"] != nil)
        #expect(catalog.strings["read-the-land.secondary"] != nil)
        #expect(catalog.strings["read-the-land.primary.duoInner"] != nil)
    }
    
    @Test func overridesBecomeDeviceVariations() throws {
        let data = try StringCatalog.export(project())
        let catalog = try JSONDecoder().decode(StringCatalog.Catalog.self, from: data)
        let english = try #require(catalog.strings["read-the-land.primary"]?.localizations?["en-US"])
        
        #expect(english.variations?.device?["applewatch"]?.stringUnit?.value == "Read it")
        #expect(english.variations?.device?["other"]?.stringUnit?.value == "Read the land")
        #expect(catalog.strings["read-the-land.primary"]?.localizations?["de"]?.stringUnit?.value == "Lies das Land")
    }
    
    @Test func aTranslationFromTheCatalogIsImported() throws {
        let catalog = """
        {"sourceLanguage":"en-US","version":"1.0","strings":{
          "mark-the-way.primary":{"localizations":{"fr":{"stringUnit":{"state":"translated","value":"Marquez le chemin"}}}},
          "unknown-slide.primary":{"localizations":{"fr":{"stringUnit":{"state":"translated","value":"?"}}}}
        }}
        """
        let imported = try StringCatalog.importCatalog(Data(catalog.utf8), into: .fixture())
        let slide = try #require(imported.slides.values.first { $0.slug == "mark-the-way" })
        #expect(slide.primary.base["fr"] == "Marquez le chemin")
        #expect(slide.primary.base["en-US"] == "Mark the way")
    }
}
