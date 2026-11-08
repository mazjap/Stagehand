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
    
    /// How many pixels a capture's width and height can each be from a target's size and still be that size.
    ///
    /// Simulators don't always take screenshots at exactly the size of their display: the iPhone Duo's iOS 27.2 simulator
    /// takes its inner display at 2006 × 2852, for a 2007 × 2853 display. Exports are always a target's exact size.
    public static let sizeTolerance = 2
    
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
    ///
    /// A size within `sizeTolerance` of a target's counts as that size, and the closest one wins, so an exact match always
    /// does. `size` is the target's size, not the screenshot's.
    public func classify(width: Int, height: Int) -> Classification? {
        var closest: (classification: Classification, distance: Int)?
        
        for target in targets {
            for size in target.sizes {
                for isRotated in [false, true] {
                    let widthOff = abs(size.width - (isRotated ? height : width))
                    let heightOff = abs(size.height - (isRotated ? width : height))
                    
                    guard widthOff <= Self.sizeTolerance, heightOff <= Self.sizeTolerance else {
                        continue
                    }
                    
                    if widthOff + heightOff < closest?.distance ?? .max {
                        closest = (Classification(target: target, size: size, isRotated: isRotated), widthOff + heightOff)
                    }
                }
            }
        }
        
        return closest?.classification
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
