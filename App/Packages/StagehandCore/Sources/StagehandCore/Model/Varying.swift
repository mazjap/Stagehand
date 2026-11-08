import Foundation
import StagehandModel

/// A value that's shared across device classes unless a class overrides it.
///
/// Everything that's "linked by default" is a `Varying`: slide text, capture keys, variants, and the style's
/// fonts, sizes and colors. An override equal to the base is removed, so a badge never shows "overridden"
/// for a value that matches the shared one.
public struct Varying<Value: Codable & Equatable & Sendable>: Codable, Equatable, Sendable {
    public var base: Value
    public var overrides: [DeviceClass: Value]
    
    public init(_ base: Value, overrides: [DeviceClass: Value] = [:]) {
        self.base = base
        self.overrides = overrides
        normalize()
    }
    
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.base = try container.decode(Value.self, forKey: .base)
        self.overrides = try container.decodeIfPresent([DeviceClass: Value].self, forKey: .overrides) ?? [:]
    }
    
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(base, forKey: .base)
        
        if !overrides.isEmpty {
            try container.encode(overrides, forKey: .overrides)
        }
    }
    
    private enum CodingKeys: String, CodingKey {
        case base
        case overrides
    }
    
    // MARK: - Functions
    
    /// The value for a device class: its override, or the shared value.
    public subscript(_ device: DeviceClass) -> Value {
        overrides[device] ?? base
    }
    
    public func isOverridden(for device: DeviceClass) -> Bool {
        overrides[device] != nil
    }
    
    /// Sets the value where an edit for this class belongs: its override when it has one, or the shared value.
    public mutating func set(_ value: Value, for device: DeviceClass, scope: EditScope = .automatic) {
        switch resolvedScope(scope, for: device) {
        case .shared:
            base = value
        case .override:
            overrides[device] = value
        }
        
        normalize()
    }
    
    /// Changes the value where an edit for this class belongs.
    public mutating func update(for device: DeviceClass, scope: EditScope = .automatic, _ body: (inout Value) -> Void) {
        var value = self[device]
        body(&value)
        set(value, for: device, scope: scope)
    }
    
    /// Gives a class its own copy of the shared value. It's removed again unless it's then changed.
    public mutating func override(for device: DeviceClass, with value: Value? = nil) {
        overrides[device] = value ?? self[device]
    }
    
    /// Removes a class's override, so it uses the shared value again.
    public mutating func revert(_ device: DeviceClass) {
        overrides[device] = nil
    }
    
    /// Removes every override that's equal to the shared value.
    public mutating func normalize() {
        overrides = overrides.filter { $0.value != base }
    }
    
    /// Which value an edit with this scope changes.
    public func resolvedScope(_ scope: EditScope, for device: DeviceClass) -> EditScope.Resolved {
        switch scope {
        case .automatic: isOverridden(for: device) ? .override : .shared
        case .shared: .shared
        case .override: .override
        }
    }
    
    /// Transforms every value, keeping the same overrides.
    public func map<T>(_ transform: (Value) -> T) -> Varying<T> {
        Varying<T>(transform(base), overrides: overrides.mapValues(transform))
    }
}

/// Where an edit to a ``Varying`` goes.
public enum EditScope: String, Codable, Sendable, Hashable {
    /// To the class's override when it has one, or else to the shared value.
    case automatic
    
    /// Always to the shared value.
    case shared
    
    /// Always to the class's override ("Override for <class>").
    case override
    
    public enum Resolved: Sendable, Hashable {
        case shared
        case override
    }
}

extension Varying: Hashable where Value: Hashable {}
