import Foundation
import SwiftUI
import UniformTypeIdentifiers

/// A `.stagehandstyle` style, opened with `DocumentGroup` and edited in the same editor as a project.
@Observable
public final class StyleDocument: Document, EditableDocument {
    public static let readableContentTypes: [UTType] = [.stagehandStyle]
    public static let writableContentTypes: [UTType] = [.stagehandStyle]
    
    public var project: Project
    public var captures: CaptureIndex
    public var captureFiles: [CaptureAddress: Data]
    public var fonts: [String: Data]
    public var assets: [String: Data]
    public var bezels: [BezelID: EmbeddedBezel]
    
    /// Where the document is on disk, set by the app's `makeDocument`. It's observable, so a save shows up.
    @ObservationIgnored public var fileConfiguration: URLDocumentConfiguration?
    public private(set) var loadGeneration = 0
    
    public var kind: DocumentKind {
        .style
    }
    
    public init(contents: ProjectContents = StylePackage.newStyle()) {
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
            try StylePackage.read(files: package.packageFiles)
        }
    }
    
    @MainActor
    public func apply(snapshot: sending ProjectContents, previous: sending ProjectContents?) async throws {
        contents = snapshot
        loadGeneration += 1
    }
    
    public func writer(configuration: sending WriteConfiguration) -> sending FileWrapperDocumentWriter<ProjectContents> {
        FileWrapperDocumentWriter(configuration) { snapshot, _ in
            FileWrapper(packageFiles: try StylePackage.files(snapshot))
        }
    }
    
    @MainActor
    public func snapshot(contentType: UTType) async throws -> sending ProjectContents {
        contents
    }
}
