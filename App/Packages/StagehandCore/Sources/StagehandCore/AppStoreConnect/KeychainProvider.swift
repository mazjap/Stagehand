import Dependencies
import Foundation
import Security

public enum KeychainError: Error, Equatable, LocalizedError {
    case status(OSStatus)
    
    public var errorDescription: String? {
        switch self {
        case let .status(status): "The Keychain returned an error (\(status))."
        }
    }
}

/// Stores secrets, like the App Store Connect API key, in the Keychain.
public protocol KeychainProvider: Sendable {
    func read(account: String) throws(KeychainError) -> Data?
    func write(_ data: Data, account: String) throws(KeychainError)
    func delete(account: String) throws(KeychainError)
}

public struct LiveKeychain: KeychainProvider {
    public static let service = "com.mazjap.Stagehand"
    
    public init() {}
    
    private func query(_ account: String) -> [CFString: Any] {
        [kSecClass: kSecClassGenericPassword, kSecAttrService: Self.service, kSecAttrAccount: account]
    }
    
    public func read(account: String) throws(KeychainError) -> Data? {
        var query = query(account)
        query[kSecReturnData] = true
        query[kSecMatchLimit] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        if status == errSecItemNotFound {
            return nil
        }
        
        guard status == errSecSuccess else {
            throw .status(status)
        }
        
        return result as? Data
    }
    
    public func write(_ data: Data, account: String) throws(KeychainError) {
        let status = SecItemUpdate(query(account) as CFDictionary, [kSecValueData: data] as CFDictionary)
        
        if status == errSecItemNotFound {
            var item = query(account)
            item[kSecValueData] = data
            item[kSecAttrAccessible] = kSecAttrAccessibleAfterFirstUnlock
            let added = SecItemAdd(item as CFDictionary, nil)
            
            guard added == errSecSuccess else {
                throw .status(added)
            }
        } else if status != errSecSuccess {
            throw .status(status)
        }
    }
    
    public func delete(account: String) throws(KeychainError) {
        let status = SecItemDelete(query(account) as CFDictionary)
        
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw .status(status)
        }
    }
}

public final class InMemoryKeychain: KeychainProvider, @unchecked Sendable {
    private let lock = NSLock()
    private var items: [String: Data] = [:]
    
    public init() {}
    
    public func read(account: String) throws(KeychainError) -> Data? {
        lock.withLock { items[account] }
    }
    
    public func write(_ data: Data, account: String) throws(KeychainError) {
        lock.withLock { items[account] = data }
    }
    
    public func delete(account: String) throws(KeychainError) {
        _ = lock.withLock { items.removeValue(forKey: account) }
    }
}

enum KeychainProviderKey: DependencyKey {
    static let liveValue: any KeychainProvider = LiveKeychain()
    static var testValue: any KeychainProvider { InMemoryKeychain() }
}

extension DependencyValues {
    public var keychain: any KeychainProvider {
        get { self[KeychainProviderKey.self] }
        set { self[KeychainProviderKey.self] = newValue }
    }
}
