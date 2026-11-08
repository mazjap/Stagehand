import CryptoKit
import Dependencies
import DependenciesTestSupport
import Foundation
@testable import StagehandCore
import StagehandModel
import Testing

@Suite struct AppStoreConnectTokenTests {
    private let key = P256.Signing.PrivateKey()
    
    private var credentials: AppStoreConnectCredentials {
        AppStoreConnectCredentials(issuerID: "69a6de7e-0000-47e3-e053-5b8c7c11a4d1", keyID: "2X9R4HXF34", privateKey: key.pemRepresentation)
    }
    
    private func parts(_ token: String) throws -> (header: [String: Any], claims: [String: Any], signature: Data, input: String) {
        let pieces = token.split(separator: ".").map(String.init)
        try #require(pieces.count == 3)
        let header = try JSONSerialization.jsonObject(with: #require(AppStoreConnectToken.decodeBase64URL(pieces[0]))) as! [String: Any]
        let claims = try JSONSerialization.jsonObject(with: #require(AppStoreConnectToken.decodeBase64URL(pieces[1]))) as! [String: Any]
        return (header, claims, try #require(AppStoreConnectToken.decodeBase64URL(pieces[2])), pieces[0] + "." + pieces[1])
    }
    
    @Test func theSignatureVerifiesWithThePublicKey() throws {
        let token = try AppStoreConnectToken.make(credentials, now: .sampleDate)
        let (_, _, signature, input) = try parts(token)
        
        // The raw 64-byte form, not DER.
        #expect(signature.count == 64)
        let parsed = try P256.Signing.ECDSASignature(rawRepresentation: signature)
        #expect(key.publicKey.isValidSignature(parsed, for: Data(input.utf8)))
    }
    
    @Test func theHeaderAndClaimsAreWhatAppStoreConnectExpects() throws {
        let token = try AppStoreConnectToken.make(credentials, now: .sampleDate, lifetime: 60 * 60)
        let (header, claims, _, _) = try parts(token)
        
        #expect(header["alg"] as? String == "ES256")
        #expect(header["kid"] as? String == "2X9R4HXF34")
        #expect(header["typ"] as? String == "JWT")
        #expect(claims["iss"] as? String == credentials.issuerID)
        #expect(claims["aud"] as? String == "appstoreconnect-v1")
        
        let issued = try #require(claims["iat"] as? Int)
        let expires = try #require(claims["exp"] as? Int)
        #expect(issued == Int(Date.sampleDate.timeIntervalSince1970))
        #expect(expires - issued == 20 * 60)
    }
    
    @Test func anInvalidKeyIsAnError() {
        let bad = AppStoreConnectCredentials(issuerID: "i", keyID: "k", privateKey: "not a key")
        #expect(throws: AppStoreConnectError.self) { try AppStoreConnectToken.make(bad, now: .sampleDate) }
    }
    
    @Test func theCacheReusesATokenUntilShortlyBeforeItExpires() async throws {
        final class MovingClock: ClockProvider, @unchecked Sendable {
            var now: Date = .sampleDate
        }
        
        let clock = MovingClock()
        let cache = AppStoreConnectTokenCache(credentials: credentials, clock: clock)
        let first = try await cache.token()
        clock.now = Date.sampleDate.addingTimeInterval(10 * 60)
        #expect(try await cache.token() == first)
        clock.now = Date.sampleDate.addingTimeInterval(18.5 * 60)
        #expect(try await cache.token() != first)
    }
}

/// Answers requests from canned JSON and records them.
final class FakeTransport: HTTPTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [URLRequest] = []
    private let respond: @Sendable (URLRequest) -> (Int, String)
    
    init(respond: @escaping @Sendable (URLRequest) -> (Int, String)) {
        self.respond = respond
    }
    
    var requests: [URLRequest] {
        lock.withLock { recorded }
    }
    
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        lock.withLock { recorded.append(request) }
        let (status, body) = respond(request)
        return (Data(body.utf8), HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!)
    }
}

@Suite struct AppStoreConnectClientTests {
    private func client(_ transport: FakeTransport) -> AppStoreConnectClient {
        let credentials = AppStoreConnectCredentials(issuerID: "issuer", keyID: "KEY", privateKey: P256.Signing.PrivateKey().pemRepresentation)
        return AppStoreConnectClient(transport: transport, tokens: AppStoreConnectTokenCache(credentials: credentials, clock: FixedClock()))
    }
    
