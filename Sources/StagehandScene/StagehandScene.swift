import Foundation

#if canImport(CoreGraphics)
import CoreGraphics
#endif

/// For app targets: reads the scene Stagehand's capture kit is staging, and whether a capture is running.
///
/// Keep call sites behind `#if DEBUG`, since this ships inside the app itself.
public enum StagehandScene {
    /// The environment variable the scene is sent in, unless the test configures another.
    public static let environmentKey = "STAGEHAND_SCENE"
    
    /// The launch argument the kit always launches with.
    public static let capturingArgument = "-stagehand-capturing"
    
    /// The launch argument a Mac capture sends its window size with, followed by `<width>x<height>`.
    public static let windowSizeArgument = "-stagehand-window-size"
    
    // MARK: - Functions
    
    /// The raw scene string, or `nil` when no scene is being staged.
    public static func current(
        key: String = environmentKey,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> String? {
        guard let value = environment[key], !value.isEmpty else {
            return nil
        }
        
        return value
    }
    
    /// The scene decoded from JSON, or `nil` when there's none or it doesn't decode.
    public static func decode<Scene: Decodable>(
        _ type: Scene.Type,
        key: String = environmentKey,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        decoder: JSONDecoder = JSONDecoder()
    ) -> Scene? {
        guard let string = current(key: key, environment: environment) else {
            return nil
        }
        
        return try? decoder.decode(Scene.self, from: Data(string.utf8))
    }
    
    /// Whether the app was launched by the capture kit.
    public static var isCapturing: Bool {
        isCapturing(arguments: ProcessInfo.processInfo.arguments)
    }
    
    /// Whether these launch arguments come from the capture kit.
    public static func isCapturing(arguments: [String]) -> Bool {
        arguments.contains(capturingArgument)
    }
    
    #if os(macOS)
    /// The window size a Mac capture asked for, so Mac captures always use the same size.
    public static var requestedWindowSize: CGSize? {
        requestedWindowSize(arguments: ProcessInfo.processInfo.arguments)
    }
    
    /// The window size in these launch arguments.
    public static func requestedWindowSize(arguments: [String]) -> CGSize? {
        guard let index = arguments.firstIndex(of: windowSizeArgument), index + 1 < arguments.count else {
            return nil
        }
        
        let parts = arguments[index + 1].lowercased().split(separator: "x")
        
        guard parts.count == 2, let width = Double(parts[0]), let height = Double(parts[1]), width > 0, height > 0 else {
            return nil
        }
        
        return CGSize(width: width, height: height)
    }
    #endif
}
