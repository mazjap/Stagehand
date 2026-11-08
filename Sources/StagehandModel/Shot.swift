import Foundation

/// The metadata saved with every capture.
///
/// > Warning: Other repositories decode this at pinned versions. A change needs a new ``schemaVersion``,
/// > and Stagehand keeps reading the old ones.
public struct Shot: Codable, Sendable, Hashable {
    /// The current schema version.
    public static let currentSchemaVersion = 1
    
    public var schemaVersion: Int
    public var captureID: UUID
    
    /// The capture key.
    public var name: String
    public var scene: String?
    
    /// `nil` when the size isn't in `devices.json`.
    public var deviceClass: DeviceClass?
    public var targetID: String?
    public var pixelWidth: Int
    public var pixelHeight: Int
    
    /// `STAGEHAND_LOCALE`, or else the test runner's preferred language.
    public var locale: String?
    
    /// `STAGEHAND_RUN_ID`, set by Stagehand's runner.
    public var runID: String?
    public var simulatorModel: String?
    public var simulatorRuntime: String?
    public var quirksApplied: [String]
    public var capturedAt: Date
    
    public init(
        schemaVersion: Int = Shot.currentSchemaVersion,
        captureID: UUID,
        name: String,
        scene: String? = nil,
        deviceClass: DeviceClass?,
        targetID: String?,
        pixelWidth: Int,
        pixelHeight: Int,
        locale: String? = nil,
        runID: String? = nil,
        simulatorModel: String? = nil,
        simulatorRuntime: String? = nil,
        quirksApplied: [String] = [],
        capturedAt: Date
    ) {
        self.schemaVersion = schemaVersion
        self.captureID = captureID
        self.name = name
        self.scene = scene
        self.deviceClass = deviceClass
        self.targetID = targetID
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.locale = locale
        self.runID = runID
        self.simulatorModel = simulatorModel
        self.simulatorRuntime = simulatorRuntime
        self.quirksApplied = quirksApplied
        self.capturedAt = capturedAt
    }
    
    // MARK: - Functions
    
    /// A JSON encoder with the settings `Shot` metadata is written with.
    public static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
    
    /// A JSON decoder that reads every schema version Stagehand knows.
    public static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
