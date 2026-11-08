import Foundation

/// How a capture's two test attachments are named, so the kit and Stagehand's importer agree.
///
/// The image is `stagehand.<capture ID>.<name>` and the metadata is `stagehand.<capture ID>.meta`.
/// The capture ID ties the pair together, and the name stays readable in Xcode's test report.
public enum ShotAttachment {
    public static let prefix = "stagehand."
    public static let metadataSuffix = "meta"
    
    /// The image attachment's name.
    public static func imageName(captureID: UUID, name: String) -> String {
        prefix + captureID.uuidString + "." + name
    }
    
    /// The metadata attachment's name.
    public static func metadataName(captureID: UUID) -> String {
        prefix + captureID.uuidString + "." + metadataSuffix
    }
    
    /// Splits an attachment name into its capture ID and the rest (`meta`, or the capture's name).
    ///
    /// Xcode may add a suffix when exporting (like `_0_<UUID>.png`), so callers strip file extensions
    /// and export suffixes first, or match on ``captureID(in:)`` alone.
    public static func parse(_ name: String) -> (captureID: UUID, suffix: String)? {
        guard name.hasPrefix(prefix) else {
            return nil
        }
        
        let rest = name.dropFirst(prefix.count)
        
        guard let dot = rest.firstIndex(of: "."), let id = UUID(uuidString: String(rest[..<dot])) else {
            return nil
        }
        
        return (id, String(rest[rest.index(after: dot)...]))
    }
    
    /// The capture ID in an attachment name, if it's one of the kit's.
    public static func captureID(in name: String) -> UUID? {
        parse(name)?.captureID
    }
}
