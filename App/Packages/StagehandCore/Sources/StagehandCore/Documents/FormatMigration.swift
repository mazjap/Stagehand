import Foundation
import StagehandModel

/// Reads a document's `formatVersion` and migrates older JSON forward before decoding.
///
/// > Warning: Never rename a Codable key or an enum case's raw value in place. Bump the format version and add a
/// > migration here instead.
public enum FormatMigration {
    private struct Header: Decodable {
        var formatVersion: Int
    }
    
    /// A migration from one format version to the next, on the document's JSON object.
    public typealias Step = @Sendable (inout [String: Any]) throws -> Void
    
    /// Migrations by the version they migrate from.
    static let projectSteps: [Int: Step] = [
        1: { project in
            try StyleMigrations.anchorPlacements(inStyleAt: "style", of: &project)
            
            if var basedOn = project["basedOn"] as? [String: Any] {
                try StyleMigrations.anchorPlacements(inStyleAt: "snapshot", of: &basedOn)
                project["basedOn"] = basedOn
            }
        },
        2: { project in
            ProjectMigrations.lineups(in: &project)
            let devices = project["devices"] as? [String] ?? []
            let layouts = (project["style"] as? [String: Any]).map { StyleMigrations.layouts(of: $0, materializing: devices) } ?? [:]
            StyleMigrations.templates(inStyleAt: "style", of: &project, materializing: devices)
            
            if var basedOn = project["basedOn"] as? [String: Any] {
                StyleMigrations.templates(inStyleAt: "snapshot", of: &basedOn, materializing: devices)
                project["basedOn"] = basedOn
            }
            
            if var slides = project["slides"] as? [String: Any] {
                for (id, slide) in slides {
                    if var slide = slide as? [String: Any] {
                        StyleMigrations.slide(&slide, layouts: layouts)
                        slides[id] = slide
                    }
                }
                
                project["slides"] = slides
            }
        },
    ]
    
    /// Decodes a document's JSON, refusing a newer format and migrating an older one.
    public static func decode<T: Decodable>(
        _ type: T.Type,
        from data: Data,
        fileName: String,
        currentVersion: Int,
        steps: [Int: Step] = [:]
    ) throws(DocumentError) -> T {
        let version: Int
        
        do {
            version = try JSONDecoder().decode(Header.self, from: data).formatVersion
        } catch {
            throw .corrupt(fileName, reason: "it has no format version")
        }
        
        if version > currentVersion {
            throw .newerFormat(found: version, supported: currentVersion)
        }
        
        var migrated = data
        
        if version < currentVersion {
            do {
                guard var object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    throw DocumentError.corrupt(fileName, reason: "it isn't a JSON object")
                }
                
                for from in version..<currentVersion {
                    try steps[from]?(&object)
                    object["formatVersion"] = from + 1
                }
                
                migrated = try JSONSerialization.data(withJSONObject: object)
            } catch let error as DocumentError {
                throw error
            } catch {
                throw .corrupt(fileName, reason: error.localizedDescription)
            }
        }
        
        do {
            return try makeDecoder().decode(T.self, from: migrated)
        } catch {
            throw .corrupt(fileName, reason: String(describing: error))
        }
    }
    
    public static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
    
    public static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

