import Foundation
@testable import StagehandCore
import StagehandModel
import Testing

@MainActor
@Suite struct AutoFitTests {
    private let target = DeviceTable.target("iphone-dynamic-island-large")
    
    private func slide(_ primary: String, de: String? = nil) -> Slide {
        var localized: Localized = ["en-US": primary]
        localized["de"] = de
        return Slide(title: primary, primary: Varying(localized), secondary: Varying([:]), captureKey: Varying("x"))
    }
    
    @Test func slidesThatFitKeepTheStyleSize() {
        let style = Style.fixture()
        let result = AutoFitter(measurer: FakeTextMeasurer()).fit(slides: [slide("Read"), slide("Mark")], style: style, target: target, locale: "en-US", sourceLocale: "en-US")
        #expect(result.sizes[.primary] == style.primary.size[.phone])
        #expect(result.overflowing.isEmpty)
    }
    
    @Test func slidesInASetShareOneSize() throws {
        let style = Style.fixture()
        let short = slide("Read")
        let long = slide("Bring everything along")
        let fitter = AutoFitter(measurer: FakeTextMeasurer())
        
        let together = fitter.fit(slides: [short, long], style: style, target: target, locale: "en-US", sourceLocale: "en-US")
        let alone = fitter.fit(slides: [long], style: style, target: target, locale: "en-US", sourceLocale: "en-US")
        let size = try #require(together.sizes[.primary])
        
        #expect(size < style.primary.size[.phone])
        #expect(size == alone.sizes[.primary])
        #expect(size >= style.primary.size[.phone] * style.autoFitMinimum)
    }
    
    @Test func theSharedSizeNamesTheSlideThatSetIt() throws {
        let style = Style.fixture()
        let short = slide("Read")
        let long = slide("Bring everything along")
        let result = AutoFitter(measurer: FakeTextMeasurer()).fit(slides: [short, long], style: style, target: target, locale: "en-US", sourceLocale: "en-US")
        
        let shrinking = try #require(result.shrinking(.primary, on: short.id))
        #expect(shrinking.cause == long.id)
        #expect(shrinking.fraction < 1)
        #expect(result.shrinking(.secondary, on: short.id) == nil)
    }
    
    /// A slide whose own text fits keeps the template's size when the style fits each slide on its own, so one long
    /// headline (like a slide still saying "Your headline") doesn't shrink every other slide.
    @Test func fittingEachSlideOnItsOwnShrinksOnlyTheOneThatNeedsIt() throws {
        var style = Style.fixture()
        style.autoFitScope = .slide
        let short = slide("Read")
        let long = slide("Bring everything along")
        let result = AutoFitter(measurer: FakeTextMeasurer()).fit(slides: [short, long], style: style, target: target, locale: "en-US", sourceLocale: "en-US")
        
        #expect(result.fitted(for: short.id).sizes[.primary] == style.primary.size[.phone])
        #expect(try #require(result.fitted(for: long.id).sizes[.primary]) < style.primary.size[.phone])
        #expect(result.shrinking(.primary, on: short.id) == nil)
        #expect(result.shrinking(.primary, on: long.id)?.cause == long.id)
    }
    
    @Test func aTemplateSetSavedWithoutAnAutoFitScopeSharesOneSize() throws {
        var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(Style.fixture())) as! [String: Any]
        json.removeValue(forKey: "autoFitScope")
        let style = try JSONDecoder().decode(Style.self, from: JSONSerialization.data(withJSONObject: json))
        
        #expect(style.autoFitScope == .lineup)
    }
    
    @Test func aLongHeadlineIsFlaggedInsteadOfShrinkingPastTheMinimum() throws {
        let style = Style.fixture()
        let long = slide("Supercalifragilisticexpialidocious adventures everywhere you go today")
        let result = AutoFitter(measurer: FakeTextMeasurer()).fit(slides: [long], style: style, target: target, locale: "en-US", sourceLocale: "en-US")
        
        #expect(result.overflowing[long.id] == [.primary])
        #expect(result.sizes[.primary] == style.primary.size[.phone] * style.autoFitMinimum)
    }
    
    @Test func eachLocaleIsFittedOnItsOwn() throws {
        let style = Style.fixture()
        let slide = slide("Read", de: "Lies die Landschaft genau")
        let fitter = AutoFitter(measurer: FakeTextMeasurer())
        
        let english = fitter.fit(slides: [slide], style: style, target: target, locale: "en-US", sourceLocale: "en-US")
        let german = fitter.fit(slides: [slide], style: style, target: target, locale: "de", sourceLocale: "en-US")
        
        #expect(english.sizes[.primary] == style.primary.size[.phone])
        #expect(try #require(german.sizes[.primary]) < style.primary.size[.phone])
    }
    
    @Test func theCacheDoesNotRefitForAMovedDevice() {
        let measurer = FakeTextMeasurer()
        let cache = AutoFitCache(measurer: measurer)
        var slide = slide("Bring everything along")
        let style = Style.fixture()
        
        _ = cache.result(slides: [slide], style: style, target: target, locale: "en-US", sourceLocale: "en-US")
        let calls = measurer.calls
        slide.detachments[.phone] = Detachment(device: DevicePlacement(position: NormPoint(x: 0.4, y: 0.6), width: 0.7))
        _ = cache.result(slides: [slide], style: style, target: target, locale: "en-US", sourceLocale: "en-US")
        
        #expect(measurer.calls == calls)
    }
}
