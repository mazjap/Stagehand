import CoreGraphics
import CryptoKit
import Dependencies
import Foundation
import OSLog
import StagehandModel

/// The library's `Bezels/` folder: each bezel's PNG with its `bezel.json`, and a default per device class.
///
/// Bezels are Apple's files, from Apple Design Resources. They live in the library, never in the repository.
public struct BezelLibrary: Sendable {
    public static let folderName = "Bezels"
    static let defaultsFile = "defaults.json"
    static let sourcesFile = "sources.json"
    
    public var folder: URL
    private let fileManager: any FileManagerProvider
    
    public init(libraryURL: URL, fileManager: any FileManagerProvider) {
        self.folder = libraryURL.appending(path: Self.folderName, directoryHint: .isDirectory)
        self.fileManager = fileManager
    }
    
    // MARK: - Functions
    
    /// Every bezel and the defaults.
    public func load() -> BezelCatalog {
        guard fileManager.isDirectory(at: folder), let urls = try? fileManager.contentsOfDirectory(at: folder) else {
            return .empty
        }
        
        var bezels: [BezelID: BezelInfo] = [:]
        let decoder = FormatMigration.makeDecoder()
        
        for url in urls where url.pathExtension == "json" && ![Self.defaultsFile, Self.sourcesFile].contains(url.lastPathComponent) {
            do {
                let info = try decoder.decode(BezelInfo.self, from: fileManager.read(url))
                bezels[info.id] = info
            } catch {
                Logger.bezels.error("Skipping \(url.lastPathComponent, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }
        
        let defaults = (try? decoder.decode([DeviceClass: BezelID].self, from: fileManager.read(folder.appending(path: Self.defaultsFile)))) ?? [:]
        var resolvedDefaults = defaults.filter { bezels[$0.value] != nil }
        
        // A class with exactly one bezel uses it by default.
        for deviceClass in DeviceClass.allCases where resolvedDefaults[deviceClass] == nil {
            let matching = bezels.values.filter { $0.deviceClass == deviceClass }
            
            if matching.count == 1 {
                resolvedDefaults[deviceClass] = matching[0].id
            }
        }
        
        return BezelCatalog(bezels: bezels, defaults: resolvedDefaults)
    }
    
    /// Imports a bezel PNG: finds its screen, copies it into the library and writes its `bezel.json`.
    ///
    /// An imported bezel is never overwritten, since templates pin bezels by ID. The same image again returns the
    /// bezel already there, and a different image with the same name (an updated file from Apple) gets an ID of its
    /// own, ending in part of its checksum.
    public func importBezel(
        data: Data,
        name: String,
        deviceClass: DeviceClass,
        model: String,
        color: String,
        importedAt: Date? = nil,
        source: BezelSourceInfo? = nil
    ) throws(BezelImportError) -> BezelInfo {
        guard let image = CGImage.decode(data) else {
            throw .undecodable(name)
        }
        
        let base = "\(deviceClass.rawValue)-\(name.slugified)"
        let checksum = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined().prefix(8)
        
        for id in [base, "\(base)-\(checksum)"] {
            guard fileManager.fileExists(at: infoURL(for: id)) else {
                return try write(data: data, image: image, id: id, name: name, deviceClass: deviceClass, model: model, color: color, importedAt: importedAt, source: source)
            }
            
            if (try? fileManager.read(imageURL(for: id))) == data,
               let existing = try? FormatMigration.makeDecoder().decode(BezelInfo.self, from: fileManager.read(infoURL(for: id))) {
                return existing
            }
        }
        
        throw .writeFailed("\(name) was already imported twice with different images")
    }
    
    private func write(
        data: Data,
        image: CGImage,
        id: BezelID,
        name: String,
        deviceClass: DeviceClass,
        model: String,
        color: String,
        importedAt: Date?,
        source: BezelSourceInfo?
    ) throws(BezelImportError) -> BezelInfo {
        let detection = try BezelDetector.detect(in: image, name: name)
        let info = BezelInfo(
            id: id,
            name: name,
            deviceClass: deviceClass,
            model: model,
            color: color,
            imageWidth: image.width,
            imageHeight: image.height,
            screenRect: detection.screenRect,
            importedAt: importedAt,
            source: source
        )
        
        do {
            try fileManager.write(data, to: imageURL(for: id))
            try fileManager.write(FormatMigration.makeEncoder().encode(info), to: infoURL(for: id))
        } catch {
            throw .writeFailed(error.localizedDescription)
        }
        
        return info
    }
    
    /// The version of each Apple disk image last installed, by its URL, from `sources.json`.
    public func installedVersions() -> [URL: String] {
        let decoded = (try? FormatMigration.makeDecoder().decode([String: String].self, from: fileManager.read(folder.appending(path: Self.sourcesFile)))) ?? [:]
        return Dictionary(uniqueKeysWithValues: decoded.compactMap { key, value in URL(string: key).map { ($0, value) } })
    }
    
    public func recordInstalled(_ url: URL, version: String) throws {
        var versions = installedVersions()
        versions[url] = version
        let encoded = Dictionary(uniqueKeysWithValues: versions.map { ($0.key.absoluteString, $0.value) })
        try fileManager.write(FormatMigration.makeEncoder().encode(encoded), to: folder.appending(path: Self.sourcesFile))
    }
    
    /// Makes a bezel the default for its class.
    public func setDefault(_ id: BezelID?, for deviceClass: DeviceClass) throws {
        let url = folder.appending(path: Self.defaultsFile)
        var defaults = (try? FormatMigration.makeDecoder().decode([DeviceClass: BezelID].self, from: fileManager.read(url))) ?? [:]
        defaults[deviceClass] = id
        try fileManager.write(FormatMigration.makeEncoder().encode(defaults), to: url)
    }
    
    public func remove(_ id: BezelID) throws {
        try? fileManager.removeItem(at: imageURL(for: id))
        try fileManager.removeItem(at: infoURL(for: id))
    }
    
    func infoURL(for id: BezelID) -> URL {
        folder.appending(path: "\(id).json")
    }
    
    public func imageURL(for id: BezelID) -> URL {
        folder.appending(path: "\(id).png")
    }
    
    /// A bezel's PNG file, for embedding in a project.
    public func imageData(for id: BezelID) throws -> Data {
        try fileManager.read(imageURL(for: id))
    }
    
    /// A bezel's image.
    public func image(for id: BezelID) -> CGImage? {
        (try? fileManager.read(imageURL(for: id))).flatMap(CGImage.decode)
    }
    
    /// A bezel's screen mask, found again from its image.
    public func mask(for id: BezelID) -> CGImage? {
        image(for: id).flatMap { try? BezelDetector.detect(in: $0).mask }
    }
}
