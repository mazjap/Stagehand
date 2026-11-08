import Foundation
import Observation

/// Makes the `DocumentGroup`'s project documents, holding a new project's creation while the New Project window is
/// open.
///
/// > Warning: SwiftUI calls `makeDocument` for every document, the ones it opens or restores included, and reads the
/// > file into the instance afterward. Its configuration's `fileURL` is `nil` even then, so it can't tell them apart.
/// > Only a creation Stagehand's own New Project command asked for (``requestNewProject()``) waits on the New Project
/// > window; one that waited for an opened file showed the New Project window and left the document's window blank.
@Observable
@MainActor
public final class NewProjectPicker {
    @ObservationIgnored private var continuation: CheckedContinuation<ProjectDocument, any Error>?
    
    /// New Project commands whose `makeDocument` hasn't come yet.
    @ObservationIgnored private var requests = 0
    
    public init() {}
    
    // MARK: - Computed Properties
    
    public var isWaiting: Bool {
        continuation != nil
    }
    
    // MARK: - Functions
    
    /// Marks the next `makeDocument` as a new project, just before the New Project command asks SwiftUI for one.
    public func requestNewProject() {
        requests += 1
    }
    
    /// The document for `makeDocument`. A requested new project shows the New Project window through `present` and
    /// waits for ``finish(with:)`` or ``cancel()``. Anything else (a file being opened or restored) gets an empty
    /// document right away, which SwiftUI reads the file into.
    public func makeDocument(present: () -> Void) async throws -> ProjectDocument {
        guard requests > 0 else {
            return ProjectDocument()
        }
        
        requests -= 1
        
        return try await withCheckedThrowingContinuation { continuation in
            begin(continuation)
            present()
        }
    }
    
    /// Starts waiting for a new project. A creation still waiting is cancelled, so only one waits at a time.
    public func begin(_ continuation: CheckedContinuation<ProjectDocument, any Error>) {
        self.continuation?.resume(throwing: CancellationError())
        self.continuation = continuation
    }
    
    public func finish(with contents: ProjectContents) {
        continuation?.resume(returning: ProjectDocument(contents: contents))
        continuation = nil
    }
    
    public func cancel() {
        continuation?.resume(throwing: CancellationError())
        continuation = nil
    }
}
