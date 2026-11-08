import Dependencies
import Foundation
import Observation

/// Settings' App Store Connect section: the API key, kept in the Keychain.
@Observable
@MainActor
public final class AppStoreConnectSettingsCoordinator {
    public enum Intent {
        case load
        case importKey(DroppedFile)
        case save
        case remove
    }
    
    public var issuerID = ""
    public var keyID = ""
    public private(set) var hasKey = false
    public private(set) var message: String?
    
    @ObservationIgnored private var privateKey: String?
    @ObservationIgnored @Dependency(\.keychain) private var keychain
    
    public init() {}
    
    public func handle(_ intent: Intent) {
        switch intent {
        case .load:
            if let data = try? keychain.read(account: AppStoreConnectCredentials.keychainAccount),
               let credentials = try? JSONDecoder().decode(AppStoreConnectCredentials.self, from: data) {
                issuerID = credentials.issuerID
                keyID = credentials.keyID
                privateKey = credentials.privateKey
                hasKey = true
            }
        case let .importKey(file):
            privateKey = String(decoding: file.data, as: UTF8.self)
            
            // The key ID is in Apple's file name: AuthKey_<key ID>.p8.
            if keyID.isEmpty, file.name.hasPrefix("AuthKey_") {
                keyID = String((file.name as NSString).deletingPathExtension.dropFirst("AuthKey_".count))
            }
            
            message = "Key loaded. Save to keep it in the Keychain."
        case .save:
            guard let privateKey, !issuerID.isEmpty, !keyID.isEmpty else {
                message = "Fill in the issuer ID and key ID, and choose the .p8 key."
                return
            }
            
            let credentials = AppStoreConnectCredentials(issuerID: issuerID, keyID: keyID, privateKey: privateKey)
            
            do {
                _ = try AppStoreConnectToken.make(credentials, now: Date())
                try keychain.write(JSONEncoder().encode(credentials), account: AppStoreConnectCredentials.keychainAccount)
                hasKey = true
                message = "Saved in the Keychain."
            } catch {
                message = (error as? LocalizedError)?.errorDescription ?? String(describing: error)
            }
        case .remove:
            try? keychain.delete(account: AppStoreConnectCredentials.keychainAccount)
            privateKey = nil
            hasKey = false
            message = "Removed from the Keychain."
        }
    }
}
