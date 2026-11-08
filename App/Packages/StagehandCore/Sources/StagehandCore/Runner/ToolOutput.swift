import Foundation

/// `xcodebuild -list -json`.
public struct XcodebuildList: Decodable, Hashable, Sendable {
    public struct Container: Decodable, Hashable, Sendable {
        public var name: String
        public var schemes: [String]
        public var targets: [String]?
    }
    
    public var project: Container?
    public var workspace: Container?
    
    public var schemes: [String] {
        (workspace ?? project)?.schemes ?? []
    }
    
    public var targets: [String] {
        project?.targets ?? []
    }
    
    /// Parses the output, which can start with log lines before the JSON.
    public static func parse(_ output: String) throws -> XcodebuildList {
        try JSONDecoder().decode(XcodebuildList.self, from: Data(output.jsonPortion.utf8))
    }
}

/// `xcrun simctl list -j devices devicetypes runtimes`.
public struct SimctlList: Decodable, Hashable, Sendable {
    public struct DeviceType: Decodable, Hashable, Sendable, Identifiable {
        public var identifier: String
        public var name: String
        public var productFamily: String?
        public var modelIdentifier: String?
        
        public var id: String {
            identifier
        }
    }
    
    public struct Runtime: Decodable, Hashable, Sendable, Identifiable {
        public var identifier: String
        public var name: String
        public var version: String
        public var isAvailable: Bool
        public var platform: String?
        public var supportedDeviceTypes: [SupportedDeviceType]?
        
        public var id: String {
            identifier
        }
        
        public struct SupportedDeviceType: Decodable, Hashable, Sendable {
            public var identifier: String
        }
    }
    
    public struct Device: Decodable, Hashable, Sendable, Identifiable {
        public var udid: String
        public var name: String
        public var state: String
        public var isAvailable: Bool?
        public var deviceTypeIdentifier: String?
        
        public var id: String {
            udid
        }
        
        public var isBooted: Bool {
            state == "Booted"
        }
    }
    
    public var devicetypes: [DeviceType]?
    public var runtimes: [Runtime]?
    
    /// Devices by runtime identifier.
    public var devices: [String: [Device]]?
    
    public static func parse(_ output: String) throws -> SimctlList {
        try JSONDecoder().decode(SimctlList.self, from: Data(output.jsonPortion.utf8))
    }
    
    /// The device with this name on a runtime.
    public func device(named name: String, runtime: String) -> Device? {
        devices?[runtime]?.first { $0.name == name && $0.isAvailable != false }
    }
    
    /// Runtimes that can run a device type.
    public func runtimes(supporting deviceType: String) -> [Runtime] {
        (runtimes ?? []).filter { runtime in
            runtime.isAvailable && (runtime.supportedDeviceTypes?.contains { $0.identifier == deviceType } ?? true)
        }
    }
}

extension String {
    /// From the first `{` or `[` to the end, skipping log lines tools print before their JSON.
    var jsonPortion: String {
        guard let start = firstIndex(where: { $0 == "{" || $0 == "[" }) else {
            return self
        }
        
        return String(self[start...])
    }
}
