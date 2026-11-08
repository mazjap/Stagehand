import CoreGraphics
import Foundation
import StagehandModel

/// `style.json`: the template set, with the preview devices and slides it's designed against.
public struct StyleFile: Codable, Hashable, Sendable {
    public static let currentFormatVersion = Project.currentFormatVersion
    
    public var formatVersion: Int
    public var style: Style
    
    /// Format 2's preview set, as devices and its targets.
    public var previewDevices: [DeviceClass]
    public var previewTargets: [DeviceTarget.ID]
    
    /// In order.
    public var previewSlides: [Slide]
    public var sourceLocale: LocaleID
    
    public init(
        formatVersion: Int = StyleFile.currentFormatVersion,
        style: Style,
        previewDevices: [DeviceClass],
        previewTargets: [DeviceTarget.ID]? = nil,
        previewSlides: [Slide],
        sourceLocale: LocaleID = "en-US"
    ) {
        self.formatVersion = formatVersion
        self.style = style
        self.previewDevices = previewDevices
        self.previewTargets = previewTargets ?? ShotSet.defaultTargets(for: previewDevices)
        self.previewSlides = previewSlides
        self.sourceLocale = sourceLocale
    }
}

/// Reads and writes the `.stagehandstyle` package:
///
/// ```
/// Tilted Hero.stagehandstyle/
/// ├── style.json
/// ├── fonts/
/// ├── bezels/        the pinned bezels, as in a project
/// └── previews/      placeholder screens, laid out like a project's captures
/// ```
///
/// A style opens as ``ProjectContents`` whose devices and slides are the previews, so the same editor edits it.
public enum StylePackage {
    public static let styleFile = "style.json"
    public static let previewsFolder = "previews"
    
    /// The preview slides' capture key.
    public static let previewKey = "preview"
    
    // MARK: - Reading
    
    public static func read(files: [String: Data]) throws(DocumentError) -> ProjectContents {
        guard let data = files[styleFile] else {
            throw .missingFile(styleFile)
        }
        
        let file = try FormatMigration.decode(StyleFile.self, from: data, fileName: styleFile, currentVersion: StyleFile.currentFormatVersion, steps: styleSteps)
        var captures = CaptureIndex()
        var captureFiles: [CaptureAddress: Data] = [:]
        
        if let indexData = files["\(previewsFolder)/\(ProjectPackage.indexFile)"] {
            do {
                captures = try FormatMigration.makeDecoder().decode(CaptureIndex.self, from: indexData)
            } catch {
                throw .corrupt("previews/index.json", reason: String(describing: error))
            }
            
            for address in captures.records.keys {
                if let png = files["\(previewsFolder)/\(address.relativePath)"] {
                    captureFiles[address] = png
                } else {
                    captures.records[address] = nil
                }
            }
        }
        
        let project = Project(
            name: file.style.name,
            style: file.style,
            devices: file.previewDevices,
            targets: file.previewTargets,
            slides: Dictionary(uniqueKeysWithValues: file.previewSlides.map { ($0.id, $0) }),
            slideOrder: file.previewSlides.map(\.id),
            sourceLocale: file.sourceLocale,
            listingLocales: [file.sourceLocale],
            appLocales: [file.sourceLocale]
        )
        
        return ProjectContents(
            project: project,
            captures: captures,
            captureFiles: captureFiles,
            fonts: subfolder("fonts", in: files),
            bezels: ProjectPackage.readBezels(subfolder(ProjectPackage.bezelsFolder, in: files))
        )
    }
    
    // MARK: - Writing
    
    public static func files(_ contents: ProjectContents) throws -> [String: Data] {
        let project = contents.project
        var style = project.style
        style.name = project.name
        let file = StyleFile(
            style: style,
            previewDevices: project.devices,
            previewTargets: project.targets,
            previewSlides: project.slides(in: project.mainLineup),
            sourceLocale: project.sourceLocale
        )
        let encoder = FormatMigration.makeEncoder()
        var files: [String: Data] = [styleFile: try encoder.encode(file)]
        
        files["\(previewsFolder)/\(ProjectPackage.indexFile)"] = try encoder.encode(contents.captures)
        
        for (address, data) in contents.captureFiles {
            files["\(previewsFolder)/\(address.relativePath)"] = data
        }
        
        for (name, data) in contents.fonts {
            files["fonts/\(name)"] = data
        }
        
        for (name, data) in try ProjectPackage.bezelFiles(contents.bezels) {
            files["\(ProjectPackage.bezelsFolder)/\(name)"] = data
        }
        
        return files
    }
    
    // MARK: - New Styles
    
