import Dependencies
import Foundation

/// Finds Stagehand's library folder: its iCloud container's `Documents`, or a local folder when iCloud isn't available.
public protocol UbiquityProvider: Sendable {
    /// The library's root folder, which holds `Styles/` and `Bezels/`.
    func libraryURL() async -> URL
    
    /// Whether the library is in iCloud Drive.
    func isUsingICloud() async -> Bool
}

public struct LiveUbiquity: UbiquityProvider {
    public static let containerIdentifier = "iCloud.com.mazjap.Stagehand"
    
    public init() {}
    
    public func libraryURL() async -> URL {
        await iCloudDocuments() ?? Self.localLibrary
    }
    
    public func isUsingICloud() async -> Bool {
        await iCloudDocuments() != nil
    }
    
    /// Application Support/Stagehand/Library, for when iCloud isn't available.
    public static var localLibrary: URL {
        URL.applicationSupportDirectory.appending(path: "Stagehand/Library", directoryHint: .isDirectory)
    }
    
    @concurrent
    private func iCloudDocuments() async -> URL? {
        // NOTE: - `url(forUbiquityContainerIdentifier:)` can block, so it's never called on the main actor.
        FileManager.default.url(forUbiquityContainerIdentifier: Self.containerIdentifier)?
            .appending(path: "Documents", directoryHint: .isDirectory)
    }
}

/// A library in a fixed folder, for tests.
public struct FixedUbiquity: UbiquityProvider {
    public var url: URL
    
    public init(url: URL) {
        self.url = url
    }
    
    public func libraryURL() async -> URL {
        url
    }
    
    public func isUsingICloud() async -> Bool {
        false
    }
}

enum UbiquityProviderKey: DependencyKey {
    static let liveValue: any UbiquityProvider = LiveUbiquity()
    static var testValue: any UbiquityProvider { FixedUbiquity(url: URL(filePath: "/StagehandTestLibrary", directoryHint: .isDirectory)) }
}

extension DependencyValues {
    public var ubiquity: any UbiquityProvider {
        get { self[UbiquityProviderKey.self] }
        set { self[UbiquityProviderKey.self] = newValue }
    }
}
