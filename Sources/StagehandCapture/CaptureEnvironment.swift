import Foundation
import StagehandModel

/// The settings a capture reads from its process environment.
///
/// Stagehand's runner sends these to the test runner as `TEST_RUNNER_STAGEHAND_*` variables, which
/// `xcodebuild` passes on without the prefix.
public struct CaptureEnvironment: Sendable, Hashable {
    public static let localeKey = "STAGEHAND_LOCALE"
    public static let runIDKey = "STAGEHAND_RUN_ID"
    public static let expectedClassKey = "STAGEHAND_EXPECTED_CLASS"
    public static let folderOutputKey = "STAGEHAND_FOLDER_OUTPUT"
    public static let appLanguageKey = "STAGEHAND_APP_LANGUAGE"
    public static let appRegionKey = "STAGEHAND_APP_REGION"
    public static let simulatorModelKey = "SIMULATOR_MODEL_IDENTIFIER"
    public static let simulatorRuntimeKey = "SIMULATOR_RUNTIME_VERSION"
    
    public var locale: String?
    public var runID: String?
    public var expectedClass: DeviceClass?
    public var isFolderOutputEnabled: Bool
    
    /// The language and region to launch the app in. `-testLanguage` only reaches the test runner, not the app.
    public var appLanguage: String?
    public var appRegion: String?
    public var simulatorModel: String?
    public var simulatorRuntime: String?
    
    public init(
        locale: String? = nil,
        runID: String? = nil,
        expectedClass: DeviceClass? = nil,
        isFolderOutputEnabled: Bool = true,
        appLanguage: String? = nil,
        appRegion: String? = nil,
        simulatorModel: String? = nil,
        simulatorRuntime: String? = nil
    ) {
        self.locale = locale
        self.runID = runID
        self.expectedClass = expectedClass
        self.isFolderOutputEnabled = isFolderOutputEnabled
        self.appLanguage = appLanguage
        self.appRegion = appRegion
        self.simulatorModel = simulatorModel
        self.simulatorRuntime = simulatorRuntime
    }
    
    /// Reads the settings from an environment, falling back to the preferred language for the locale.
    public init(environment: [String: String], preferredLanguages: [String] = Locale.preferredLanguages) {
        func value(_ key: String) -> String? {
            environment[key].flatMap { $0.isEmpty ? nil : $0 }
        }
        
        self.init(
            locale: value(Self.localeKey) ?? preferredLanguages.first,
            runID: value(Self.runIDKey),
            expectedClass: value(Self.expectedClassKey).flatMap(DeviceClass.init(rawValue:)),
            isFolderOutputEnabled: value(Self.folderOutputKey)?.lowercased() != "off",
            appLanguage: value(Self.appLanguageKey),
            appRegion: value(Self.appRegionKey),
            simulatorModel: value(Self.simulatorModelKey),
            simulatorRuntime: value(Self.simulatorRuntimeKey)
        )
    }
    
    /// The launch arguments that run the app in ``appLanguage`` and ``appRegion``, or none when no language is set.
    public var languageArguments: [String] {
        guard let appLanguage else {
            return []
        }
        
        let locale = appRegion.map { "\(appLanguage)_\($0)" } ?? appLanguage
        return ["-AppleLanguages", "(\(appLanguage))", "-AppleLocale", locale]
    }
    
    /// The current process's settings.
    public static var current: CaptureEnvironment {
        CaptureEnvironment(environment: ProcessInfo.processInfo.environment)
    }
}
