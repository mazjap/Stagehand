import CoreGraphics
import Foundation
import OSLog
import StagehandModel

/// A disk image downloaded from Apple Design Resources, waiting for its license to be agreed to.
public struct DownloadedBezels: Hashable, Sendable {
    public var product: AppleBezelProduct
    public var file: URL
    public var version: String?
    
    /// The disk image's license agreement, which has to be agreed to before it's opened. `nil` when it has none.
    public var license: String?
}

/// Downloads a product's bezels from Apple Design Resources and imports every PNG in it into the library.
///
/// Mounting runs `hdiutil`, so installing is Mac-only; the iPad gets the bezels through the iCloud library.
///
/// > Warning: Apple's disk images carry a license agreement. ``download(_:progress:)`` reads it without opening the
/// > image, and ``install(_:now:)`` (which agrees to it while mounting) only runs after the user clicks Agree.
public struct BezelDownloader: Sendable {
    private let library: BezelLibrary
    private let downloads: any BezelDownloadProvider
    private let processes: any ProcessRunnerProvider
    private let fileManager: any FileManagerProvider
    private let workFolder: URL
    
    public init(
        library: BezelLibrary,
        downloads: any BezelDownloadProvider,
        processes: any ProcessRunnerProvider,
        fileManager: any FileManagerProvider,
        workFolder: URL
    ) {
        self.library = library
        self.downloads = downloads
        self.processes = processes
        self.fileManager = fileManager
        self.workFolder = workFolder
    }
    
    // MARK: - Functions
    
    /// Downloads a product's disk image and reads its license agreement.
    public func download(_ product: AppleBezelProduct, progress: @escaping @Sendable (Double) -> Void) async throws -> DownloadedBezels {
        let file = workFolder.appending(path: product.url.lastPathComponent)
        let version = try await downloads.download(product.url, to: file, progress: progress)
        let license = try await license(of: file)
        return DownloadedBezels(product: product, file: file, version: version, license: license)
    }
    
    /// The disk image's license text, read from its resources without mounting it.
    public func license(of file: URL) async throws -> String? {
        let output = try await processes.run(Command("/usr/bin/hdiutil", ["udifderez", "-xml", file.path(percentEncoded: false)]))
        
        guard output.succeeded,
              let plist = try? PropertyListSerialization.propertyList(from: Data(output.stdout.utf8), format: nil) as? [String: Any],
              let texts = plist["TEXT"] as? [[String: Any]] else {
            return nil
        }
        
        let english = texts.first { $0["Name"] as? String == "English" } ?? texts.first
        return (english?["Data"] as? Data).flatMap { String(data: $0, encoding: .macOSRoman) }
    }
    
    /// Mounts the disk image (agreeing to its license), imports every bezel image, and detaches it. The disk image is
    /// deleted afterward, and its version recorded so updates can be noticed.
    public func install(_ downloaded: DownloadedBezels, now: Date) async throws -> [BezelInfo] {
        let mountPoint = try await mount(downloaded.file)
        var imported: [BezelInfo] = []
        
        do {
            let list = try await processes.run(Command("/usr/bin/find", [mountPoint, "-type", "f", "-iname", "*.png"]))
            let source = BezelSourceInfo(url: downloaded.product.url, product: downloaded.product.name, version: downloaded.version)
            
            for path in Self.bezelImagePaths(in: list.stdout, mountPoint: mountPoint) {
                if let info = importImage(at: URL(filePath: path), product: downloaded.product, source: source, now: now) {
                    imported.append(info)
                }
            }
        } catch {
            _ = try? await detach(mountPoint)
            throw error
        }
        
        _ = try? await detach(mountPoint)
        try? fileManager.removeItem(at: downloaded.file)
        
        guard !imported.isEmpty else {
            throw BezelDownloadError.noBezels(downloaded.product.name)
        }
        
        if let version = downloaded.version {
            try? library.recordInstalled(downloaded.product.url, version: version)
        }
        
        return imported
    }
    
    /// Deletes a download whose license wasn't agreed to.
    public func discard(_ downloaded: DownloadedBezels) {
        try? fileManager.removeItem(at: downloaded.file)
    }
    
    // MARK: - Helpers
    
