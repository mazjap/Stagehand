import Foundation
@testable import StagehandCore
import StagehandModel
import Testing

/// Parsing pinned to output recorded from a real run of the fixture app (Xcode 27.1). Refresh after each Xcode update.
@Suite struct RunnerParsingTests {
    private func fixture(_ name: String) -> String {
        String(decoding: TestResources.data("xcresult/\(name)"), as: UTF8.self)
    }
    
    @Test func xcodebuildListHasSchemesAndTargets() throws {
        let list = try XcodebuildList.parse(fixture("xcodebuild-list.json"))
        #expect(list.schemes.contains("StagehandFixtureApp"))
        #expect(list.targets == ["StagehandFixtureApp", "StagehandFixtureAppScreenshots"])
    }
    
    @Test func xcodebuildListSkipsLogLinesBeforeTheJSON() throws {
        let list = try XcodebuildList.parse("Command line invocation:\n    xcodebuild -list\n" + fixture("xcodebuild-list.json"))
        #expect(!list.schemes.isEmpty)
    }
    
    @Test func simctlDeviceTypesAndRuntimesParse() throws {
        let list = try SimctlList.parse(fixture("simctl-devicetypes-runtimes.json"))
        let duo = try #require(list.devicetypes?.first { $0.identifier.hasSuffix("iPhone-Duo") })
        #expect(duo.modelIdentifier == "iPhone19,4")
        #expect(list.runtimes(supporting: duo.identifier).map(\.version) == ["27.1"])
    }
    
    @Test func simctlDevicesParse() throws {
        let list = try SimctlList.parse(fixture("simctl-devices.json"))
        let device = try #require(list.device(named: "Stagehand iphone-dynamic-island-large", runtime: "com.apple.CoreSimulator.SimRuntime.iOS-27-0"))
        #expect(device.deviceTypeIdentifier == "com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro-Max")
    }
    
    @Test func attachmentsPairByCaptureID() throws {
        let manifest = try AttachmentManifest.parse(TestResources.data("xcresult/attachments-manifest.json"))
        let captures = manifest.captures()
        
        #expect(captures.map(\.name) == ["dark-scene", "light-scene"])
        #expect(captures.allSatisfy { $0.imageFile?.hasSuffix(".png") == true && $0.metadataFile?.hasSuffix(".json") == true })
        #expect(captures[0].testIdentifier == "FixtureScreenshots/testDarkScene()")
    }
    
    @Test func exportSuffixesAreStripped() {
        let exported = "stagehand.864184C9-C115-4883-AEBA-0FC24C8B4072_0_DAFD9F0F-A4F1-4172-8BBE-A8A032B9D702.dark-scene"
        #expect(AttachmentManifest.stripExportSuffix(exported) == "stagehand.864184C9-C115-4883-AEBA-0FC24C8B4072.dark-scene")
    }
    
    @Test func passedResultsHaveNoFailures() throws {
        let results = try TestResults.parse(fixture("test-results-passed.json"))
        #expect(results.failures.isEmpty)
        #expect(results.counts.passed == 2)
    }
    
    @Test func anExpectationFailureIsRecognized() throws {
        let results = try TestResults.parse(fixture("test-results-expectation-failed.json"))
        let failure = try #require(results.failures.first)
        #expect(failure.isExpectationFailure)
        #expect(failure.messages.first?.contains("expected duoInner but captured phone") == true)
    }
}
