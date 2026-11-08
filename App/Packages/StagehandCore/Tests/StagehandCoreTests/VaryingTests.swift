import Foundation
@testable import StagehandCore
import StagehandModel
import Testing

@Suite struct VaryingTests {
    @Test func aClassWithoutAnOverrideUsesTheBase() {
        let value = Varying(10, overrides: [.pad: 20])
        #expect(value[.phone] == 10)
        #expect(value[.pad] == 20)
        #expect(value.isOverridden(for: .pad))
        #expect(!value.isOverridden(for: .phone))
    }
    
    @Test func anAutomaticEditChangesTheBaseUnlessTheClassIsOverridden() {
        var value = Varying(10, overrides: [.pad: 20])
        value.set(11, for: .phone)
        #expect(value.base == 11)
        #expect(value[.pad] == 20)
        
        value.set(21, for: .pad)
        #expect(value.base == 11)
        #expect(value[.pad] == 21)
    }
    
    @Test func anOverrideScopedEditCreatesAnOverride() {
        var value = Varying(10)
        value.set(15, for: .watch, scope: .override)
        #expect(value[.watch] == 15)
        #expect(value[.phone] == 10)
    }
    
    @Test func anOverrideEqualToTheBaseIsRemoved() {
        var value = Varying(10, overrides: [.pad: 20])
        value.set(10, for: .pad)
        #expect(value.overrides.isEmpty)
        
        let constructed = Varying(5, overrides: [.mac: 5])
        #expect(constructed.overrides.isEmpty)
    }
    
    @Test func changingTheBaseToMatchAnOverrideRemovesIt() {
        var value = Varying(10, overrides: [.pad: 20])
        value.set(20, for: .phone)
        #expect(value.overrides.isEmpty)
    }
    
    @Test func revertingRemovesTheOverride() {
        var value = Varying(10, overrides: [.pad: 20])
        value.revert(.pad)
        #expect(value[.pad] == 10)
    }
    
    @Test func overridingCopiesTheCurrentValueUntilEdited() {
        var value = Varying(10)
        value.override(for: .pad)
        #expect(value.isOverridden(for: .pad))
        
        value.set(12, for: .pad)
        #expect(value.base == 10)
        #expect(value[.pad] == 12)
    }
    
    @Test func codingOmitsEmptyOverrides() throws {
        let data = try JSONEncoder().encode(Varying(3))
        #expect(String(decoding: data, as: UTF8.self) == #"{"base":3}"#)
        
        let decoded = try JSONDecoder().decode(Varying<Int>.self, from: Data(#"{"base":3,"overrides":{"pad":4}}"#.utf8))
        #expect(decoded == Varying(3, overrides: [.pad: 4]))
    }
}

@Suite struct LocalizedTests {
    private let text = Varying<Localized>(
        ["en-US": "Read the land", "de": "Lies das Land"],
        overrides: [.watch: ["en-US": "Read it"]]
    )
    
    @Test func theOverrideInTheLocaleComesFirst() {
        #expect(text.text(for: .watch, locale: "en-US", source: "en-US") == ResolvedString(text: "Read it", fellBackToSource: false))
    }
    
    @Test func theBaseInTheLocaleComesNext() {
        #expect(text.text(for: .watch, locale: "de", source: "en-US") == ResolvedString(text: "Lies das Land", fellBackToSource: false))
        #expect(text.text(for: .phone, locale: "de", source: "en-US")?.text == "Lies das Land")
    }
    
    @Test func textFallsBackToSourceLocale() {
        let resolved = text.text(for: .phone, locale: "fr", source: "en-US")
        #expect(resolved == ResolvedString(text: "Read the land", fellBackToSource: true))
    }
    
    @Test func theOverrideInTheSourceLocaleComesBeforeTheBase() {
        let resolved = text.text(for: .watch, locale: "fr", source: "en-US")
        #expect(resolved == ResolvedString(text: "Read it", fellBackToSource: true))
    }
    
    @Test func noTextAtAllResolvesToNothing() {
        let empty = Varying<Localized>([:])
        #expect(empty.text(for: .phone, locale: "en-US", source: "en-US") == nil)
    }
    
    @Test func editingAnOverriddenLocaleChangesOnlyTheOverride() {
        var value = text
        value.setText("Read", for: .watch, locale: "en-US")
        #expect(value.base["en-US"] == "Read the land")
        #expect(value.overrides[.watch]?["en-US"] == "Read")
    }
    
    @Test func editingAnotherLocaleOnAnOverriddenClassChangesTheBase() {
        var value = text
        value.setText("Lis la terre", for: .watch, locale: "fr")
        #expect(value.base["fr"] == "Lis la terre")
    }
    
    @Test func anOverrideLocaleEqualToTheBaseIsRemoved() {
        var value = text
        value.setText("Read the land", for: .watch, locale: "en-US")
        #expect(value.overrides.isEmpty)
    }
}