    private func mount(_ file: URL) async throws -> String {
        // NOTE: - `yes` answers the license prompt, which the user has already agreed to in Stagehand. The path is
        // passed as an argument, so it's never parsed by the shell.
        let output = try await processes.run(Command("/bin/sh", [
            "-c",
            "yes | /usr/bin/hdiutil attach -readonly -nobrowse -noautoopen -plist \"$1\"",
            "sh",
            file.path(percentEncoded: false),
        ]))
        
        guard output.succeeded,
              let start = output.stdout.range(of: "<?xml"),
              let plist = try? PropertyListSerialization.propertyList(from: Data(output.stdout[start.lowerBound...].utf8), format: nil) as? [String: Any],
              let entities = plist["system-entities"] as? [[String: Any]],
              let mountPoint = entities.compactMap({ $0["mount-point"] as? String }).first else {
            throw BezelDownloadError.mountFailed(output.stderr.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        
        return mountPoint
    }
    
    private func detach(_ mountPoint: String) async throws -> ProcessOutput {
        try await processes.run(Command("/usr/bin/hdiutil", ["detach", mountPoint, "-quiet"]))
    }
    
    /// Imports one image, or skips it (logging why): landscape images for upright devices, and images without a
    /// screen to find.
    private func importImage(at url: URL, product: AppleBezelProduct, source: BezelSourceInfo, now: Date) -> BezelInfo? {
        let name = url.deletingPathExtension().lastPathComponent
        
        guard let data = try? fileManager.read(url), let image = CGImage.decode(data) else {
            Logger.bezels.info("Skipping \(name, privacy: .public): unreadable")
            return nil
        }
        
        guard let deviceClass = Self.deviceClass(forImageNamed: name, width: image.width, height: image.height, product: product) else {
            Logger.bezels.info("Skipping \(name, privacy: .public): not for a class Stagehand uses")
            return nil
        }
        
        let (model, color) = Self.modelAndColor(fromImageNamed: name, product: product)
        
        do {
            return try library.importBezel(data: data, name: name, deviceClass: deviceClass, model: model, color: color, importedAt: now, source: source)
        } catch {
            Logger.bezels.info("Skipping \(name, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }
    
    /// The images `find` listed, sorted, without any inside a hidden folder: Apple's disk images carry their Finder
    /// window's background in `.DropDMGBackground/`, which isn't a bezel.
    static func bezelImagePaths(in listing: String, mountPoint: String) -> [String] {
        listing.split(separator: "\n").map(String.init).filter { path in
            let relative = path.hasPrefix(mountPoint) ? String(path.dropFirst(mountPoint.count)) : path
            return !path.isEmpty && !relative.split(separator: "/").contains { $0.hasPrefix(".") }
        }
        .sorted()
    }
    
    /// The class an image is for. Upright devices skip landscape images. The iPhone Duo's images say which display
    /// they're for in their names (closed or cover for the outer display, open for the inner one); without that,
    /// the class whose screen's shape is closest wins.
    static func deviceClass(forImageNamed name: String, width: Int, height: Int, product: AppleBezelProduct) -> DeviceClass? {
        let classes = product.deviceClasses
        let isLandscape = width > height
        let name = name.lowercased()
        
        guard let first = classes.first, isLandscape == (first == .mac) else {
            return nil
        }
        
        if classes.count == 1 {
            return first
        }
        
        if ["closed", "folded", "cover", "outer"].contains(where: name.contains) {
            return classes.first { $0 == .duoOuter } ?? first
        }
        
        if ["open", "unfolded", "inner"].contains(where: name.contains) {
            return classes.first { $0 == .duoInner } ?? first
        }
        
        let aspect = Double(width) / Double(height)
        return classes.min { lhs, rhs in
            abs((DeviceTable.standard.targets(in: lhs).first?.aspectRatio ?? 0) - aspect) < abs((DeviceTable.standard.targets(in: rhs).first?.aspectRatio ?? 0) - aspect)
        }
    }
    
    /// "iPhone 18 Pro Max - Cosmic Orange - Portrait" to ("iPhone 18 Pro Max", "Cosmic Orange"). A name without
    /// parts is the model, unless it doesn't name the product, when the product is.
    static func modelAndColor(fromImageNamed name: String, product: AppleBezelProduct) -> (model: String, color: String) {
        let parts = name.components(separatedBy: " - ").map { $0.trimmingCharacters(in: .whitespaces) }
        let model = parts.first ?? name
        let color = parts.count > 1 ? parts[1] : ""
        return (model.isEmpty ? product.name : model, color)
    }
}
