import Foundation
import StagehandModel

/// What a folder layout knows about a capture when it picks its path.
public struct ShotPath: Sendable, Hashable {
    public var name: String
    public var locale: String?
    public var deviceClass: DeviceClass?
    public var targetID: String?
    
    public init(name: String, locale: String?, deviceClass: DeviceClass?, targetID: String?) {
        self.name = name
        self.locale = locale
        self.deviceClass = deviceClass
        self.targetID = targetID
    }
    
    public init(shot: Shot) {
        self.init(name: shot.name, locale: shot.locale, deviceClass: shot.deviceClass, targetID: shot.targetID)
    }
}

/// Where captures are saved inside a folder.
public enum FolderLayout: Sendable {
    /// `<locale>/<device class>/<name>.png`.
    case byLocaleAndClass
    
    /// A path relative to the folder's root, from the capture.
    case custom(@Sendable (ShotPath) -> String)
    
    // MARK: - Functions
    
    /// The path of a capture, relative to the folder's root.
    public func relativePath(for path: ShotPath) -> String {
        switch self {
        case .byLocaleAndClass:
            let locale = path.locale ?? "unknown-locale"
            let deviceClass = path.deviceClass?.rawValue ?? "unclassified"
            return "\(locale)/\(deviceClass)/\(path.name).png"
        case let .custom(makePath):
            return makePath(path)
        }
    }
}

/// A folder captures are also saved into, when the process can write there (the simulator, or a Mac).
public struct FolderOutput: Sendable {
    public var root: URL
    public var layout: FolderLayout
    
    public init(root: URL, layout: FolderLayout = .byLocaleAndClass) {
        self.root = root
        self.layout = layout
    }
    
    // MARK: - Functions
    
    /// The file a capture is saved to.
    public func url(for path: ShotPath) -> URL {
        root.appending(path: layout.relativePath(for: path))
    }
    
    /// Writes a capture's PNG, creating folders as needed.
    public func write(_ png: Data, for path: ShotPath) throws -> URL {
        let url = url(for: path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try png.write(to: url, options: .atomic)
        return url
    }
}
