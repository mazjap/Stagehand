import Foundation
import StagehandCore
import Testing
import UniformTypeIdentifiers

/// The app's `Info.plist` declares what its `DocumentGroup`s open and create.
@MainActor
@Suite struct DocumentTypeTests {
    /// Regression test: only the project type was in `CFBundleDocumentTypes`, though a second `DocumentGroup` edits
    /// styles, so the system's document controller didn't know the app edits them.
    @Test func everyDocumentGroupTypeIsDeclaredAsAnEditor() throws {
        let types = try #require(Bundle.main.infoDictionary?["CFBundleDocumentTypes"] as? [[String: Any]])
        
        for type in [UTType.stagehandProject, .stagehandStyle] {
            let declaration = types.first { ($0["LSItemContentTypes"] as? [String])?.contains(type.identifier) == true }
            #expect(declaration?["CFBundleTypeRole"] as? String == "Editor", "\(type.identifier) isn't declared as an editor")
        }
    }
}
