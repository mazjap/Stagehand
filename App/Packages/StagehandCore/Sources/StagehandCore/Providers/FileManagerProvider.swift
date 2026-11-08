import Dependencies
import Foundation

/// The file system operations Stagehand uses, so tests can use a fake.
///
/// > Warning: Use `url.path(percentEncoded: false)` with `FileManager`, never `url.path()`, which percent-encodes
/// > spaces so files never seem to exist.
public protocol FileManagerProvider: Sendable {
    func fileExists(at url: URL) -> Bool
    func isDirectory(at url: URL) -> Bool
    func contentsOfDirectory(at url: URL) throws -> [URL]
    func createDirectory(at url: URL) throws
    func read(_ url: URL) throws -> Data
    func write(_ data: Data, to url: URL) throws
    func copyItem(at source: URL, to destination: URL) throws
    func removeItem(at url: URL) throws
}

public struct LiveFileManager: FileManagerProvider {
    public init() {}
    
    private var manager: FileManager {
        .default
    }
    
    public func fileExists(at url: URL) -> Bool {
        manager.fileExists(atPath: url.path(percentEncoded: false))
    }
    
    public func isDirectory(at url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        return manager.fileExists(atPath: url.path(percentEncoded: false), isDirectory: &isDirectory) && isDirectory.boolValue
    }
    
    public func contentsOfDirectory(at url: URL) throws -> [URL] {
        try manager.contentsOfDirectory(at: url, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
    }
    
    public func createDirectory(at url: URL) throws {
        try manager.createDirectory(at: url, withIntermediateDirectories: true)
    }
    
    public func read(_ url: URL) throws -> Data {
        try Data(contentsOf: url)
    }
    
    public func write(_ data: Data, to url: URL) throws {
        try manager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
    }
    
    public func copyItem(at source: URL, to destination: URL) throws {
        if fileExists(at: destination) {
            try manager.removeItem(at: destination)
        }
        
        try manager.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try manager.copyItem(at: source, to: destination)
    }
    
    public func removeItem(at url: URL) throws {
        try manager.removeItem(at: url)
    }
}

/// An in-memory file system for tests.
public final class InMemoryFileManager: FileManagerProvider, @unchecked Sendable {
    private let lock = NSLock()
    private var files: [String: Data] = [:]
    private var directories: Set<String> = ["/"]
    
    public init(files: [URL: Data] = [:]) {
        for (url, data) in files {
            try? write(data, to: url)
        }
    }
    
    private func key(_ url: URL) -> String {
        url.standardizedFileURL.path(percentEncoded: false).trimmingSuffix("/")
    }
    
    public func fileExists(at url: URL) -> Bool {
        lock.withLock { files[key(url)] != nil || directories.contains(key(url)) }
    }
    
    public func isDirectory(at url: URL) -> Bool {
        lock.withLock { directories.contains(key(url)) }
    }
    
    public func contentsOfDirectory(at url: URL) throws -> [URL] {
        let prefix = key(url) + "/"
        
        return lock.withLock {
            let all = Array(files.keys) + Array(directories)
            let children = Set(all.filter { $0.hasPrefix(prefix) }.compactMap { $0.dropFirst(prefix.count).split(separator: "/").first.map(String.init) })
            return children.sorted().map { url.appending(path: $0) }
        }
    }
    
    public func createDirectory(at url: URL) throws {
        lock.withLock {
            var path = key(url)
            
            while !path.isEmpty && path != "/" {
                directories.insert(path)
                path = (path as NSString).deletingLastPathComponent
            }
        }
    }
    
    public func read(_ url: URL) throws -> Data {
        guard let data = lock.withLock({ files[key(url)] }) else {
            throw CocoaError(.fileReadNoSuchFile)
        }
        
        return data
    }
    
    public func write(_ data: Data, to url: URL) throws {
        try createDirectory(at: url.deletingLastPathComponent())
        lock.withLock { files[key(url)] = data }
    }
    
    public func copyItem(at source: URL, to destination: URL) throws {
        try write(try read(source), to: destination)
    }
    
    public func removeItem(at url: URL) throws {
        let path = key(url)
        
        lock.withLock {
            files = files.filter { $0.key != path && !$0.key.hasPrefix(path + "/") }
            directories = directories.filter { $0 != path && !$0.hasPrefix(path + "/") }
        }
    }
}

extension String {
    func trimmingSuffix(_ suffix: String) -> String {
        hasSuffix(suffix) && count > suffix.count ? String(dropLast(suffix.count)) : self
    }
}

enum FileManagerProviderKey: DependencyKey {
    static let liveValue: any FileManagerProvider = LiveFileManager()
    static var testValue: any FileManagerProvider { InMemoryFileManager() }
}

extension DependencyValues {
    public var fileManager: any FileManagerProvider {
        get { self[FileManagerProviderKey.self] }
        set { self[FileManagerProviderKey.self] = newValue }
    }
}
