import Foundation
import OSLog
import StagehandModel

/// A style in the library.
public struct LibraryStyle: Hashable, Sendable, Identifiable {
    public var url: URL
    public var styleID: UUID
    public var name: String
    public var version: Int
    
    public var id: URL {
        url
    }
}

public enum StyleLibraryError: Error, Equatable, LocalizedError {
    case notFound(String)
    case unreadable(String, reason: String)
    case writeFailed(String)
    
    public var errorDescription: String? {
        switch self {
        case let .notFound(name): "\(name) isn't in the library."
        case let .unreadable(name, reason): "\(name) couldn't be read: \(reason)"
        case let .writeFailed(reason): "The style couldn't be saved to the library: \(reason)"
        }
    }
}

/// The library's `Styles/` folder: styles that aren't tied to a project, as `.stagehandstyle` packages.
public struct StyleLibrary: Sendable {
    public static let folderName = "Styles"
    
    public var folder: URL
    private let fileManager: any FileManagerProvider
    
    public init(libraryURL: URL, fileManager: any FileManagerProvider) {
        self.folder = libraryURL.appending(path: Self.folderName, directoryHint: .isDirectory)
        self.fileManager = fileManager
    }
    
    // MARK: - Functions
    
    /// Every style, by name.
    public func list() -> [LibraryStyle] {
        guard let urls = try? fileManager.contentsOfDirectory(at: folder) else {
            return []
        }
        
        return urls.filter { $0.pathExtension == "stagehandstyle" }.compactMap { url in
            do {
                let data = try fileManager.read(url.appending(path: StylePackage.styleFile))
                let file = try FormatMigration.decode(StyleFile.self, from: data, fileName: StylePackage.styleFile, currentVersion: StyleFile.currentFormatVersion, steps: StylePackage.styleSteps)
                return LibraryStyle(url: url, styleID: file.style.id, name: file.style.name, version: file.style.version)
            } catch {
                Logger.library.error("Skipping \(url.lastPathComponent, privacy: .public): \(error.localizedDescription, privacy: .public)")
                return nil
            }
        }
        .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
    
    /// The library's copy of a style, by ID.
    public func style(id: UUID) -> LibraryStyle? {
        list().first { $0.styleID == id }
    }
    
    /// A style package's contents.
    public func load(_ style: LibraryStyle) throws(StyleLibraryError) -> ProjectContents {
        do {
            return try StylePackage.read(files: readFiles(in: style.url))
        } catch {
            throw .unreadable(style.name, reason: error.localizedDescription)
        }
    }
    
    /// Saves a style as a new library style, or as a new version of the one with its ID, and returns where it came
    /// from for the project's `basedOn`.
    @discardableResult
    public func save(_ style: Style, fonts: [String: Data], bezels: [BezelID: EmbeddedBezel] = [:], asNewVersion: Bool) throws(StyleLibraryError) -> BaseStyle {
        var saved = style
        let existing = asNewVersion ? self.style(id: style.id) : nil
        
        if let existing {
            saved.version = existing.version + 1
        } else {
            saved.id = UUID()
            saved.version = 1
        }
        
        var contents = StylePackage.newStyle(named: saved.name, from: saved)
        
        // Keep the library's own preview slides and screens when replacing a version.
        if let existing, let previous = try? load(existing) {
            contents.project.slides = previous.project.slides
            contents.project.slideOrder = previous.project.slideOrder
            contents.project.devices = previous.project.devices
            contents.project.targets = previous.project.targets
            contents.captures = previous.captures
            contents.captureFiles = previous.captureFiles
        }
        
        contents.fonts = fonts
        contents.bezels = bezels
        let url = existing?.url ?? uniqueURL(for: saved.name)
        
        do {
            if fileManager.fileExists(at: url) {
                try fileManager.removeItem(at: url)
            }
            
            for (path, data) in try StylePackage.files(contents) {
                try fileManager.write(data, to: url.appending(path: path))
            }
        } catch {
            throw .writeFailed(error.localizedDescription)
        }
        
        return BaseStyle(styleID: saved.id, version: saved.version, snapshot: saved)
    }
    
    // MARK: - Helpers
    
    private func uniqueURL(for name: String) -> URL {
        let base = name.isEmpty ? "Untitled Style" : name
        var url = folder.appending(path: "\(base).stagehandstyle", directoryHint: .isDirectory)
        var number = 2
        
        while fileManager.fileExists(at: url) {
            url = folder.appending(path: "\(base) \(number).stagehandstyle", directoryHint: .isDirectory)
            number += 1
        }
        
        return url
    }
    
    private func readFiles(in url: URL, prefix: String = "") throws -> [String: Data] {
        var files: [String: Data] = [:]
        
        for child in try fileManager.contentsOfDirectory(at: url) {
            let path = prefix + child.lastPathComponent
            
            if fileManager.isDirectory(at: child) {
                files.merge(try readFiles(in: child, prefix: path + "/")) { $1 }
            } else {
                files[path] = try fileManager.read(child)
            }
        }
        
        return files
    }
}
