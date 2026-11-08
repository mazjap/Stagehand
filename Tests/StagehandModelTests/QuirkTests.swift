import Foundation
import StagehandModel
import Testing

@Suite struct QuirkTests {
    private let quirk = Quirk.all.first { $0.id == "duo-inner-rotated-180" }!
    
    @Test func appliesToTheDuoInnerDisplayOnIOS27_1() {
        #expect(quirk.applies(model: "iPhone19,4", runtime: RuntimeVersion("27.1"), deviceClass: .duoInner))
    }
    
    @Test func doesNotApplyToTheOuterDisplay() {
        #expect(!quirk.applies(model: "iPhone19,4", runtime: RuntimeVersion("27.1"), deviceClass: .duoOuter))
    }
    
    @Test func doesNotApplyToOtherModels() {
        #expect(!quirk.applies(model: "iPhone18,2", runtime: RuntimeVersion("27.1"), deviceClass: .duoInner))
        #expect(!quirk.applies(model: nil, runtime: RuntimeVersion("27.1"), deviceClass: .duoInner))
    }
    
    @Test func stillAppliesToNewerRuntimesAndFlagsThem() {
        var unfixed = quirk
        unfixed.fixedIn = nil
        #expect(unfixed.applies(model: "iPhone19,4", runtime: RuntimeVersion("27.2"), deviceClass: .duoInner))
        #expect(unfixed.isBeyondObserved(RuntimeVersion("27.2")))
        #expect(!unfixed.isBeyondObserved(RuntimeVersion("27.1")))
    }
    
    /// Regression test: the iPhone Duo's iOS 27.2 simulator takes its inner display right side up, so turning its
    /// screenshots would put them upside down.
    @Test func theDuoInnerDisplayIsFixedOnIOS27_2() {
        #expect(!quirk.applies(model: "iPhone19,4", runtime: RuntimeVersion("27.2"), deviceClass: .duoInner))
    }
    
    @Test func stopsApplyingOnceFixed() {
        var fixed = quirk
        fixed.fixedIn = RuntimeVersion("27.3")
        #expect(fixed.applies(model: "iPhone19,4", runtime: RuntimeVersion("27.2.1"), deviceClass: .duoInner))
        #expect(!fixed.applies(model: "iPhone19,4", runtime: RuntimeVersion("27.3"), deviceClass: .duoInner))
    }
    
    @Test func runtimeVersionsCompareNumerically() {
        #expect(RuntimeVersion("27.10")! > RuntimeVersion("27.9")!)
        #expect(RuntimeVersion("27.1")! == RuntimeVersion("27.1.0")!)
        #expect(RuntimeVersion("abc") == nil)
    }
}
