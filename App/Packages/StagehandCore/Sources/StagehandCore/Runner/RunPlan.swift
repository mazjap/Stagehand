import Foundation
import StagehandModel

/// Which displays a pass expects the simulator to show.
public enum Posture: String, Hashable, Sendable {
    /// However the simulator boots.
    case asBooted
    
    /// An iPhone Duo opened, which has to be done by hand in Device Hub for now.
    case unfolded
}

/// What a run captures: one pass per device class and locale, on that class's simulator.
public struct RunPlan: Hashable, Sendable {
    public struct Pass: Hashable, Sendable, Identifiable, CustomStringConvertible {
        public var deviceClass: DeviceClass
        public var simulatorName: String
        public var simulator: SimulatorSpec?
        public var platform: Platform
        public var locale: LocaleID
        public var appLocale: AppLocale
        public var onlyTesting: [String]
        public var posture: Posture
        
        public var id: String {
            "\(deviceClass.rawValue)-\(locale)"
        }
        
        public var developerDir: String? {
            simulator?.developerDir
        }
        
        public var description: String {
            "\(deviceClass.displayName) (\(locale))"
        }
    }
    
    public enum Platform: String, Hashable, Sendable {
        case iOSSimulator = "iOS Simulator"
        case watchOSSimulator = "watchOS Simulator"
        case macOS
        
        public init(_ deviceClass: DeviceClass) {
            self = switch deviceClass {
            case .watch: .watchOSSimulator
            case .mac: .macOS
            case .phone, .duoOuter, .duoInner, .pad: .iOSSimulator
            }
        }
        
        /// The `.xctestrun` file name's SDK, like `iphonesimulator`.
        var sdkName: String {
            switch self {
            case .iOSSimulator: "iphonesimulator"
            case .watchOSSimulator: "watchsimulator"
            case .macOS: "macosx"
            }
        }
    }
    
    public var passes: [Pass]
    
    public init(passes: [Pass]) {
        self.passes = passes
    }
    
    /// Builds needed, one per developer directory and platform.
    public var builds: [BuildKey] {
        var seen = Set<BuildKey>()
        return passes.map { BuildKey(developerDir: $0.developerDir, platform: $0.platform) }.filter { seen.insert($0).inserted }
    }
    
    public struct BuildKey: Hashable, Sendable {
        public var developerDir: String?
        public var platform: Platform
    }
    
    /// The simulator a class runs on. The Duo's two displays share one.
    public static func simulatorName(for deviceClass: DeviceClass, table: DeviceTable = .standard) -> String {
        switch deviceClass {
        case .duoOuter, .duoInner: "Stagehand iphone-duo"
        default: "Stagehand " + (table.targets(in: deviceClass).first?.id ?? deviceClass.rawValue)
        }
    }
    
    /// A plan for every capture the project's sets need, in each app locale.
    ///
    /// Passes are ordered by developer directory and simulator, and the Duo's outer display comes before its inner one,
    /// since it boots folded.
    public static func make(
        project: Project,
        classes: [DeviceClass]? = nil,
        locales: [LocaleID]? = nil,
        onlyTesting: [String] = []
    ) -> RunPlan {
        let link = project.appLink
        let wanted = classes ?? DeviceClass.allCases.filter(project.devices.contains)
        let locales = locales ?? project.appLocales
        var passes: [Pass] = []
        
        for device in wanted {
            for locale in locales {
                passes.append(Pass(
                    deviceClass: device,
                    simulatorName: simulatorName(for: device),
                    simulator: link?.simulators[device] ?? (device == .duoOuter ? link?.simulators[.duoInner] : device == .duoInner ? link?.simulators[.duoOuter] : nil),
                    platform: Platform(device),
                    locale: locale,
                    appLocale: project.appLocale(for: locale),
                    onlyTesting: onlyTesting,
                    posture: device == .duoInner ? .unfolded : .asBooted
                ))
            }
        }
        
        let order: [DeviceClass] = [.phone, .pad, .duoOuter, .duoInner, .watch, .mac]
        passes.sort { lhs, rhs in
            let left = (lhs.developerDir ?? "", order.firstIndex(of: lhs.deviceClass) ?? 0, lhs.locale)
            let right = (rhs.developerDir ?? "", order.firstIndex(of: rhs.deviceClass) ?? 0, rhs.locale)
            return left < right
        }
        
        return RunPlan(passes: passes)
    }
}
