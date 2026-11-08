import CoreGraphics
import Foundation
import StagehandModel

public enum CaptureImportError: Error, Hashable, LocalizedError {
    case undecodable(String)
    case unknownSize(String, width: Int, height: Int)
    case wrongClass(String, expected: DeviceClass, found: DeviceClass)
    
    /// Dropped on the contact sheet rather than a cell, with a name whose capture key no slide uses.
    case noMatchingSlide(String, key: String)
    
    public var fileName: String {
        switch self {
        case let .undecodable(name), let .unknownSize(name, _, _), let .wrongClass(name, _, _), let .noMatchingSlide(name, _): name
        }
    }
    
    public var errorDescription: String? {
        switch self {
        case let .undecodable(name):
            "\(name) isn't an image Stagehand can read."
        case let .unknownSize(name, width, height):
            "\(name) is \(width) × \(height), which isn't a size in devices.json."
        case let .wrongClass(name, expected, found):
            "\(name) is a \(found.displayName) screenshot, not \(expected.displayName)."
        case let .noMatchingSlide(name, key):
            "\(name) doesn't match a slide: its name makes the capture key \u{201C}\(key)\u{201D}, which no slide uses. Drop it on a slide's cell or on the canvas, or name it after the slide's capture key."
        }
    }
}

/// Classifies dropped screenshots by pixel size and turns them into capture records.
public enum CaptureImporter {
    /// Where a drop landed.
    public enum Destination: Hashable, Sendable {
        /// On a cell: the capture takes the cell's key and device class.
        case cell(key: String, deviceClass: DeviceClass)
        
        /// On the contact sheet: the class comes from the size and the key from the file name.
        case sheet
        
        /// From a folder of screenshots (like `AppStoreScreenshots/`, which FlaskMaster's tests write): like the
        /// sheet, but a key no slide uses yet is kept, for choosing in a slide's Capture Key menu.
        case folder
    }
    
    public struct Imported: Hashable, Sendable {
        public var record: CaptureRecord
        public var data: Data
    }
    
    /// The capture key for a file name: `Read the Land.png` becomes `read-the-land`.
    public static func captureKey(fromFileName name: String) -> String {
        (name as NSString).deletingPathExtension.slugified
    }
    
    /// Every image under a folder, its subfolders included (a device's folder each, like `iPhone/` and `iPad/`),
    /// skipping hidden files and folders.
    public static func imageFiles(in folder: URL, fileManager: any FileManagerProvider) -> [URL] {
        let extensions: Set<String> = ["png", "jpg", "jpeg", "heic"]
        let contents = ((try? fileManager.contentsOfDirectory(at: folder)) ?? [])
            .filter { !$0.lastPathComponent.hasPrefix(".") }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
        
        return contents.flatMap { url -> [URL] in
            if fileManager.isDirectory(at: url) {
                imageFiles(in: url, fileManager: fileManager)
            } else if extensions.contains(url.pathExtension.lowercased()) {
                [url]
            } else {
                []
            }
        }
    }
    
    /// Classifies one dropped image.
    public static func importImage(
        _ data: Data,
        fileName: String,
        destination: Destination,
        locale: LocaleID,
        existing: CaptureIndex,
        now: Date,
        table: DeviceTable = .standard
    ) -> Result<Imported, CaptureImportError> {
        guard let size = CGImage.pixelSize(of: data) else {
            return .failure(.undecodable(fileName))
        }
        
        guard let classification = table.classify(width: size.width, height: size.height) else {
            return .failure(.unknownSize(fileName, width: size.width, height: size.height))
        }
        
        let key: String
        
        switch destination {
        case let .cell(cellKey, deviceClass):
            guard classification.deviceClass == deviceClass else {
                return .failure(.wrongClass(fileName, expected: deviceClass, found: classification.deviceClass))
            }
            
            key = cellKey
        case .sheet, .folder:
            key = captureKey(fromFileName: fileName)
        }
        
        let address = CaptureAddress(key: key, deviceClass: classification.deviceClass, locale: locale)
        let record = CaptureRecord(
            address: address,
            pixelWidth: size.width,
            pixelHeight: size.height,
            targetID: classification.target.id,
            source: .dropped,
            importedAt: now,
            revision: (existing.records[address]?.revision ?? 0) + 1
        )
        
        return .success(Imported(record: record, data: data))
    }
}
