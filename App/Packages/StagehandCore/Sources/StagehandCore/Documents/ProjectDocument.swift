import Foundation
import SwiftUI
import UniformTypeIdentifiers

/// A `.stagehand` project, opened with `DocumentGroup`.
///
/// Edits go through ``ProjectCoordinator``, which registers undo for each one. SwiftUI relies on the undo stack to
/// detect unsaved changes, so an edit without undo isn't autosaved.
@Observable
public final class ProjectDocument: Document, EditableDocument {
    public static let readableContentTypes: [UTType] = [.stagehandProject]
    public static let writableContentTypes: [UTType] = [.stagehandProject]
    
    public var project: Project
    public var captures: CaptureIndex
    public var captureFiles: [CaptureAddress: Data]
    public var fonts: [String: Data]
    public var assets: [String: Data]
    public var bezels: [BezelID: EmbeddedBezel]
    
    /// Where the document is on disk, set by the app's `makeDocument`. It's observable, so a save shows up.
    @ObservationIgnored public var fileConfiguration: URLDocumentConfiguration?
    
    /// Bumped each time a new snapshot is applied from disk, so coordinators can reload derived state.
    public private(set) var loadGeneration = 0
    
    /// Why the file couldn't be read. While it's set, the window shows this instead of the editor, and saving is refused.
    public private(set) var loadFailure: DocumentError?
    
    public var kind: DocumentKind {
        .project
    }
    
    public init(contents: ProjectContents = ProjectContents(project: .empty())) {
        self.project = contents.project
        self.captures = contents.captures
        self.captureFiles = contents.captureFiles
        self.fonts = contents.fonts
        self.assets = contents.assets
        self.bezels = contents.bezels
    }
    
    // MARK: - Functions
    
    /// Reads a package, catching what goes wrong so the document can show it.
    public static func load(_ package: FileWrapper) -> DocumentSnapshot {
        DocumentSnapshot { () throws(DocumentError) in
            try ProjectPackage.read(package)
        }
    }
    
    // MARK: - Document
    
    public func reader(configuration: sending ReadConfiguration) -> sending FileWrapperDocumentReader<DocumentSnapshot> {
        FileWrapperDocumentReader(configuration) { package in
            Self.load(package)
        }
    }
    
    @MainActor
    public func apply(snapshot: sending DocumentSnapshot, previous: sending DocumentSnapshot?) async throws {
        switch snapshot {
        case let .contents(contents):
            self.contents = contents
            loadFailure = nil
            loadGeneration += 1
        case let .unreadable(error):
            loadFailure = error
        }
    }
    
    public func writer(configuration: sending WriteConfiguration) -> sending FileWrapperDocumentWriter<DocumentSnapshot> {
        FileWrapperDocumentWriter(configuration) { snapshot, previous in
            try ProjectPackage.write(try snapshot.contentsToWrite(), previous: previous)
        }
    }
    
    @MainActor
    public func snapshot(contentType: UTType) async throws -> sending DocumentSnapshot {
        if let loadFailure {
            throw loadFailure
        }
        
        return .contents(contents)
    }
}
