import Dependencies
import Foundation
import Observation
import StagehandModel

extension Notification.Name {
    /// Posted when the library's bezels change, so open projects reload them.
    public static let stagehandBezelsChanged = Notification.Name("com.mazjap.Stagehand.bezelsChanged")
}

/// The library window's coordinator: template sets in `Styles/`, and bezels in `Bezels/`, downloaded from Apple Design
/// Resources.
@Observable
@MainActor
public final class LibraryCoordinator {
    public enum Intent {
        case load
        case importBezel(DroppedFile, deviceClass: DeviceClass, model: String, color: String)
        case setDefault(BezelID?, DeviceClass)
        case remove(BezelID)
        case dismissAlert
        
        /// Reads Apple Design Resources' list of bezels, and each one's current version.
        case loadAppleBezels
        
        /// Downloads a product's disk image, then waits for its license to be agreed to (``pendingLicense``).
        case download(AppleBezelProduct)
        
        /// The user's Agree to the pending license: opens the disk image and imports its bezels.
        case agreeToLicense
        case declineLicense
    }
    
    public private(set) var libraryURL: URL?
    public private(set) var isUsingICloud = false
    public private(set) var bezels: BezelCatalog = .empty
    public private(set) var styles: [LibraryStyle] = []
    public var alert: CoordinatorAlert?
    
    /// Apple Design Resources' products, in the page's order.
    public private(set) var appleProducts: [AppleBezelProduct] = []
    public private(set) var isLoadingAppleBezels = false
    
    /// Each product's version on Apple's server, and the version last installed.
    public private(set) var latestVersions: [URL: String] = [:]
    public private(set) var installedVersions: [URL: String] = [:]
    
    /// Downloads in progress, from 0 to 1, and installs (shown as indeterminate).
    public private(set) var progress: [URL: Double] = [:]
    public private(set) var installing: Set<URL> = []
    
    /// A downloaded disk image whose license is waiting for Agree or Decline.
    public private(set) var pendingLicense: DownloadedBezels?
    
    @ObservationIgnored @Dependency(\.ubiquity) private var ubiquity
    @ObservationIgnored @Dependency(\.fileManager) private var fileManager
    @ObservationIgnored @Dependency(\.bezelDownloads) private var downloads
    @ObservationIgnored @Dependency(\.processRunner) private var processes
    @ObservationIgnored @Dependency(\.clock) private var clock
    @ObservationIgnored private var library: BezelLibrary?
    
    /// Where disk images wait while their licenses are read.
    public var workFolder = URL.cachesDirectory.appending(path: "Stagehand/Bezel Downloads", directoryHint: .isDirectory)
    
    public init() {}
    
    public func handle(_ intent: Intent) {
        switch intent {
        case .load:
            let ubiquity = ubiquity
            
            Task { [weak self] in
                let url = await ubiquity.libraryURL()
                let iCloud = await ubiquity.isUsingICloud()
                self?.finishLoading(url: url, iCloud: iCloud)
            }
        case let .importBezel(file, deviceClass, model, color):
            guard let library else { return }
            
            do {
                let name = (file.name as NSString).deletingPathExtension
                _ = try library.importBezel(data: file.data, name: name, deviceClass: deviceClass, model: model, color: color)
                changed()
            } catch {
                alert = CoordinatorAlert(title: "Couldn't Import Bezel", error: error)
            }
        case let .setDefault(id, deviceClass):
            do {
                try library?.setDefault(id, for: deviceClass)
                changed()
            } catch {
                alert = CoordinatorAlert(title: "Couldn't Change the Default", error: error)
            }
        case let .remove(id):
            do {
                try library?.remove(id)
                changed()
            } catch {
                alert = CoordinatorAlert(title: "Couldn't Remove Bezel", error: error)
            }
        case .dismissAlert:
            alert = nil
        case .loadAppleBezels:
            let downloads = downloads
            isLoadingAppleBezels = true
            
            Task { [weak self] in
                await self?.loadAppleBezels(downloads)
            }
        case let .download(product):
            let downloader = downloader
            progress[product.url] = 0
            
            Task { [weak self] in
                await self?.download(product, with: downloader)
            }
        case .agreeToLicense:
            guard let pending = pendingLicense else { return }
            pendingLicense = nil
            let downloader = downloader
            let now = clock.now
            installing.insert(pending.product.url)
            
            Task { [weak self] in
                await self?.install(pending, with: downloader, now: now)
            }
        case .declineLicense:
            if let pending = pendingLicense {
                downloader?.discard(pending)
                progress[pending.product.url] = nil
            }
            
            pendingLicense = nil
        }
    }
    
