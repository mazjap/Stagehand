import CryptoKit
import Foundation

/// The API key App Store Connect issued: the `.p8` private key, its key ID and the issuer ID.
public struct AppStoreConnectCredentials: Codable, Hashable, Sendable {
    public static let keychainAccount = "AppStoreConnectCredentials"
    
    public var issuerID: String
    public var keyID: String
    
    /// The `.p8` file's PEM text.
    public var privateKey: String
    
    public init(issuerID: String, keyID: String, privateKey: String) {
        self.issuerID = issuerID
        self.keyID = keyID
        self.privateKey = privateKey
    }
}

public enum AppStoreConnectError: Error, Equatable, LocalizedError {
    case missingCredentials
    case invalidKey(String)
    case http(Int, String)
    case unexpectedResponse(String)
    case notFound(String)
    case checksumMismatch(String)
    
    public var errorDescription: String? {
        switch self {
        case .missingCredentials: "Add an App Store Connect API key in Settings first."
        case let .invalidKey(reason): "The API key couldn't be read: \(reason)"
        case let .http(status, body): "App Store Connect returned \(status): \(body)"
        case let .unexpectedResponse(what): "App Store Connect sent an unexpected response for \(what)."
        case let .notFound(what): "\(what) wasn't found in App Store Connect."
        case let .checksumMismatch(name): "\(name) changed while it was uploading."
        }
    }
}

/// Signs App Store Connect API tokens: ES256 JWTs, at most 20 minutes long.
///
/// > Warning: App Store Connect needs the signature's raw 64-byte form (`signature.rawRepresentation`), not
/// > CryptoKit's DER form, which it rejects as unauthorized.
public enum AppStoreConnectToken {
    public static let audience = "appstoreconnect-v1"
    public static let maximumLifetime: TimeInterval = 20 * 60
    
    public static func make(_ credentials: AppStoreConnectCredentials, now: Date, lifetime: TimeInterval = 19 * 60) throws(AppStoreConnectError) -> String {
        let key: P256.Signing.PrivateKey
        
        do {
            key = try P256.Signing.PrivateKey(pemRepresentation: credentials.privateKey)
        } catch {
            throw .invalidKey(error.localizedDescription)
        }
        
        let issuedAt = Int(now.timeIntervalSince1970)
        let header = #"{"alg":"ES256","kid":"\#(credentials.keyID)","typ":"JWT"}"#
        let claims = #"{"aud":"\#(audience)","exp":\#(issuedAt + Int(min(lifetime, maximumLifetime))),"iat":\#(issuedAt),"iss":"\#(credentials.issuerID)"}"#
        let signingInput = base64URL(Data(header.utf8)) + "." + base64URL(Data(claims.utf8))
        
        let signature: P256.Signing.ECDSASignature
        
        do {
            signature = try key.signature(for: Data(signingInput.utf8))
        } catch {
            throw .invalidKey(error.localizedDescription)
        }
        
        return signingInput + "." + base64URL(signature.rawRepresentation)
    }
    
    public static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
    
    public static func decodeBase64URL(_ string: String) -> Data? {
        var base64 = string.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        
        while base64.count % 4 != 0 {
            base64 += "="
        }
        
        return Data(base64Encoded: base64)
    }
}

/// Caches a token until shortly before it expires.
public actor AppStoreConnectTokenCache {
    private let credentials: AppStoreConnectCredentials
    private let clock: any ClockProvider
    private var cached: (token: String, expires: Date)?
    
    public init(credentials: AppStoreConnectCredentials, clock: any ClockProvider) {
        self.credentials = credentials
        self.clock = clock
    }
    
    public func token() throws(AppStoreConnectError) -> String {
        let now = clock.now
        
        if let cached, cached.expires.timeIntervalSince(now) > 60 {
            return cached.token
        }
        
        let token = try AppStoreConnectToken.make(credentials, now: now)
        cached = (token, now.addingTimeInterval(19 * 60))
        return token
    }
}