/// Format 2 to 3's project changes: sets become the project's devices, one order and custom product pages.
enum ProjectMigrations {
    /// Every set that isn't for a custom product page adds its devices, targets and slides (in order) to the project.
    /// A set for a custom product page becomes a ``ProductPage``. A slide is off for each device no set it's in has.
    static func lineups(in project: inout [String: Any]) {
        let sets = project["sets"] as? [[String: Any]] ?? []
        let pageSets = sets.filter { ($0["customProductPageID"] as? String).map { !$0.isEmpty } ?? false }
        let mainSets = sets.filter { set in !pageSets.contains { $0["id"] as? String == set["id"] as? String } }
        let deviceSource = mainSets.isEmpty ? sets : mainSets
        
        var devices: [String] = []
        var targets: [String] = []
        var order: [String] = []
        
        for set in deviceSource {
            for device in set["devices"] as? [String] ?? [] where !devices.contains(device) {
                devices.append(device)
            }
        }
        
        for set in sets {
            for target in set["targets"] as? [String] ?? [] where !targets.contains(target) {
                targets.append(target)
            }
        }
        
        for set in mainSets {
            for id in set["slideIDs"] as? [String] ?? [] where !order.contains(id) {
                order.append(id)
            }
        }
        
        if devices.isEmpty {
            devices = [DeviceClass.phone.rawValue]
        }
        
        project["devices"] = devices
        project["targets"] = targets
        project["slideOrder"] = order
        project["productPages"] = pageSets.map { set in
            [
                "id": set["id"] as? String ?? UUID().uuidString,
                "name": set["name"] as? String ?? "Custom Product Page",
                "pageID": set["customProductPageID"] as? String ?? "",
                "slideIDs": set["slideIDs"] as? [String] ?? [],
            ] as [String: Any]
        }
        project["sets"] = nil
        
        guard var slides = project["slides"] as? [String: Any] else {
            return
        }
        
        for (key, value) in slides {
            guard var slide = value as? [String: Any] else {
                continue
            }
            
            let id = slide["id"] as? String ?? key
            let containing = sets.filter { ($0["slideIDs"] as? [String] ?? []).contains(id) }
            
            // A draft (in no set) stays on every device.
            guard !containing.isEmpty else {
                continue
            }
            
            let on = Set(containing.flatMap { $0["devices"] as? [String] ?? [] })
            let excluded = DeviceClass.allCases.map(\.rawValue).filter { devices.contains($0) && !on.contains($0) }
            
            if !excluded.isEmpty {
                slide["excludedDevices"] = excluded
                slides[key] = slide
            }
        }
        
        project["slides"] = slides
    }
}

/// Migrations of a style's JSON, shared by projects and style documents.
enum StyleMigrations {
    /// A format 2 style's layouts by class and then variant, as format 3 template layouts. Classes in `materializing`
    /// that had no layout get a copy of the one they borrowed through the fallback chain.
    static func layouts(of style: [String: Any], materializing devices: [String]) -> [String: [String: [String: Any]]] {
        let old = style["layouts"] as? [String: Any] ?? [:]
        var result: [String: [String: [String: Any]]] = [:]
        
        for (device, value) in old {
            guard let layout = value as? [String: Any] else {
                continue
            }
            
            var byVariant: [String: [String: Any]] = [:]
            
            for (variant, placement) in layout["variants"] as? [String: Any] ?? [:] {
                guard var device = placement as? [String: Any] else {
                    continue
                }
                
                let primary = device["primary"] ?? layout["primary"]
                let secondary = device["secondary"] ?? layout["secondary"]
                device["primary"] = nil
                device["secondary"] = nil
                byVariant[variant] = [
                    "primary": primary ?? [:],
                    "secondary": secondary ?? [:],
                    "device": device,
                    "hiddenElements": [String](),
                    "extras": [String: Any](),
                ]
            }
            
            result[device] = byVariant
        }
        
        for device in devices where result[device] == nil {
            guard let deviceClass = DeviceClass(rawValue: device) else {
                continue
            }
            
            if let source = deviceClass.layoutFallbackChain.dropFirst().first(where: { result[$0.rawValue] != nil }) {
                result[device] = result[source.rawValue]
            }
        }
        
        return result
    }
    
    /// Format 2 to 3: each variant becomes a template with that variant's placement on every class that had it.
    static func templates(inStyleAt key: String, of object: inout [String: Any], materializing devices: [String]) {
        guard var style = object[key] as? [String: Any] else {
            return
        }
        
        let layouts = layouts(of: style, materializing: devices)
        let known = ["straight", "tilted", "zoomed"]
        let variants = Set(layouts.values.flatMap(\.keys))
        let order = known.filter(variants.contains) + variants.subtracting(known).sorted()
        var templates: [String: Any] = [:]
        
        for variant in order {
            var templateLayouts: [String: Any] = [:]
            
            for (device, byVariant) in layouts {
                if let layout = byVariant[variant] {
                    templateLayouts[device] = layout
                }
            }
            
            templates[variant] = [
                "id": variant,
                "name": variant.prefix(1).uppercased() + variant.dropFirst(),
                "elements": [Any](),
                "layouts": templateLayouts,
            ] as [String: Any]
        }
        
        style["layouts"] = nil
        style["templates"] = templates
        style["templateOrder"] = order
        object[key] = style
    }
    
