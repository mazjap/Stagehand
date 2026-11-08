import Foundation
@testable import StagehandCore
import Testing

/// Making the `DocumentGroup`'s project documents.
@MainActor
@Suite struct NewProjectPickerTests {
    /// Regression test: `makeDocument` always waited on the New Project window, but SwiftUI calls it for documents
    /// it opens too, with no file URL yet. Opening a saved project showed New Project and left its window blank.
    @Test func openingAFileDoesntWaitOnNewProject() async throws {
        let picker = NewProjectPicker()
        var presented = false
        
        let document = try await picker.makeDocument { presented = true }
        
        #expect(!presented)
        #expect(!picker.isWaiting)
        #expect(document.project.slideOrder.isEmpty)
    }
    
    @Test func onlyTheRequestedCreationWaits() async throws {
        let picker = NewProjectPicker()
        picker.requestNewProject()
        let creation = Task { _ = try await picker.makeDocument {} }
        
        while !picker.isWaiting {
            await Task.yield()
        }
        
        // A file opened while New Project is open doesn't take its place.
        _ = try await picker.makeDocument {}
        #expect(picker.isWaiting)
        
        picker.cancel()
        _ = await creation.result
    }
    
    @Test func aNewDocumentWaitsForTheChosenContents() async throws {
        let picker = NewProjectPicker()
        let presented = Flag()
        let contents = ProjectContents(project: .fixture())
        picker.requestNewProject()
        let project = Task { try await picker.makeDocument { presented.isSet = true }.project }
        
        while !picker.isWaiting {
            await Task.yield()
        }
        
        #expect(presented.isSet)
        picker.finish(with: contents)
        
        #expect(try await project.value == contents.project)
        #expect(!picker.isWaiting)
    }
    
    @Test func cancellingThrows() async {
        let picker = NewProjectPicker()
        picker.requestNewProject()
        let creation = Task { _ = try await picker.makeDocument {} }
        
        while !picker.isWaiting {
            await Task.yield()
        }
        
        picker.cancel()
        
        await #expect(throws: CancellationError.self) {
            try await creation.value
        }
    }
}

@MainActor
private final class Flag {
    var isSet = false
}
