import Foundation
import StagehandModel

/// One image Stagehand would upload: an export, in its set's order.
public struct DesiredScreenshot: Hashable, Sendable {
    public var fileName: String
    public var data: Data
    public var checksum: String
    
    public init(fileName: String, data: Data) {
        self.fileName = fileName
        self.data = data
        self.checksum = data.md5
    }
}

/// What uploading one locale's target would change. Building one is a dry run: nothing is sent.
public struct UploadSetPlan: Hashable, Sendable, Identifiable {
    public var locale: LocaleID
    public var target: DeviceTarget
    public var displayType: String
    
    /// `nil` when the version has no localization for the locale, which Stagehand doesn't create.
    public var localization: ASCLocalization?
    
    /// The custom product page the set uploads to, or `nil` for the product page.
    public var customProductPageID: String?
    
    /// `nil` when App Store Connect has no screenshot set for this display type yet.
    public var setID: String?
    public var uploads: [DesiredScreenshot]
    public var deletions: [ASCScreenshot]
    public var unchanged: [ASCScreenshot]
    
    /// The final order, as indexes into the desired screenshots.
    public var desired: [DesiredScreenshot]
    public var needsReorder: Bool
    
    public var id: String {
        "\(customProductPageID.map { "\($0)/" } ?? "")\(locale)/\(target.id)"
    }
    
    public var hasChanges: Bool {
        !uploads.isEmpty || !deletions.isEmpty || needsReorder
    }
    
    public var summary: String {
        var parts: [String] = []
        
        if !uploads.isEmpty { parts.append("upload \(uploads.count)") }
        if !deletions.isEmpty { parts.append("delete \(deletions.count)") }
        if !unchanged.isEmpty { parts.append("keep \(unchanged.count)") }
        if needsReorder { parts.append("reorder") }
        
        return parts.isEmpty ? "No changes" : parts.joined(separator: ", ").capitalizedFirst
    }
}

extension String {
    var capitalizedFirst: String {
        prefix(1).uppercased() + dropFirst()
    }
}

/// Compares an export with what's in App Store Connect.
public enum UploadPlanner {
    /// Keeps existing screenshots whose checksum matches an export, uploads the rest, deletes what's left over,
    /// and reorders when the final order differs from what's there, unless `keepsOrder` leaves App Store Connect's
    /// order (with new uploads at the end).
    public static func plan(
        locale: LocaleID,
        target: DeviceTarget,
        localization: ASCLocalization?,
        customProductPageID: String? = nil,
        setID: String?,
        desired: [DesiredScreenshot],
        existing: [ASCScreenshot],
        keepsOrder: Bool = false
    ) -> UploadSetPlan {
        var remaining = existing
        var unchanged: [ASCScreenshot] = []
        var uploads: [DesiredScreenshot] = []
        
        for screenshot in desired {
            if let index = remaining.firstIndex(where: { $0.checksum == screenshot.checksum }) {
                unchanged.append(remaining.remove(at: index))
            } else {
                uploads.append(screenshot)
            }
        }
        
        let keptOrder = existing.filter { kept in unchanged.contains(kept) }.map(\.id)
        let desiredOrder = unchanged.map(\.id)
        
        return UploadSetPlan(
            locale: locale,
            target: target,
            displayType: target.displayType,
            localization: localization,
            customProductPageID: customProductPageID,
            setID: setID,
            uploads: uploads,
            deletions: remaining,
            unchanged: unchanged,
            desired: desired,
            needsReorder: !keepsOrder && (!uploads.isEmpty || keptOrder != desiredOrder)
        )
    }
}
