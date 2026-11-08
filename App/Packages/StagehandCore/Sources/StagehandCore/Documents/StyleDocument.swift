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
    
    /// Why the file couldn't be read. While it's set, the window shows this instead of the editor, and saving is refused.
    public private(set) var loadFailure: DocumentError?
    
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
    
    // MARK: - Functions
    
    /// Reads a package, catching what goes wrong so the document can show it.
    public static func load(_ package: FileWrapper) -> DocumentSnapshot {
        let files = package.packageFiles
        
        return DocumentSnapshot { () throws(DocumentError) in
            try StylePackage.read(files: files)
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
        FileWrapperDocumentWriter(configuration) { snapshot, _ in
            FileWrapper(packageFiles: try StylePackage.files(try snapshot.contentsToWrite()))
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
