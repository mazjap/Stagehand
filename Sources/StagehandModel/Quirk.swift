import Foundation

/// A known simulator bug that a capture is corrected for.
///
/// Quirks are keyed on the simulator's model identifier (`SIMULATOR_MODEL_IDENTIFIER`) and runtime
/// (`SIMULATOR_RUNTIME_VERSION`). A quirk applies to every runtime from the oldest it was observed on,
/// since simulator bugs usually outlive a release, until the runtime it's marked fixed in.
public struct Quirk: Codable, Hashable, Sendable, Identifiable {
    /// How a quirk's image is corrected. Every fix is reversible, so Stagehand can undo one on import.
    public enum Fix: String, Codable, Hashable, Sendable {
        case rotate180
        
        /// The fix that undoes this one.
        public var inverse: Fix {
            switch self {
            case .rotate180: .rotate180
            }
        }
    }
    
    public var id: String
    public var modelIdentifiers: [String]
    
    /// The device class the quirk affects, or `nil` for every class on the model.
    public var deviceClass: DeviceClass?
    public var observedRuntimes: [RuntimeVersion]
    public var fixedIn: RuntimeVersion?
    public var fix: Fix
    public var note: String
    
    public init(
        id: String,
        modelIdentifiers: [String],
        deviceClass: DeviceClass?,
        observedRuntimes: [RuntimeVersion],
        fixedIn: RuntimeVersion? = nil,
        fix: Fix,
        note: String
    ) {
        self.id = id
        self.modelIdentifiers = modelIdentifiers
        self.deviceClass = deviceClass
        self.observedRuntimes = observedRuntimes
        self.fixedIn = fixedIn
        self.fix = fix
        self.note = note
    }
    
    /// Every quirk the kit knows.
    public static let all: [Quirk] = [
        Quirk(
            id: "duo-inner-rotated-180",
            modelIdentifiers: ["iPhone19,4"],
            deviceClass: .duoInner,
            observedRuntimes: [RuntimeVersion("27.1")!],
            fix: .rotate180,
            note: "The iPhone Duo simulator's inner display screenshots come back upside down. Observed in TrekPoint, October 2026."
        ),
    ]
    
    // MARK: - Functions
    
    /// Whether this quirk applies to a capture from this model, runtime and class.
    public func applies(model: String?, runtime: RuntimeVersion?, deviceClass: DeviceClass?) -> Bool {
        guard let model, modelIdentifiers.contains(model) else {
            return false
        }
        
        if let quirkClass = self.deviceClass, quirkClass != deviceClass {
            return false
        }
        
        guard let runtime, let oldest = observedRuntimes.min() else {
            return false
        }
        
        if let fixedIn, runtime >= fixedIn {
            return false
        }
        
        return runtime >= oldest
    }
    
    /// Whether a runtime is newer than any this quirk was observed on, so a capture should get one look.
    public func isBeyondObserved(_ runtime: RuntimeVersion?) -> Bool {
        guard let runtime, let newest = observedRuntimes.max() else {
            return false
        }
        
        return runtime > newest
    }
    
    /// The quirks that apply to a capture.
    public static func applicable(
        model: String?,
        runtime: String?,
        deviceClass: DeviceClass?,
        in quirks: [Quirk] = Quirk.all
    ) -> [Quirk] {
        let version = runtime.flatMap(RuntimeVersion.init)
        return quirks.filter { $0.applies(model: model, runtime: version, deviceClass: deviceClass) }
    }
}
