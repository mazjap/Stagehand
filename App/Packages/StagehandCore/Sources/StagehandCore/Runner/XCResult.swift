import Foundation
import StagehandModel

/// The `manifest.json` that `xcresulttool export attachments` writes.
public struct AttachmentManifest: Decodable, Hashable, Sendable {
    public struct Test: Decodable, Hashable, Sendable {
        public var testIdentifier: String
        public var testIdentifierURL: String?
        public var attachments: [Attachment]
    }
    
    public struct Attachment: Decodable, Hashable, Sendable {
        public var exportedFileName: String
        public var suggestedHumanReadableName: String
        public var isAssociatedWithFailure: Bool
        public var deviceName: String?
        public var deviceId: String?
    }
    
    public var tests: [Test]
    
    public init(from decoder: any Decoder) throws {
        self.tests = try decoder.singleValueContainer().decode([Test].self)
    }
    
    public static func parse(_ data: Data) throws -> AttachmentManifest {
        try JSONDecoder().decode(AttachmentManifest.self, from: data)
    }
    
    /// The kit's attachments grouped by capture ID: each image with its metadata and the test that made it.
    public func captures() -> [CapturedAttachment] {
        var groups: [UUID: CapturedAttachment] = [:]
        
        for test in tests {
            for attachment in test.attachments {
                guard let parsed = ShotAttachment.parse(Self.stripExportSuffix(attachment.suggestedHumanReadableName)) else {
                    continue
                }
                
                var group = groups[parsed.captureID] ?? CapturedAttachment(captureID: parsed.captureID, testIdentifier: test.testIdentifier)
                
                if parsed.suffix == ShotAttachment.metadataSuffix {
                    group.metadataFile = attachment.exportedFileName
                } else {
                    group.imageFile = attachment.exportedFileName
                    group.name = parsed.suffix
                }
                
                groups[parsed.captureID] = group
            }
        }
        
        return groups.values.sorted { ($0.name ?? "", $0.captureID.uuidString) < ($1.name ?? "", $1.captureID.uuidString) }
    }
    
    /// Screenshots attached under a plain name, without the capture kit: what MJScreenshotTesting's
    /// `ScreenshotTestCase` and TrekPoint's screenshot tests attach (`XCTAttachment(screenshot:)` named like
    /// `01-level` or `1. Terrain Made Clear`). Failure screenshots, and the kit's own attachments, are left out.
    public func plainScreenshots() -> [PlainAttachment] {
        tests.flatMap { test in
            test.attachments.compactMap { attachment -> PlainAttachment? in
                let name = Self.plainName(attachment.suggestedHumanReadableName)
                let isImage = Self.imageExtensions.contains((attachment.exportedFileName as NSString).pathExtension.lowercased())
                
                guard isImage, !attachment.isAssociatedWithFailure, !name.isEmpty,
                      ShotAttachment.captureID(in: Self.stripExportSuffix(attachment.suggestedHumanReadableName)) == nil else {
                    return nil
                }
                
                return PlainAttachment(name: name, testIdentifier: test.testIdentifier, imageFile: attachment.exportedFileName)
            }
        }
        .sorted { ($0.name, $0.imageFile) < ($1.name, $1.imageFile) }
    }
    
    private static let imageExtensions: Set<String> = ["png", "jpg", "jpeg", "heic"]
    
    /// An attachment's name as the test gave it: without Xcode's export suffix or an image extension.
    static func plainName(_ suggested: String) -> String {
        let stripped = stripExportSuffix(suggested)
        let ext = (stripped as NSString).pathExtension.lowercased()
        return (imageExtensions.contains(ext) ? (stripped as NSString).deletingPathExtension : stripped)
            .trimmingCharacters(in: .whitespaces)
    }
    
    /// Removes what Xcode adds to an attachment's name when exporting.
    ///
    /// Xcode treats whatever follows the name's last dot as an extension and inserts `_<n>_<UUID>` before it, so
    /// `stagehand.<ID>.dark-scene` exports as `stagehand.<ID>_0_<UUID>.dark-scene` (Xcode 27.1).
    static func stripExportSuffix(_ name: String) -> String {
        name.replacing(/_\d+_[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}/, with: "")
    }
}

/// One capture's two attachments.
/// A screenshot a test attached under a plain name, without the kit's metadata.
public struct PlainAttachment: Hashable, Sendable {
    public var name: String
    public var testIdentifier: String
    public var imageFile: String
}

public struct CapturedAttachment: Hashable, Sendable {
    public var captureID: UUID
    public var testIdentifier: String
    public var name: String?
    public var imageFile: String?
    public var metadataFile: String?
}

/// `xcresulttool get test-results tests`.
public struct TestResults: Decodable, Hashable, Sendable {
    public struct Node: Decodable, Hashable, Sendable {
        public var nodeIdentifier: String?
        public var nodeType: String
        public var name: String
        public var result: String?
        public var children: [Node]?
    }
    
    public var testNodes: [Node]
    
    public static func parse(_ output: String) throws -> TestResults {
        try JSONDecoder().decode(TestResults.self, from: Data(output.jsonPortion.utf8))
    }
    
    /// Every failed test case and its failure messages.
    public var failures: [TestFailure] {
        var failures: [TestFailure] = []
        
        func visit(_ node: Node) {
            if node.nodeType == "Test Case", node.result == "Failed" {
                var messages: [String] = []
                
                func collect(_ node: Node) {
                    if node.nodeType == "Failure Message" {
                        messages.append(node.name)
                    }
                    
                    node.children?.forEach(collect)
                }
                
                node.children?.forEach(collect)
                failures.append(TestFailure(testIdentifier: node.nodeIdentifier ?? node.name, messages: messages))
            }
            
            node.children?.forEach(visit)
        }
        
        testNodes.forEach(visit)
        return failures
    }
    
    /// How many test cases ran, and how many passed.
    public var counts: (passed: Int, total: Int) {
        var passed = 0
        var total = 0
        
        func visit(_ node: Node) {
            if node.nodeType == "Test Case" {
                total += 1
                passed += node.result == "Passed" ? 1 : 0
            }
            
            node.children?.forEach(visit)
        }
        
        testNodes.forEach(visit)
        return (passed, total)
    }
}

public struct TestFailure: Hashable, Sendable {
    public var testIdentifier: String
    public var messages: [String]
    
    /// Whether the kit failed the test because the capture wasn't the expected device class (a folded Duo).
    public var isExpectationFailure: Bool {
        messages.contains { $0.contains("stagehand.expectation:") }
    }
}