    // MARK: - Computed Properties
    
    /// A product whose installed version differs from Apple's current one.
    public func hasUpdate(_ product: AppleBezelProduct) -> Bool {
        guard let installed = installedVersions[product.url], let latest = latestVersions[product.url] else {
            return false
        }
        
        return installed != latest
    }
    
    public func isInstalled(_ product: AppleBezelProduct) -> Bool {
        installedVersions[product.url] != nil
    }
    
    private var downloader: BezelDownloader? {
        library.map { BezelDownloader(library: $0, downloads: downloads, processes: processes, fileManager: fileManager, workFolder: workFolder) }
    }
    
    // MARK: - Downloads
    
    private func loadAppleBezels(_ downloads: any BezelDownloadProvider) async {
        defer { isLoadingAppleBezels = false }
        
        do {
            appleProducts = BezelSource.products(fromPage: try await downloads.page())
            
            for product in appleProducts where installedVersions[product.url] != nil {
                latestVersions[product.url] = try? await downloads.version(of: product.url)
            }
        } catch {
            alert = CoordinatorAlert(title: "Couldn't Reach Apple Design Resources", error: error)
        }
    }
    
    private func download(_ product: AppleBezelProduct, with downloader: BezelDownloader?) async {
        guard let downloader else {
            progress[product.url] = nil
            return
        }
        
        do {
            let downloaded = try await downloader.download(product) { [weak self] fraction in
                Task { @MainActor in
                    if self?.progress[product.url] != nil {
                        self?.progress[product.url] = fraction
                    }
                }
            }
            
            progress[product.url] = 1
            
            if downloaded.license == nil {
                await install(downloaded, with: downloader, now: clock.now)
            } else {
                pendingLicense = downloaded
            }
        } catch {
            progress[product.url] = nil
            alert = CoordinatorAlert(title: "Couldn't Download \(product.name)", error: error)
        }
    }
    
    private func install(_ downloaded: DownloadedBezels, with downloader: BezelDownloader?, now: Date) async {
        defer {
            installing.remove(downloaded.product.url)
            progress[downloaded.product.url] = nil
        }
        
        do {
            _ = try await downloader?.install(downloaded, now: now)
            
            if let version = downloaded.version {
                latestVersions[downloaded.product.url] = version
            }
            
            changed()
        } catch {
            alert = CoordinatorAlert(title: "Couldn't Install \(downloaded.product.name)", error: error)
        }
    }
    
    private func finishLoading(url: URL, iCloud: Bool) {
        libraryURL = url
        isUsingICloud = iCloud
        library = BezelLibrary(libraryURL: url, fileManager: fileManager)
        bezels = library?.load() ?? .empty
        installedVersions = library?.installedVersions() ?? [:]
        styles = StyleLibrary(libraryURL: url, fileManager: fileManager).list()
    }
    
    /// A new project's contents with every template's Library Default bezels pinned (and embedded), so the templates
    /// keep the bezels they were made with.
    public func pinningBezels(_ contents: ProjectContents) -> ProjectContents {
        var contents = contents
        let library = library
        BezelPinning.pinLibraryDefaults(in: &contents, catalog: bezels) { try? library?.imageData(for: $0) }
        return contents
    }
    
    /// A new project from a library style, copying the style and its fonts in with a `BaseStyle` snapshot.
    public func newProject(from style: LibraryStyle, devices: [DeviceClass] = [.phone]) throws -> ProjectContents {
        guard let libraryURL else {
            throw StyleLibraryError.notFound(style.name)
        }
        
        let contents = try StyleLibrary(libraryURL: libraryURL, fileManager: fileManager).load(style)
        var project = Self.newProject(from: contents.project.style, fonts: contents.fonts, devices: devices)
        project.bezels = contents.bezels
        return project
    }
    
    /// A new project with a library style and its fonts, on some devices.
    public static func newProject(from style: Style, fonts: [String: Data], devices: [DeviceClass] = [.phone]) -> ProjectContents {
        var project = Project.empty(devices: devices, style: style)
        project.basedOn = BaseStyle(styleID: style.id, version: style.version, snapshot: style)
        return ProjectContents(project: project, fonts: fonts)
    }
    
    private func changed() {
        bezels = library?.load() ?? .empty
        installedVersions = library?.installedVersions() ?? [:]
        NotificationCenter.default.post(name: .stagehandBezelsChanged, object: nil)
    }
}
