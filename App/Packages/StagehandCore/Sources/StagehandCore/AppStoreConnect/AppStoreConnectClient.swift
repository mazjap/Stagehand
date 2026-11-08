import CryptoKit
import Dependencies
import Foundation

/// Sends HTTP requests, so tests can use a fake.
public protocol HTTPTransport: Sendable {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

public struct URLSessionTransport: HTTPTransport {
    public init() {}
    
    public func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let http = response as? HTTPURLResponse else {
            throw AppStoreConnectError.unexpectedResponse(request.url?.path ?? "")
        }
        
        return (data, http)
    }
}

public struct ASCResource: Hashable, Sendable {
    public var id: String
    public var attributes: [String: JSONValue]
    
    public func string(_ key: String) -> String? {
        if case let .string(value) = attributes[key] { value } else { nil }
    }
    
    public func int(_ key: String) -> Int? {
        if case let .number(value) = attributes[key] { Int(value) } else { nil }
    }
}

/// A screenshot already in App Store Connect.
public struct ASCScreenshot: Hashable, Sendable, Identifiable {
    public var id: String
    public var fileName: String
    public var checksum: String?
}

/// Where to send one part of an upload.
public struct ASCUploadOperation: Hashable, Sendable {
    public var method: String
    public var url: URL
    public var offset: Int
    public var length: Int
    public var headers: [String: String]
}

/// A localization screenshots belong to: an App Store version's, or a custom product page version's.
public struct ASCLocalization: Hashable, Sendable {
    public enum Kind: Hashable, Sendable {
        case version
        case customProductPage
    }
    
    public var id: String
    public var kind: Kind
    
    public init(id: String, kind: Kind) {
        self.id = id
        self.kind = kind
    }
    
    var resourceType: String {
        switch kind {
        case .version: "appStoreVersionLocalizations"
        case .customProductPage: "appCustomProductPageLocalizations"
        }
    }
    
    var relationship: String {
        switch kind {
        case .version: "appStoreVersionLocalization"
        case .customProductPage: "appCustomProductPageLocalization"
        }
    }
}

/// The endpoints Stagehand uses, for finding an app's editable version and managing its screenshot sets.
///
/// > Warning: Nothing is uploaded, deleted or reordered without the user's explicit confirmation, every time.
public protocol AppStoreConnectProvider: Sendable {
    func appID(bundleID: String) async throws -> String
    func editableVersionID(appID: String, platform: String) async throws -> String
    func localizations(versionID: String) async throws -> [String: String]
    
    /// A custom product page's editable version's localizations, by locale.
    func customProductPageLocalizations(pageID: String) async throws -> [String: String]
    func screenshotSets(localization: ASCLocalization) async throws -> [String: String]
    func createScreenshotSet(localization: ASCLocalization, displayType: String) async throws -> String
    func screenshots(setID: String) async throws -> [ASCScreenshot]
    func reserveScreenshot(setID: String, fileName: String, fileSize: Int) async throws -> (id: String, operations: [ASCUploadOperation])
    func uploadParts(_ data: Data, operations: [ASCUploadOperation]) async throws
    func commitScreenshot(id: String, checksum: String) async throws
    func deleteScreenshot(id: String) async throws
    func reorderScreenshots(setID: String, ids: [String]) async throws
}

/// A small hand-written client, with Apple's published OpenAPI spec as the reference.
public struct AppStoreConnectClient: AppStoreConnectProvider {
    public static let baseURL = URL(string: "https://api.appstoreconnect.apple.com")!
    
    private let transport: any HTTPTransport
    private let tokens: AppStoreConnectTokenCache
    
    public init(transport: any HTTPTransport, tokens: AppStoreConnectTokenCache) {
        self.transport = transport
        self.tokens = tokens
    }
    
    // MARK: - Endpoints
    
    public func appID(bundleID: String) async throws -> String {
        let apps = try await list("/v1/apps", query: ["filter[bundleId]": bundleID])
        
        guard let app = apps.first else {
            throw AppStoreConnectError.notFound("An app with the bundle identifier \(bundleID)")
        }
        
        return app.id
    }
    