    /// A new style: the fixture style renamed, three preview slides, and placeholder screens for its preview set.
    public static func newStyle(named name: String = "Untitled Style", from style: Style? = nil, now: Date? = nil) -> ProjectContents {
        // Whole seconds, since dates are saved as ISO 8601 and would otherwise change on the first save.
        let now = now ?? Date(timeIntervalSince1970: Date().timeIntervalSince1970.rounded(.down))
        var style = style ?? Style.fixture(id: UUID())
        style.name = name
        
        let slides = ["Show it off", "Bring it along", "Make it yours"].enumerated().map { index, headline in
            Slide(
                title: "Preview \(index + 1)",
                primary: Varying(["en-US": headline]),
                secondary: Varying(["en-US": "A line about what this screen shows"]),
                captureKey: Varying(previewKey),
                template: Varying(style.templates.indices.contains(index) ? style.templates[index].id : style.templates.first?.id ?? .straight)
            )
        }
        
        let devices = style.deviceClasses.filter { $0 != .mac }
        var contents = ProjectContents(project: Project(
            name: name,
            style: style,
            devices: devices.isEmpty ? [.phone] : devices,
            slides: Dictionary(uniqueKeysWithValues: slides.map { ($0.id, $0) }),
            slideOrder: slides.map(\.id)
        ))
        
        for device in DeviceClass.allCases {
            guard let target = DeviceTable.standard.targets(in: device).first, let png = PlaceholderScreen.png(for: target) else {
                continue
            }
            
            let address = CaptureAddress(key: previewKey, deviceClass: device, locale: "en-US")
            contents.captures.records[address] = CaptureRecord(
                address: address,
                pixelWidth: target.exportSize.width,
                pixelHeight: target.exportSize.height,
                targetID: target.id,
                source: .dropped,
                importedAt: now
            )
            contents.captureFiles[address] = png
        }
        
        return contents
    }
    
    // MARK: - Helpers
    
    static let styleSteps: [Int: FormatMigration.Step] = [
        1: { file in try StyleMigrations.anchorPlacements(inStyleAt: "style", of: &file) },
        2: { file in
            let set = file["previewSet"] as? [String: Any] ?? [:]
            let devices = set["devices"] as? [String] ?? [DeviceClass.phone.rawValue]
            let layouts = (file["style"] as? [String: Any]).map { StyleMigrations.layouts(of: $0, materializing: devices) } ?? [:]
            StyleMigrations.templates(inStyleAt: "style", of: &file, materializing: devices)
            file["previewDevices"] = devices
            file["previewTargets"] = set["targets"] as? [String] ?? []
            file["previewSet"] = nil
            
            // Slides in the order the preview set had them.
            let order = set["slideIDs"] as? [String] ?? []
            var slides = file["previewSlides"] as? [[String: Any]] ?? []
            slides.sort { (order.firstIndex(of: $0["id"] as? String ?? "") ?? .max) < (order.firstIndex(of: $1["id"] as? String ?? "") ?? .max) }
            
            for index in slides.indices {
                StyleMigrations.slide(&slides[index], layouts: layouts)
            }
            
            file["previewSlides"] = slides
        },
    ]
    
    static func subfolder(_ name: String, in files: [String: Data]) -> [String: Data] {
        var result: [String: Data] = [:]
        
        for (path, data) in files where path.hasPrefix(name + "/") {
            let rest = String(path.dropFirst(name.count + 1))
            
            if !rest.contains("/") {
                result[rest] = data
            }
        }
        
        return result
    }
}

/// A neutral screen for a style's preview slides, so a style can be judged with no app attached.
enum PlaceholderScreen {
    static func png(for target: DeviceTarget) -> Data? {
        let width = target.exportSize.width
        let height = target.exportSize.height
        
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else {
            return nil
        }
        
        let unit = Double(width) / 12
        context.setFillColor(CGColor(srgbRed: 0.93, green: 0.94, blue: 0.96, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        
        // A header bar, a hero block and a few rows, like an app screen. Core Graphics' origin is the bottom left.
        context.setFillColor(CGColor(srgbRed: 0.78, green: 0.81, blue: 0.86, alpha: 1))
        context.fill(CGRect(x: unit, y: Double(height) - unit * 2.4, width: unit * 5, height: unit * 0.7))
        context.fill(CGRect(x: unit, y: Double(height) - unit * 8, width: Double(width) - unit * 2, height: unit * 4.6))
        
        context.setFillColor(CGColor(srgbRed: 0.85, green: 0.87, blue: 0.9, alpha: 1))
        
        for row in 0..<6 {
            let y = Double(height) - unit * (9.6 + Double(row) * 1.6)
            
            guard y > unit else {
                break
            }
            
            context.fill(CGRect(x: unit, y: y, width: Double(width) - unit * 2, height: unit))
        }
        
        return context.makeImage()?.pngData()
    }
}