    @Test func findsTheAppByBundleIdentifierWithABearerToken() async throws {
        let transport = FakeTransport { _ in (200, #"{"data":[{"id":"1234","type":"apps","attributes":{"bundleId":"com.mazjap.TrekPoint"}}]}"#) }
        let id = try await client(transport).appID(bundleID: "com.mazjap.TrekPoint")
        let request = try #require(transport.requests.first)
        
        #expect(id == "1234")
        #expect(request.url?.absoluteString == "https://api.appstoreconnect.apple.com/v1/apps?filter%5BbundleId%5D=com.mazjap.TrekPoint")
        #expect(request.value(forHTTPHeaderField: "Authorization")?.hasPrefix("Bearer ey") == true)
    }
    
    @Test func anErrorStatusThrows() async {
        let transport = FakeTransport { _ in (401, #"{"errors":[{"status":"401"}]}"#) }
        await #expect(throws: AppStoreConnectError.self) { try await client(transport).appID(bundleID: "x") }
    }
    
    @Test func reservingParsesTheUploadOperations() async throws {
        let transport = FakeTransport { _ in
            (201, #"{"data":{"id":"shot-1","type":"appScreenshots","attributes":{"uploadOperations":[{"method":"PUT","url":"https://upload.example/part1","offset":0,"length":3,"requestHeaders":[{"name":"Content-Type","value":"image/png"}]}]}}}"#)
        }
        let reservation = try await client(transport).reserveScreenshot(setID: "set-1", fileName: "01-read.png", fileSize: 3)
        
        #expect(reservation.id == "shot-1")
        #expect(reservation.operations == [ASCUploadOperation(method: "PUT", url: URL(string: "https://upload.example/part1")!, offset: 0, length: 3, headers: ["Content-Type": "image/png"])])
        
        let body = try JSONSerialization.jsonObject(with: #require(transport.requests.first?.httpBody)) as? [String: Any]
        let data = body?["data"] as? [String: Any]
        #expect((data?["attributes"] as? [String: Any])?["fileName"] as? String == "01-read.png")
    }
    
    @Test func uploadPartsSendsEachRangeWithoutTheToken() async throws {
        let transport = FakeTransport { _ in (200, "") }
        let operations = [
            ASCUploadOperation(method: "PUT", url: URL(string: "https://upload.example/1")!, offset: 0, length: 2, headers: [:]),
            ASCUploadOperation(method: "PUT", url: URL(string: "https://upload.example/2")!, offset: 2, length: 2, headers: [:]),
        ]
        try await client(transport).uploadParts(Data([1, 2, 3, 4]), operations: operations)
        
        #expect(transport.requests.map(\.httpBody) == [Data([1, 2]), Data([3, 4])])
        #expect(transport.requests.allSatisfy { $0.value(forHTTPHeaderField: "Authorization") == nil })
    }
    
    @Test func reorderingSendsTheIDsInOrder() async throws {
        let transport = FakeTransport { _ in (204, "") }
        try await client(transport).reorderScreenshots(setID: "set-1", ids: ["b", "a"])
        let request = try #require(transport.requests.first)
        
        #expect(request.httpMethod == "PATCH")
        #expect(request.url?.path() == "/v1/appScreenshotSets/set-1/relationships/appScreenshots")
        let body = try JSONSerialization.jsonObject(with: #require(request.httpBody)) as? [String: Any]
        #expect((body?["data"] as? [[String: Any]])?.compactMap { $0["id"] as? String } == ["b", "a"])
    }
}

@Suite struct UploadPlannerTests {
    private let target = DeviceTable.target("iphone-dynamic-island-large")
    
    @Test func unchangedImagesAreSkippedByChecksum() {
        let a = DesiredScreenshot(fileName: "01.png", data: Data([1]))
        let b = DesiredScreenshot(fileName: "02.png", data: Data([2]))
        let existing = [ASCScreenshot(id: "x", fileName: "01.png", checksum: a.checksum), ASCScreenshot(id: "y", fileName: "02.png", checksum: b.checksum)]
        let plan = UploadPlanner.plan(locale: "en-US", target: target, localization: ASCLocalization(id: "l", kind: .version), setID: "s", desired: [a, b], existing: existing)
        
        #expect(plan.uploads.isEmpty)
        #expect(plan.deletions.isEmpty)
        #expect(!plan.needsReorder)
        #expect(!plan.hasChanges)
    }
    
    @Test func changedImagesAreUploadedAndOldOnesDeleted() {
        let a = DesiredScreenshot(fileName: "01.png", data: Data([1]))
        let changed = DesiredScreenshot(fileName: "02.png", data: Data([9]))
        let existing = [ASCScreenshot(id: "x", fileName: "01.png", checksum: a.checksum), ASCScreenshot(id: "y", fileName: "02.png", checksum: Data([2]).md5)]
        let plan = UploadPlanner.plan(locale: "en-US", target: target, localization: ASCLocalization(id: "l", kind: .version), setID: "s", desired: [a, changed], existing: existing)
        
        #expect(plan.uploads == [changed])
        #expect(plan.deletions.map(\.id) == ["y"])
        #expect(plan.unchanged.map(\.id) == ["x"])
        #expect(plan.summary == "Upload 1, delete 1, keep 1, reorder")
    }
    
    @Test func aNewOrderIsAReorder() {
        let a = DesiredScreenshot(fileName: "01.png", data: Data([1]))
        let b = DesiredScreenshot(fileName: "02.png", data: Data([2]))
        let existing = [ASCScreenshot(id: "y", fileName: "02.png", checksum: b.checksum), ASCScreenshot(id: "x", fileName: "01.png", checksum: a.checksum)]
        let plan = UploadPlanner.plan(locale: "en-US", target: target, localization: ASCLocalization(id: "l", kind: .version), setID: "s", desired: [a, b], existing: existing)
        
        #expect(plan.needsReorder)
        #expect(plan.uploads.isEmpty)
    }
    
    @Test func keepingAppStoreConnectsOrderNeverReorders() {
        let a = DesiredScreenshot(fileName: "01.png", data: Data([1]))
        let b = DesiredScreenshot(fileName: "02.png", data: Data([2]))
        let c = DesiredScreenshot(fileName: "03.png", data: Data([3]))
        let existing = [ASCScreenshot(id: "y", fileName: "02.png", checksum: b.checksum), ASCScreenshot(id: "x", fileName: "01.png", checksum: a.checksum)]
        let plan = UploadPlanner.plan(locale: "en-US", target: target, localization: ASCLocalization(id: "l", kind: .version), setID: "s", desired: [a, b, c], existing: existing, keepsOrder: true)
        
        #expect(!plan.needsReorder)
        #expect(plan.uploads == [c])
        #expect(plan.summary == "Upload 1, keep 2")
    }
}

/// Records every call, and never touches the network.
final class FakeAppStoreConnect: AppStoreConnectProvider, @unchecked Sendable {
    private let lock = NSLock()
    private var log: [String] = []
    var existing: [ASCScreenshot] = []
    
    var calls: [String] {
        lock.withLock { log }
    }
    
    private func record(_ call: String) {
        lock.withLock { log.append(call) }
    }
    
    func appID(bundleID: String) async throws -> String { record("app"); return "app" }
    func editableVersionID(appID: String, platform: String) async throws -> String { record("version \(platform)"); return "v" }
    func localizations(versionID: String) async throws -> [String: String] { record("localizations"); return ["en-US": "loc"] }
    func customProductPageLocalizations(pageID: String) async throws -> [String: String] { record("page \(pageID)"); return ["en-US": "page-loc"] }
    func screenshotSets(localization: ASCLocalization) async throws -> [String: String] {
        record("sets \(localization.id)")
        return localization.kind == .version ? ["APP_IPHONE_67": "set-phone"] : [:]
    }
    func createScreenshotSet(localization: ASCLocalization, displayType: String) async throws -> String { record("create \(localization.id) \(displayType)"); return "new-\(displayType)" }
    func screenshots(setID: String) async throws -> [ASCScreenshot] { record("screenshots \(setID)"); return setID == "set-phone" ? existing : [] }
    func reserveScreenshot(setID: String, fileName: String, fileSize: Int) async throws -> (id: String, operations: [ASCUploadOperation]) { record("reserve \(setID) \(fileName)"); return ("id-\(fileName)", []) }
    func uploadParts(_ data: Data, operations: [ASCUploadOperation]) async throws { record("upload") }
    func commitScreenshot(id: String, checksum: String) async throws { record("commit \(id)") }
    func deleteScreenshot(id: String) async throws { record("delete \(id)") }
    func reorderScreenshots(setID: String, ids: [String]) async throws { record("reorder \(setID)") }
}

@MainActor
@Suite(.dependencies) struct UploadCoordinatorTests {
    @Test func planningOnlyReadsAndUploadingWaitsForConfirmation() async throws {
        let fake = FakeAppStoreConnect()
        let keychain = InMemoryKeychain()
        let credentials = AppStoreConnectCredentials(issuerID: "i", keyID: "k", privateKey: P256.Signing.PrivateKey().pemRepresentation)
        try keychain.write(JSONEncoder().encode(credentials), account: AppStoreConnectCredentials.keychainAccount)
        
        try await withDependencies {
            $0.keychain = keychain
            $0.appStoreConnect = AppStoreConnectFactory { _ in fake }
        } operation: {
            let project = ProjectCoordinator(document: ProjectDocument(contents: ProjectContents(project: .fixture())), measurer: FakeTextMeasurer())
            await project.start()
            let upload = UploadCoordinator(project: project)
            await upload.plan()
            
            let plans = upload.plans
            #expect(plans.count == 2)
            #expect(plans.allSatisfy { $0.uploads.count == 3 })
            #expect(fake.calls.allSatisfy { !$0.hasPrefix("reserve") && !$0.hasPrefix("delete") && !$0.hasPrefix("create") && !$0.hasPrefix("reorder") })
            
            upload.handle(.confirmUpload)
            
            for _ in 0..<200 where !fake.calls.contains(where: { $0.hasPrefix("reorder new-") }) {
                try await Task.sleep(for: .milliseconds(10))
            }
            
            #expect(fake.calls.contains("create loc APP_IPAD_PRO_3GEN_129"))
            #expect(fake.calls.filter { $0.hasPrefix("commit") }.count == 6)
            #expect(fake.calls.contains("reorder set-phone"))
        }
    }
    
    @Test func aCustomProductPageUploadsToThatPage() async throws {
        let fake = FakeAppStoreConnect()
        let keychain = InMemoryKeychain()
        let credentials = AppStoreConnectCredentials(issuerID: "i", keyID: "k", privateKey: P256.Signing.PrivateKey().pemRepresentation)
        try keychain.write(JSONEncoder().encode(credentials), account: AppStoreConnectCredentials.keychainAccount)
        var project = Project.fixture()
        project.productPages = [ProductPage(name: "Hikers", pageID: "cpp-1", slideIDs: project.slideOrder)]
        
        try await withDependencies {
            $0.keychain = keychain
            $0.appStoreConnect = AppStoreConnectFactory { _ in fake }
        } operation: {
            let coordinator = ProjectCoordinator(document: ProjectDocument(contents: ProjectContents(project: project)), measurer: FakeTextMeasurer())
            await coordinator.start()
            let upload = UploadCoordinator(project: coordinator)
            await upload.plan()
            
            // The main lineup plans against the version, and the page against its own localizations.
            let pagePlans = upload.plans.filter { $0.customProductPageID == "cpp-1" }
            #expect(fake.calls.contains("page cpp-1"))
            #expect(pagePlans.count == 2)
            #expect(pagePlans.allSatisfy { $0.localization == ASCLocalization(id: "page-loc", kind: .customProductPage) && $0.setID == nil })
            #expect(pagePlans.allSatisfy { $0.id.hasPrefix("cpp-1/") })
            #expect(upload.plans.count == 4)
        }
    }
    
    @Test func theCustomProductPageRelationshipIsUsedWhenCreatingASet() async throws {
        let transport = FakeTransport { _ in (201, #"{"data":{"id":"set-9","type":"appScreenshotSets"}}"#) }
        let credentials = AppStoreConnectCredentials(issuerID: "issuer", keyID: "KEY", privateKey: P256.Signing.PrivateKey().pemRepresentation)
        let client = AppStoreConnectClient(transport: transport, tokens: AppStoreConnectTokenCache(credentials: credentials, clock: FixedClock()))
        let id = try await client.createScreenshotSet(localization: ASCLocalization(id: "loc-1", kind: .customProductPage), displayType: "APP_IPHONE_67")
        let body = try JSONSerialization.jsonObject(with: #require(transport.requests.first?.httpBody)) as? [String: Any]
        let relationships = (body?["data"] as? [String: Any])?["relationships"] as? [String: Any]
        
        #expect(id == "set-9")
        #expect(relationships?["appCustomProductPageLocalization"] != nil)
    }
    
    @Test func planningWithoutAKeyFails() async {
        await withDependencies {
            $0.keychain = InMemoryKeychain()
        } operation: {
            let project = ProjectCoordinator(document: ProjectDocument(contents: ProjectContents(project: .fixture())), measurer: FakeTextMeasurer())
            let upload = UploadCoordinator(project: project)
            await upload.plan()
            #expect(upload.phase == .failed(AppStoreConnectError.missingCredentials.errorDescription!))
        }
    }
}
