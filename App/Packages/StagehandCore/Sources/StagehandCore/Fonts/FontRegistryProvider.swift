import CoreText
import CryptoKit
import Dependencies
import Foundation
import OSLog

public enum FontError: Error, Equatable, LocalizedError {
    case unreadable(String)
    case registrationFailed(String, reason: String)
    
    public var errorDescription: String? {
        switch self {
        case let .unreadable(name): "\(name) isn't a font file Stagehand can read."
        case let .registrationFailed(name, reason): "\(name) couldn't be registered: \(reason)"
        }
    }
}

/// Registers a document's embedded fonts, so text renders in them and never silently falls back to the system font.
public protocol FontRegistryProvider: Sendable {
    /// Registers fonts for this process, returning their PostScript names. Fonts already registered are skipped.
    func register(_ fonts: [String: Data]) async throws(FontError) -> [String]
    
    /// The PostScript name of a font file.
    func postScriptName(of data: Data, fileName: String) throws(FontError) -> String
    
    /// Every font installed on the system, by family.
    func availableFamilies() -> [FontFamily]
    
    /// An installed font's file, to embed it in a document.
    func fontFile(postScriptName: String) -> URL?
}

/// An installed font family and its faces.
public struct FontFamily: Hashable, Sendable, Identifiable {
    public struct Face: Hashable, Sendable, Identifiable {
        public var postScriptName: String
        public var styleName: String
        
        public var id: String {
            postScriptName
        }
    }
    
    public var name: String
    public var faces: [Face]
    
    public var id: String {
        name
    }
}

public struct LiveFontRegistry: FontRegistryProvider {
    public init() {}
    
    /// Where fonts are written before they're registered, since Core Text registers fonts by URL.
    static var cacheFolder: URL {
        URL.cachesDirectory.appending(path: "com.mazjap.Stagehand/Fonts", directoryHint: .isDirectory)
    }
    
    public func register(_ fonts: [String: Data]) async throws(FontError) -> [String] {
        var names: [String] = []
        
        for (fileName, data) in fonts.sorted(by: { $0.key < $1.key }) {
            let fileNames = try descriptorNames(data, fileName: fileName)
            names += fileNames
            
            // A font embedded from the system is already installed, and registering it again fails as a duplicate.
            if fileNames.allSatisfy(Self.isInstalled) {
                continue
            }
            
            // Each file is cached under a hash of its contents, so two documents' fonts with one name don't collide.
            let digest = SHA256.hash(data: data).prefix(8).map { String(format: "%02x", $0) }.joined()
            let folder = Self.cacheFolder.appending(path: digest, directoryHint: .isDirectory)
            let url = folder.appending(path: fileName)
            
            do {
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                
                if !FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) {
                    try data.write(to: url, options: .atomic)
                }
            } catch {
                throw .registrationFailed(fileName, reason: error.localizedDescription)
            }
            
            var error: Unmanaged<CFError>?
            
            if !CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error), let error = error?.takeRetainedValue() {
                // An already registered font is fine: the document was opened before, or another uses it too.
                let code = CFErrorGetCode(error)
                
                if code != CTFontManagerError.alreadyRegistered.rawValue && code != CTFontManagerError.duplicatedName.rawValue {
                    throw .registrationFailed(fileName, reason: CFErrorCopyDescription(error) as String)
                }
            }
        }
        
        Logger.fonts.info("Registered \(names.count) fonts")
        return names
    }
    
    public func postScriptName(of data: Data, fileName: String) throws(FontError) -> String {
        guard let name = try descriptorNames(data, fileName: fileName).first else {
            throw .unreadable(fileName)
        }
        
        return name
    }
    
    public func availableFamilies() -> [FontFamily] {
        Self.families
    }
    
    public func fontFile(postScriptName: String) -> URL? {
        let descriptor = CTFontDescriptorCreateWithNameAndSize(postScriptName as CFString, 12)
        return CTFontDescriptorCopyAttribute(descriptor, kCTFontURLAttribute) as? URL
    }
    
    /// Every installed family, read once. Hidden system faces (names starting with a dot) are left out.
    private static let families: [FontFamily] = {
        let collection = CTFontCollectionCreateFromAvailableFonts(nil)
        let descriptors = CTFontCollectionCreateMatchingFontDescriptors(collection) as? [CTFontDescriptor] ?? []
        var byFamily: [String: [FontFamily.Face]] = [:]
        
        for descriptor in descriptors {
            guard let name = CTFontDescriptorCopyAttribute(descriptor, kCTFontNameAttribute) as? String, !name.hasPrefix("."),
                  let family = CTFontDescriptorCopyAttribute(descriptor, kCTFontFamilyNameAttribute) as? String, !family.hasPrefix(".") else {
                continue
            }
            
            let style = CTFontDescriptorCopyAttribute(descriptor, kCTFontStyleNameAttribute) as? String ?? name
            byFamily[family, default: []].append(FontFamily.Face(postScriptName: name, styleName: style))
        }
        
        return byFamily
            .map { FontFamily(name: $0.key, faces: Array(Set($0.value)).sorted { $0.styleName < $1.styleName }) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }()
    
    static func isInstalled(_ postScriptName: String) -> Bool {
        let font = CTFontCreateWithName(postScriptName as CFString, 12, nil)
        return CTFontCopyPostScriptName(font) as String == postScriptName && CTFontDescriptorCopyAttribute(CTFontCopyFontDescriptor(font), kCTFontURLAttribute) != nil
    }
    
    private func descriptorNames(_ data: Data, fileName: String) throws(FontError) -> [String] {
        guard let descriptors = CTFontManagerCreateFontDescriptorsFromData(data as CFData) as? [CTFontDescriptor], !descriptors.isEmpty else {
            throw .unreadable(fileName)
        }
        
        return descriptors.compactMap { CTFontDescriptorCopyAttribute($0, kCTFontNameAttribute) as? String }
    }
}

enum FontRegistryProviderKey: DependencyKey {
    static let liveValue: any FontRegistryProvider = LiveFontRegistry()
    static var testValue: any FontRegistryProvider { LiveFontRegistry() }
}

extension DependencyValues {
    public var fontRegistry: any FontRegistryProvider {
        get { self[FontRegistryProviderKey.self] }
        set { self[FontRegistryProviderKey.self] = newValue }
    }
}
