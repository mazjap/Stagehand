import Dependencies
import Foundation
import StagehandModel

/// One product's bezels on Apple Design Resources: a disk image of PNGs.
public struct AppleBezelProduct: Hashable, Sendable, Identifiable {
    /// The product, from the file's name, like "iPhone 18" or "iPad Pro (M5)".
    public var name: String
    public var url: URL
    
    /// The classes its bezels can be for. Empty for products Stagehand doesn't make screenshots for (Other).
    public var deviceClasses: [DeviceClass]
    
    public var id: URL {
        url
    }
}

/// Reads Apple Design Resources' list of product bezels.
///
/// Apple's bezels are never bundled or committed: they're downloaded into the library from these links.
public enum BezelSource {
    public static let pageURL = URL(string: "https://developer.apple.com/design/resources/")!
    
    // MARK: - Functions
    
    /// Every `Bezel-*.dmg` link on the page, once each, in the page's order.
    public static func products(fromPage html: String) -> [AppleBezelProduct] {
        var seen = Set<URL>()
        var products: [AppleBezelProduct] = []
        
        for match in html.matches(of: #/href="([^"]*/Bezel-[^"/]+\.dmg)"/#) {
            let href = String(match.output.1).replacingOccurrences(of: "&amp;", with: "&")
            
            guard let url = URL(string: href, relativeTo: pageURL)?.absoluteURL, seen.insert(url).inserted else {
                continue
            }
            
            let name = productName(fromFileName: url.deletingPathExtension().lastPathComponent)
            products.append(AppleBezelProduct(name: name, url: url, deviceClasses: deviceClasses(forProduct: name)))
        }
        
        return products
    }
    
    /// `Bezel-iPad-Pro-(M5)` to "iPad Pro (M5)", and `Bezel-Apple-Watch-Series-11-2025` to "Apple Watch Series 11".
    static func productName(fromFileName fileName: String) -> String {
        var words = (fileName.removingPercentEncoding ?? fileName)
            .replacing(#/^Bezel-/#, with: "")
            .split(separator: "-")
            .map(String.init)
        
        // A trailing year is the release, not the product.
        if let last = words.last, last.count == 4, let year = Int(last), year > 2000, words.count > 1 {
            words.removeLast()
        }
        
        return words.joined(separator: " ")
    }
    
    /// The classes a product's bezels can be for.
    public static func deviceClasses(forProduct name: String) -> [DeviceClass] {
        let name = name.lowercased()
        
        if name.contains("keynote") || name.contains("apple tv") {
            return []
        }
        
        if name.contains("iphone duo") {
            return [.duoOuter, .duoInner]
        }
        
        if name.hasPrefix("iphone") {
            return [.phone]
        }
        
        if name.hasPrefix("ipad") {
            return [.pad]
        }
        
        if name.contains("watch") {
            return [.watch]
        }
        
        if name.contains("macbook") || name.contains("imac") || name.contains("studio display") {
            return [.mac]
        }
        
        return []
    }
}

// MARK: - Provider

/// Fetches Apple Design Resources' page and its disk images, so tests can use a fake.
public protocol BezelDownloadProvider: Sendable {
    /// The Design Resources page's HTML.
    func page() async throws -> String
    
    /// A file's version without downloading it: its `ETag`, or else its `Last-Modified`.
    func version(of url: URL) async throws -> String?
    
    /// Downloads a file into `destination`, reporting progress from 0 to 1, and returns its version.
    func download(_ url: URL, to destination: URL, progress: @escaping @Sendable (Double) -> Void) async throws -> String?
}

public struct LiveBezelDownloads: BezelDownloadProvider {
    public init() {}
    
    public func page() async throws -> String {
        let (data, _) = try await URLSession.shared.data(from: BezelSource.pageURL)
        return String(decoding: data, as: UTF8.self)
    }
    
    public func version(of url: URL) async throws -> String? {
        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"
        let (_, response) = try await URLSession.shared.data(for: request)
        return Self.version(of: response)
    }
    
    public func download(_ url: URL, to destination: URL, progress: @escaping @Sendable (Double) -> Void) async throws -> String? {
        let delegate = ProgressDelegate(progress: progress)
        let (file, response) = try await URLSession.shared.download(from: url, delegate: delegate)
        
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw BezelDownloadError.httpStatus(http.statusCode)
        }
        
        try? FileManager.default.removeItem(at: destination)
        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.moveItem(at: file, to: destination)
        return Self.version(of: response)
    }
    
    static func version(of response: URLResponse) -> String? {
        guard let http = response as? HTTPURLResponse else {
            return nil
        }
        
        return http.value(forHTTPHeaderField: "ETag") ?? http.value(forHTTPHeaderField: "Last-Modified")
    }
    
    private final class ProgressDelegate: NSObject, URLSessionDownloadDelegate, Sendable {
        let progress: @Sendable (Double) -> Void
        
        init(progress: @escaping @Sendable (Double) -> Void) {
            self.progress = progress
        }
        
        func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
            if totalBytesExpectedToWrite > 0 {
                progress(Double(totalBytesWritten) / Double(totalBytesExpectedToWrite))
            }
        }
        
        func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {}
    }
}

/// Answers from fixed values, recording the URLs it's asked for.
public final class FakeBezelDownloads: BezelDownloadProvider, @unchecked Sendable {
    public var html: String
    public var versions: [URL: String]
    
    /// What a download writes, by URL.
    public var files: [URL: Data]
    
    private let lock = NSLock()
    private var recorded: [URL] = []
    
    public init(html: String = "", versions: [URL: String] = [:], files: [URL: Data] = [:]) {
        self.html = html
        self.versions = versions
        self.files = files
    }
    
    public var downloaded: [URL] {
        lock.withLock { recorded }
    }
    
    public func page() async throws -> String {
        html
    }
    
    public func version(of url: URL) async throws -> String? {
        versions[url]
    }
    
    public func download(_ url: URL, to destination: URL, progress: @escaping @Sendable (Double) -> Void) async throws -> String? {
        lock.withLock { recorded.append(url) }
        progress(1)
        return versions[url]
    }
}

public enum BezelDownloadError: Error, LocalizedError, Equatable {
    case httpStatus(Int)
    case mountFailed(String)
    case noBezels(String)
    
    public var errorDescription: String? {
        switch self {
        case let .httpStatus(status): "Apple Design Resources answered with HTTP \(status)."
        case let .mountFailed(reason): "The disk image couldn't be opened: \(reason)"
        case let .noBezels(product): "\(product)'s disk image had no bezel images Stagehand could use."
        }
    }
}

enum BezelDownloadProviderKey: DependencyKey {
    static let liveValue: any BezelDownloadProvider = LiveBezelDownloads()
    static var testValue: any BezelDownloadProvider { FakeBezelDownloads() }
}

extension DependencyValues {
    public var bezelDownloads: any BezelDownloadProvider {
        get { self[BezelDownloadProviderKey.self] }
        set { self[BezelDownloadProviderKey.self] = newValue }
    }
}
