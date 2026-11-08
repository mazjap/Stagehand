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
    
    // MARK: - Document
    
    public func reader(configuration: sending ReadConfiguration) -> sending FileWrapperDocumentReader<ProjectContents> {
        FileWrapperDocumentReader(configuration) { package in
            try ProjectPackage.read(package)
        }
    }
    
    @MainActor
    public func apply(snapshot: sending ProjectContents, previous: sending ProjectContents?) async throws {
        contents = snapshot
        loadGeneration += 1
    }
    
    public func writer(configuration: sending WriteConfiguration) -> sending FileWrapperDocumentWriter<ProjectContents> {
        FileWrapperDocumentWriter(configuration) { snapshot, previous in
            try ProjectPackage.write(snapshot, previous: previous)
        }
    }
    
    @MainActor
    public func snapshot(contentType: UTType) async throws -> sending ProjectContents {
        contents
    }
}
