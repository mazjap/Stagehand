import Foundation
import StagehandModel

/// Where a capture lives: its key, device class and locale.
public struct CaptureAddress: Codable, Hashable, Sendable, Comparable, CustomStringConvertible {
    public var key: String
    public var deviceClass: DeviceClass
    public var locale: LocaleID
    
    public init(key: String, deviceClass: DeviceClass, locale: LocaleID) {
        self.key = key
        self.deviceClass = deviceClass
        self.locale = locale
    }
    
    // MARK: - Computed Properties
    
    /// The file's path inside `captures/`: `<capture key>/<device class>/<locale>.png`.
    public var relativePath: String {
        "\(key)/\(deviceClass.rawValue)/\(locale).png"
    }
    
    public var description: String {
        relativePath
    }
    
    // MARK: - Functions
    
    public static func < (lhs: CaptureAddress, rhs: CaptureAddress) -> Bool {
        (lhs.key, lhs.deviceClass.rawValue, lhs.locale) < (rhs.key, rhs.deviceClass.rawValue, rhs.locale)
    }
}

/// One capture's entry in `captures/index.json`.
public struct CaptureRecord: Codable, Hashable, Sendable {
    public enum Source: String, Codable, Hashable, Sendable {
        case dropped
        case runner
    }
    
    public var address: CaptureAddress
    public var pixelWidth: Int
    public var pixelHeight: Int
    public var targetID: DeviceTarget.ID?
    public var source: Source
    public var importedAt: Date
    
    /// The kit's metadata, for captures from the runner.
    public var shot: Shot?
    
    /// Bumped each time the image is replaced, so caches keyed on it refresh.
    public var revision: Int
    
    /// Quirks undone on import because the runtime has been fixed.
    public var quirksUndone: [String]
    
    /// The UI test that made it, for `-only-testing:` when recapturing one cell.
    public var testIdentifier: String?
    
    public init(
        address: CaptureAddress,
        pixelWidth: Int,
        pixelHeight: Int,
        targetID: DeviceTarget.ID?,
        source: Source,
        importedAt: Date,
        shot: Shot? = nil,
        revision: Int = 1,
        quirksUndone: [String] = [],
        testIdentifier: String? = nil
    ) {
        self.address = address
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.targetID = targetID
        self.source = source
        self.importedAt = importedAt
        self.shot = shot
        self.revision = revision
        self.quirksUndone = quirksUndone
        self.testIdentifier = testIdentifier
    }
    
    // MARK: - Computed Properties
    
    /// Quirks applied to a capture from a runtime newer than any the quirk was observed on, which get one look.
    public var quirksToReview: [Quirk] {
        guard let shot else {
            return []
        }
        
        let runtime = shot.simulatorRuntime.flatMap(RuntimeVersion.init)
        return Quirk.all.filter { shot.quirksApplied.contains($0.id) && !quirksUndone.contains($0.id) && $0.isBeyondObserved(runtime) }
    }
}

/// `captures/index.json`: every capture's metadata.
public struct CaptureIndex: Codable, Hashable, Sendable {
    public var records: [CaptureAddress: CaptureRecord]
    
    public init(records: [CaptureAddress: CaptureRecord] = [:]) {
        self.records = records
    }
    
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let list = try container.decode([CaptureRecord].self, forKey: .captures)
        self.records = Dictionary(list.map { ($0.address, $0) }, uniquingKeysWith: { $1 })
    }
    
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(records.values.sorted { $0.address < $1.address }, forKey: .captures)
    }
    
    private enum CodingKeys: String, CodingKey {
        case captures
    }
}
