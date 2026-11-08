import Foundation
import StagehandModel

/// A contact sheet cell: one slide on one target.
public struct CellID: Hashable, Sendable {
    public var setID: ShotSet.ID
    public var slideID: Slide.ID
    public var targetID: DeviceTarget.ID
    
    public init(setID: ShotSet.ID, slideID: Slide.ID, targetID: DeviceTarget.ID) {
        self.setID = setID
        self.slideID = slideID
        self.targetID = targetID
    }
}

/// Something the issues list shows.
public struct Issue: Hashable, Sendable, Identifiable {
    public enum Kind: Hashable, Sendable {
        case cell(SceneFlag)
        case tooManySlides(count: Int)
        case watchSizesDiffer(key: String)
        case requiredTargetMissing(DeviceTarget.ID)
        case unknownCaptureSize(String, width: Int, height: Int)
        case noLayout(DeviceClass)
        case templateMissingLayout(TemplateID, DeviceClass)
        case newerBezel(BezelID, newer: BezelID)
        case importRefused(String)
        case emptySet
    }
    
    public var kind: Kind
    public var severity: SceneFlag.Severity
    public var message: String
    public var setID: ShotSet.ID?
    public var cell: CellID?
    
    public init(kind: Kind, severity: SceneFlag.Severity, message: String, setID: ShotSet.ID? = nil, cell: CellID? = nil) {
        self.kind = kind
        self.severity = severity
        self.message = message
        self.setID = setID
        self.cell = cell
    }
    
    public var id: Int {
        hashValue
    }
}

/// The project-level checks, beyond each cell's flags.
public enum ProjectValidator {
    public static func setIssues(project: Project, captures: CaptureIndex, table: DeviceTable = .standard) -> [Issue] {
        var issues: [Issue] = []
        
        for set in project.sets {
            if set.slideIDs.isEmpty {
                issues.append(Issue(kind: .emptySet, severity: .warning, message: "\(set.name) has no slides.", setID: set.id))
            }
            
            // App Store Connect's limit is per device, so a slide that's off for a device doesn't count there.
            for device in set.devices {
                let count = project.slides(in: set, on: device).count
                
                if count > ShotSet.maximumSlides {
                    issues.append(Issue(
                        kind: .tooManySlides(count: count),
                        severity: .error,
                        message: "\(set.name) has \(count) slides on \(device.displayName). App Store Connect takes at most \(ShotSet.maximumSlides).",
                        setID: set.id
                    ))
                }
            }
        }
        
        for device in project.devices {
            if project.style.templates(for: device).isEmpty {
                issues.append(Issue(
                    kind: .noLayout(device),
                    severity: .error,
                    message: "The project includes \(device.displayName), but no template has a layout for it.",
                    setID: ShotSet.mainID
                ))
            }
            
            // A template a slide uses on this device, but without a layout for it.
            let used = Set(project.slides.values.filter { $0.isOn(device) }.map { $0.template[device] })
            
            for template in project.style.templates where used.contains(template.id) && template.layouts[device] == nil {
                issues.append(Issue(
                    kind: .templateMissingLayout(template.id, device),
                    severity: .warning,
                    message: "\(template.name) has no \(device.displayName) layout yet, so its slides use another template there.",
                    setID: ShotSet.mainID
                ))
            }
            
            let required = table.targets(in: device).filter(\.isRequired)
            
            for target in required where !project.targets.contains(target.id) {
                issues.append(Issue(
                    kind: .requiredTargetMissing(target.id),
                    severity: .warning,
                    message: "The project doesn't export \(target.name), which App Store Connect requires for \(device.displayName).",
                    setID: ShotSet.mainID
                ))
            }
        }
        
        for record in captures.records.values.sorted(by: { $0.address < $1.address }) {
            if table.classify(width: record.pixelWidth, height: record.pixelHeight) == nil {
                issues.append(Issue(
                    kind: .unknownCaptureSize(record.address.relativePath, width: record.pixelWidth, height: record.pixelHeight),
                    severity: .error,
                    message: "The \(record.address.key) capture is \(record.pixelWidth) × \(record.pixelHeight), which isn't in devices.json."
                ))
            }
        }
        
        // Apple Watch screenshots have to be the same size in every localization.
        let watch = captures.records.values.filter { $0.address.deviceClass == .watch }
        
        for (key, records) in Dictionary(grouping: watch, by: \.address.key).sorted(by: { $0.key < $1.key }) {
            let sizes = Set(records.map { "\($0.pixelWidth)x\($0.pixelHeight)" })
            
            if sizes.count > 1 {
                issues.append(Issue(
                    kind: .watchSizesDiffer(key: key),
                    severity: .error,
                    message: "The \(key) Apple Watch captures differ in size between localizations (\(sizes.sorted().joined(separator: ", ")))."
                ))
            }
        }
        
        return issues
    }
}
