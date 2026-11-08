import Foundation
import SwiftUI
import Observation

/// What a document holds, so one editor edits both projects and styles.
public enum DocumentKind: Hashable, Sendable {
    /// A project: exported, captured and uploaded.
    case project
    
    /// A style, designed against its preview slides. It's never exported.
    case style
}

/// A document the editor can edit. Projects and styles both present their contents as ``ProjectContents``; a style
/// document's are its style, its preview set and slides, and its placeholder screens as captures.
///
/// > Warning: Don't make this `@MainActor`. Conforming to it would isolate the whole document class, which breaks
/// > its `Document` conformance (reading and writing run in the background).
public protocol EditableDocument: AnyObject, Observable {
    var kind: DocumentKind { get }
    var project: Project { get set }
    var captures: CaptureIndex { get set }
    var captureFiles: [CaptureAddress: Data] { get set }
    var fonts: [String: Data] { get set }
    var assets: [String: Data] { get set }
    var bezels: [BezelID: EmbeddedBezel] { get set }
    
    /// Bumped each time a snapshot is applied from disk.
    var loadGeneration: Int { get }
    
    /// Why the file couldn't be read, in which case the document's contents aren't the file's and it refuses to save.
    var loadFailure: DocumentError? { get }
    
    /// Where the document is on disk (`nil` until a new one is saved), as `makeDocument` was given it.
    var fileConfiguration: URLDocumentConfiguration? { get }
}

extension EditableDocument {
    /// Everything in the document, as one value. It's also what each undo step restores.
    public var contents: ProjectContents {
        get {
            ProjectContents(project: project, captures: captures, captureFiles: captureFiles, fonts: fonts, assets: assets, bezels: bezels)
        }
        set {
            if project != newValue.project { project = newValue.project }
            if captures != newValue.captures { captures = newValue.captures }
            if captureFiles != newValue.captureFiles { captureFiles = newValue.captureFiles }
            if fonts != newValue.fonts { fonts = newValue.fonts }
            if assets != newValue.assets { assets = newValue.assets }
            if bezels != newValue.bezels { bezels = newValue.bezels }
        }
    }
}

extension FileWrapper {
    /// A package of files, from relative paths like `fonts/A.ttf`.
    public convenience init(packageFiles files: [String: Data]) {
        self.init(directoryWithFileWrappers: [:])
        
        for (path, data) in files.sorted(by: { $0.key < $1.key }) {
            var folder: FileWrapper = self
            let components = path.split(separator: "/").map(String.init)
            
            for name in components.dropLast() {
                if let existing = folder.fileWrappers?[name], existing.isDirectory {
                    folder = existing
                } else {
                    let created = FileWrapper(directoryWithFileWrappers: [:])
                    created.preferredFilename = name
                    folder.addFileWrapper(created)
                    folder = created
                }
            }
            
            let file = FileWrapper(regularFileWithContents: data)
            file.preferredFilename = components.last
            folder.addFileWrapper(file)
        }
    }
    
    /// Every regular file in a package, by relative path.
    public var packageFiles: [String: Data] {
        var files: [String: Data] = [:]
        
        func visit(_ wrapper: FileWrapper, prefix: String) {
            for (name, child) in wrapper.fileWrappers ?? [:] where !name.hasPrefix(".") {
                if child.isDirectory {
                    visit(child, prefix: prefix + name + "/")
                } else if let data = child.regularFileContents {
                    files[prefix + name] = data
                }
            }
        }
        
        visit(self, prefix: "")
        return files
    }
}