    /// Format 2 to 3: a slide's variant becomes its template, and each class's nudge becomes a detached device
    /// placement: the variant's placement (falling back to straight, as format 2 drew it) with the nudge applied.
    static func slide(_ slide: inout [String: Any], layouts: [String: [String: [String: Any]]]) {
        let variant = slide["variant"] as? [String: Any] ?? ["base": "straight"]
        slide["template"] = variant
        slide["variant"] = nil
        
        let nudges = slide["nudges"] as? [String: Any] ?? [:]
        slide["nudges"] = nil
        var detachments: [String: Any] = [:]
        
        for (device, value) in nudges {
            guard let nudge = value as? [String: Any] else {
                continue
            }
            
            let overrides = variant["overrides"] as? [String: Any] ?? [:]
            let requested = overrides[device] as? String ?? variant["base"] as? String ?? "straight"
            let byVariant = layouts[device] ?? [:]
            
            guard var placement = (byVariant[requested] ?? byVariant["straight"])?["device"] as? [String: Any] else {
                continue
            }
            
            let position = placement["position"] as? [String: Any] ?? [:]
            placement["position"] = [
                "x": (position["x"] as? Double ?? 0.5) + (nudge["dx"] as? Double ?? 0),
                "y": (position["y"] as? Double ?? 0.5) + (nudge["dy"] as? Double ?? 0),
            ]
            placement["width"] = (placement["width"] as? Double ?? 0.78) * (nudge["scale"] as? Double ?? 1)
            placement["rotation"] = (placement["rotation"] as? Double ?? 0) + (nudge["rotation"] as? Double ?? 0)
            detachments[device] = ["device": placement]
        }
        
        if !detachments.isEmpty {
            slide["detachments"] = detachments
        }
    }
    
    /// Format 1 to 2: text boxes become an anchored position and a width (their height now follows the font size),
    /// devices are placed by an anchor instead of their center, and the glow is a blur of the device's shape.
    static func anchorPlacements(inStyleAt key: String, of object: inout [String: Any]) throws {
        guard var style = object[key] as? [String: Any] else {
            return
        }
        
        if var layouts = style["layouts"] as? [String: Any] {
            for (device, value) in layouts {
                guard var layout = value as? [String: Any] else {
                    continue
                }
                
                for role in ["primary", "secondary"] {
                    layout[role] = (layout[role] as? [String: Any]).map(textPlacement)
                }
                
                if var variants = layout["variants"] as? [String: Any] {
                    for (variant, placement) in variants {
                        if let placement = placement as? [String: Any] {
                            variants[variant] = devicePlacement(placement)
                        }
                    }
                    
                    layout["variants"] = variants
                }
                
                layouts[device] = layout
            }
            
            style["layouts"] = layouts
        }
        
        object[key] = style
    }
    
    /// Keeps the box's top, middle or bottom (whichever its text was aligned to) where it was.
    private static func textPlacement(_ old: [String: Any]) -> [String: Any] {
        var new = old
        let frame = old["frame"] as? [String: Any] ?? [:]
        let x = frame["x"] as? Double ?? 0
        let y = frame["y"] as? Double ?? 0
        let width = frame["width"] as? Double ?? 0.8
        let height = frame["height"] as? Double ?? 0
        let horizontal = old["alignment"] as? String ?? "center"
        let vertical = old["verticalAlignment"] as? String ?? "top"
        
        let anchorX = switch horizontal {
        case "leading": 0.0
        case "trailing": 1.0
        default: 0.5
        }
        
        let anchorY = switch vertical {
        case "center": 0.5
        case "bottom": 1.0
        default: 0.0
        }
        
        let anchor = BoxAnchor.allCases.first { $0.unit.x == anchorX && $0.unit.y == anchorY } ?? .top
        new["frame"] = nil
        new["anchor"] = anchor.rawValue
        new["width"] = width
        new["position"] = ["x": x + anchorX * width, "y": y + anchorY * height]
        return new
    }
    
    private static func devicePlacement(_ old: [String: Any]) -> [String: Any] {
        var new = old
        new["position"] = old["center"]
        new["center"] = nil
        new["anchor"] = BoxAnchor.center.rawValue
        
        if var glow = old["glow"] as? [String: Any] {
            glow["radius"] = nil
            glow["blur"] = 0.06
            glow["spread"] = 1.0
            new["glow"] = glow
        }
        
        for role in ["primary", "secondary"] {
            new[role] = (old[role] as? [String: Any]).map(textPlacement)
        }
        
        return new
    }
}