    public func editableVersionID(appID: String, platform: String) async throws -> String {
        let versions = try await list("/v1/apps/\(appID)/appStoreVersions", query: [
            "filter[platform]": platform,
            "filter[appStoreState]": "PREPARE_FOR_SUBMISSION,DEVELOPER_REJECTED,REJECTED,METADATA_REJECTED",
        ])
        
        guard let version = versions.first else {
            throw AppStoreConnectError.notFound("An editable \(platform) version")
        }
        
        return version.id
    }
    
    public func localizations(versionID: String) async throws -> [String: String] {
        let resources = try await list("/v1/appStoreVersions/\(versionID)/appStoreVersionLocalizations")
        return Dictionary(resources.compactMap { resource in resource.string("locale").map { ($0, resource.id) } }, uniquingKeysWith: { first, _ in first })
    }
    
    public func customProductPageLocalizations(pageID: String) async throws -> [String: String] {
        let versions = try await list("/v1/appCustomProductPages/\(pageID)/appCustomProductPageVersions", query: ["filter[state]": "PREPARE_FOR_SUBMISSION,REJECTED"])
        
        guard let version = versions.first else {
            throw AppStoreConnectError.notFound("An editable version of custom product page \(pageID)")
        }
        
        let resources = try await list("/v1/appCustomProductPageVersions/\(version.id)/appCustomProductPageLocalizations")
        return Dictionary(resources.compactMap { resource in resource.string("locale").map { ($0, resource.id) } }, uniquingKeysWith: { first, _ in first })
    }
    
    public func screenshotSets(localization: ASCLocalization) async throws -> [String: String] {
        let resources = try await list("/v1/\(localization.resourceType)/\(localization.id)/appScreenshotSets")
        return Dictionary(resources.compactMap { resource in resource.string("screenshotDisplayType").map { ($0, resource.id) } }, uniquingKeysWith: { first, _ in first })
    }
    
    public func createScreenshotSet(localization: ASCLocalization, displayType: String) async throws -> String {
        let body: JSONValue = .object(["data": .object([
            "type": .string("appScreenshotSets"),
            "attributes": .object(["screenshotDisplayType": .string(displayType)]),
            "relationships": .object([localization.relationship: .object(["data": .object([
                "type": .string(localization.resourceType),
                "id": .string(localization.id),
            ])])]),
        ])])
        
        return try await single("POST", "/v1/appScreenshotSets", body: body).id
    }
    
    public func screenshots(setID: String) async throws -> [ASCScreenshot] {
        try await list("/v1/appScreenshotSets/\(setID)/appScreenshots").map { resource in
            ASCScreenshot(id: resource.id, fileName: resource.string("fileName") ?? "", checksum: resource.string("sourceFileChecksum"))
        }
    }
    
    public func reserveScreenshot(setID: String, fileName: String, fileSize: Int) async throws -> (id: String, operations: [ASCUploadOperation]) {
        let body: JSONValue = .object(["data": .object([
            "type": .string("appScreenshots"),
            "attributes": .object(["fileName": .string(fileName), "fileSize": .number(Double(fileSize))]),
            "relationships": .object(["appScreenshotSet": .object(["data": .object([
                "type": .string("appScreenshotSets"),
                "id": .string(setID),
            ])])]),
        ])])
        
        let resource = try await single("POST", "/v1/appScreenshots", body: body)
        
        guard case let .array(operations) = resource.attributes["uploadOperations"] else {
            throw AppStoreConnectError.unexpectedResponse("reserving \(fileName)")
        }
        
        return (resource.id, operations.compactMap(Self.operation))
    }
    
    public func uploadParts(_ data: Data, operations: [ASCUploadOperation]) async throws {
        for operation in operations {
            var request = URLRequest(url: operation.url)
            request.httpMethod = operation.method
            
            for (name, value) in operation.headers {
                request.setValue(value, forHTTPHeaderField: name)
            }
            
            let end = min(operation.offset + operation.length, data.count)
            request.httpBody = data.subdata(in: operation.offset..<end)
            let (body, response) = try await transport.send(request)
            
            guard (200..<300).contains(response.statusCode) else {
                throw AppStoreConnectError.http(response.statusCode, String(decoding: body, as: UTF8.self))
            }
        }
    }
    
