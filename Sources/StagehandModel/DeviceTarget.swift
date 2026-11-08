import Foundation

/// One App Store Connect screenshot slot and the pixel sizes it accepts.
public struct DeviceTarget: Codable, Hashable, Sendable, Identifiable {
    public typealias ID = String
    
    public enum Orientation: String, Codable, Sendable {
        case portrait
        case landscape
    }
    
    /// One accepted size, in the target's own orientation.
    public struct Size: Codable, Hashable, Sendable {
        public var width: Int
        public var height: Int
        
        /// The App Store Connect `ScreenshotDisplayType` for this size, when it differs from the target's.
        public var displayType: String?
        
        public init(width: Int, height: Int, displayType: String? = nil) {
            self.width = width
            self.height = height
            self.displayType = displayType
        }
    }
    
    public var id: ID
    public var name: String
    public var deviceClass: DeviceClass
    public var orientation: Orientation
    public var isRequired: Bool
    
    /// The App Store Connect `ScreenshotDisplayType` value used when uploading.
    public var displayType: String
    
    /// Whether ``displayType`` has been checked against Apple's OpenAPI spec.
    public var displayTypeVerified: Bool
    
    /// Accepted sizes, largest first. Exports use the first one.
    public var sizes: [Size]
    
    public init(
        id: ID,
        name: String,
        deviceClass: DeviceClass,
        orientation: Orientation,
        isRequired: Bool,
        displayType: String,
        displayTypeVerified: Bool = true,
        sizes: [Size]
    ) {
        self.id = id
        self.name = name
        self.deviceClass = deviceClass
        self.orientation = orientation
        self.isRequired = isRequired
        self.displayType = displayType
        self.displayTypeVerified = displayTypeVerified
        self.sizes = sizes
    }
    
    // MARK: - Computed Properties
    
    /// The size exports render at: the largest accepted size.
    public var exportSize: Size {
        sizes[0]
    }
    
    /// Width ÷ height of the export size.
    public var aspectRatio: Double {
        Double(exportSize.width) / Double(exportSize.height)
    }
    
    // MARK: - Functions
    
    /// The display type for one of this target's sizes.
    public func displayType(for size: Size) -> String {
        size.displayType ?? displayType
    }
}
