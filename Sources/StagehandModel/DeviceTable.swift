import Foundation

/// The table of App Store Connect screenshot sizes, loaded from `devices.json`.
///
/// `devices.json` is the only source of screenshot sizes. Stagehand and the capture kit both classify
/// screenshots through it.
public struct DeviceTable: Codable, Sendable, Hashable {
    public var schemaVersion: Int
    
    /// The month the table was last checked against Apple's Screenshot specifications page.
    public var checkedAgainst: String
    public var targets: [DeviceTarget]
    
    public init(schemaVersion: Int = 1, checkedAgainst: String, targets: [DeviceTarget]) {
        self.schemaVersion = schemaVersion
        self.checkedAgainst = checkedAgainst
        self.targets = targets
    }
    
    /// The table bundled with this version of the kit.
    public static let standard: DeviceTable = {
        guard let url = Bundle.module.url(forResource: "devices", withExtension: "json") else {
            preconditionFailure("devices.json is missing from StagehandModel's resources")
        }
        
        do {
            return try JSONDecoder().decode(DeviceTable.self, from: Data(contentsOf: url))
        } catch {
            preconditionFailure("devices.json can't be decoded: \(error)")
        }
    }()
    
    // MARK: - Functions
    
    /// The target with this ID.
    public func target(id: DeviceTarget.ID) -> DeviceTarget? {
        targets.first { $0.id == id }
    }
    
    /// Every target in a device class, in table order.
    public func targets(in deviceClass: DeviceClass) -> [DeviceTarget] {
        targets.filter { $0.deviceClass == deviceClass }
    }
    
    /// The target a screenshot of this pixel size belongs to, in either orientation, or `nil` when no target accepts it.
    public func classify(width: Int, height: Int) -> Classification? {
        for target in targets {
            for size in target.sizes {
                if size.width == width && size.height == height {
                    return Classification(target: target, size: size, isRotated: false)
                }
                
                if size.width == height && size.height == width {
                    return Classification(target: target, size: size, isRotated: true)
                }
            }
        }
        
        return nil
    }
    
    /// The result of classifying a pixel size.
    public struct Classification: Hashable, Sendable {
        public var target: DeviceTarget
        public var size: DeviceTarget.Size
        
        /// Whether the image is in the other orientation from the target's (landscape for a portrait target).
        public var isRotated: Bool
        
        public var deviceClass: DeviceClass {
            target.deviceClass
        }
    }
}