    public func commitScreenshot(id: String, checksum: String) async throws {
        let body: JSONValue = .object(["data": .object([
            "type": .string("appScreenshots"),
            "id": .string(id),
            "attributes": .object(["uploaded": .bool(true), "sourceFileChecksum": .string(checksum)]),
        ])])
        
        _ = try await send("PATCH", "/v1/appScreenshots/\(id)", body: body)
    }
    
    public func deleteScreenshot(id: String) async throws {
        _ = try await send("DELETE", "/v1/appScreenshots/\(id)")
    }
    
    public func reorderScreenshots(setID: String, ids: [String]) async throws {
        let body: JSONValue = .object(["data": .array(ids.map { .object(["type": .string("appScreenshots"), "id": .string($0)]) })])
        _ = try await send("PATCH", "/v1/appScreenshotSets/\(setID)/relationships/appScreenshots", body: body)
    }
    
    // MARK: - Requests
    
    private func list(_ path: String, query: [String: String] = [:]) async throws -> [ASCResource] {
        let data = try await send("GET", path, query: query)
        
        guard case let .object(root) = try JSONDecoder().decode(JSONValue.self, from: data), case let .array(items) = root["data"] else {
            throw AppStoreConnectError.unexpectedResponse(path)
        }
        
        return items.compactMap(Self.resource)
    }
    
    private func single(_ method: String, _ path: String, body: JSONValue) async throws -> ASCResource {
        let data = try await send(method, path, body: body)
        
        guard case let .object(root) = try JSONDecoder().decode(JSONValue.self, from: data), let item = root["data"], let resource = Self.resource(item) else {
            throw AppStoreConnectError.unexpectedResponse(path)
        }
        
        return resource
    }
    
    private func send(_ method: String, _ path: String, query: [String: String] = [:], body: JSONValue? = nil) async throws -> Data {
        var components = URLComponents(url: Self.baseURL.appending(path: path), resolvingAgainstBaseURL: false)!
        
        if !query.isEmpty {
            components.queryItems = query.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
        }
        
        var request = URLRequest(url: components.url!)
        request.httpMethod = method
        request.setValue("Bearer \(try await tokens.token())", forHTTPHeaderField: "Authorization")
        
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONEncoder().encode(body)
        }
        
        let (data, response) = try await transport.send(request)
        
        guard (200..<300).contains(response.statusCode) else {
            throw AppStoreConnectError.http(response.statusCode, String(decoding: data, as: UTF8.self))
        }
        
        return data
    }
    
    private static func resource(_ value: JSONValue) -> ASCResource? {
        guard case let .object(object) = value, case let .string(id) = object["id"] else {
            return nil
        }
        
        let attributes: [String: JSONValue] = if case let .object(attributes) = object["attributes"] { attributes } else { [:] }
        return ASCResource(id: id, attributes: attributes)
    }
    
    private static func operation(_ value: JSONValue) -> ASCUploadOperation? {
        guard case let .object(object) = value,
              case let .string(method) = object["method"],
              case let .string(url) = object["url"],
              let parsed = URL(string: url),
              case let .number(offset) = object["offset"],
              case let .number(length) = object["length"] else {
            return nil
        }
        
        var headers: [String: String] = [:]
        
        if case let .array(list) = object["requestHeaders"] {
            for header in list {
                if case let .object(pair) = header, case let .string(name) = pair["name"], case let .string(value) = pair["value"] {
                    headers[name] = value
                }
            }
        }
        
        return ASCUploadOperation(method: method, url: parsed, offset: Int(offset), length: Int(length), headers: headers)
    }
}

/// Any JSON value, for the API's loosely shaped responses.
public enum JSONValue: Codable, Hashable, Sendable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case object([String: JSONValue])
    case array([JSONValue])
    case null
    
    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else {
            self = .object(try container.decode([String: JSONValue].self))
        }
    }
    
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        
        switch self {
        case let .string(value): try container.encode(value)
        case let .number(value): try container.encode(value)
        case let .bool(value): try container.encode(value)
        case let .object(value): try container.encode(value)
        case let .array(value): try container.encode(value)
        case .null: try container.encodeNil()
        }
    }
}

extension Data {
    /// The MD5 checksum App Store Connect compares uploads with.
    public var md5: String {
        Insecure.MD5.hash(data: self).map { String(format: "%02x", $0) }.joined()
    }
}
