import Foundation
import OSLog
import StagehandModel

/// Reads and writes the `.stagehand` package:
///
/// ```
/// TrekPoint.stagehand/
/// ├── project.json
/// ├── fonts/
/// ├── captures/
/// │   ├── index.json
/// │   └── <capture key>/<device class>/<locale>.png
/// ├── assets/
/// └── bezels/        the pinned bezels: <id>.png and <id>.json
/// ```
public enum ProjectPackage {
    public static let projectFile = "project.json"
    public static let fontsFolder = "fonts"
    public static let capturesFolder = "captures"
    public static let indexFile = "index.json"
    public static let assetsFolder = "assets"
    public static let bezelsFolder = "bezels"
    
    // MARK: - Reading
    
    public static func read(_ package: FileWrapper) throws(DocumentError) -> ProjectContents {
        let children = package.fileWrappers ?? [:]
        
        guard let projectData = children[projectFile]?.regularFileContents else {
            throw .missingFile(projectFile)
        }
        
        let project = try FormatMigration.decode(
            Project.self,
            from: projectData,
            fileName: projectFile,
            currentVersion: Project.currentFormatVersion,
            steps: FormatMigration.projectSteps
        )
        
        var captures = CaptureIndex()
        var captureFiles: [CaptureAddress: Data] = [:]
        
        if let folder = children[capturesFolder], let indexData = folder.fileWrappers?[indexFile]?.regularFileContents {
            do {
                captures = try FormatMigration.makeDecoder().decode(CaptureIndex.self, from: indexData)
            } catch {
                throw .corrupt("captures/\(indexFile)", reason: String(describing: error))
            }
            
            for (address, _) in captures.records {
                if let data = wrapper(at: address.relativePath, in: folder)?.regularFileContents {
                    captureFiles[address] = data
                } else {
                    Logger.documents.warning("Dropping \(address.relativePath, privacy: .public), whose file is missing")
                    captures.records[address] = nil
                }
            }
        }
        
        return ProjectContents(
            project: project,
            captures: captures,
            captureFiles: captureFiles,
            fonts: regularFiles(in: children[fontsFolder]),
            assets: regularFiles(in: children[assetsFolder]),
            bezels: readBezels(regularFiles(in: children[bezelsFolder]))
        )
    }
    
    /// Each `<id>.json` with its `<id>.png`. A bezel missing either file is skipped.
    static func readBezels(_ files: [String: Data]) -> [BezelID: EmbeddedBezel] {
        var bezels: [BezelID: EmbeddedBezel] = [:]
        let decoder = FormatMigration.makeDecoder()
        
        for (name, data) in files where name.hasSuffix(".json") {
            let id = String(name.dropLast(".json".count))
            
            guard let info = try? decoder.decode(BezelInfo.self, from: data), let png = files["\(id).png"] else {
                Logger.documents.warning("Skipping the embedded bezel \(id, privacy: .public)")
                continue
            }
            
            bezels[info.id] = EmbeddedBezel(info: info, png: png)
        }
        
        return bezels
    }
    
    static func bezelFiles(_ bezels: [BezelID: EmbeddedBezel]) throws -> [String: Data] {
        var files: [String: Data] = [:]
        let encoder = FormatMigration.makeEncoder()
        
        for (id, bezel) in bezels {
            files["\(id).json"] = try encoder.encode(bezel.info)
            files["\(id).png"] = bezel.png
        }
        
        return files
    }
    
    // MARK: - Writing
    
    /// The package for these contents, reusing unchanged capture files from the previous save.
    ///
    /// Captures are by far the largest files, so a capture whose revision matches the previous save's keeps its
    /// existing file wrapper instead of being rewritten.
    public static func write(_ contents: ProjectContents, previous: FileWrapper?) throws -> FileWrapper {
        let package = FileWrapper(directoryWithFileWrappers: [:])
        
        let projectWrapper = FileWrapper(regularFileWithContents: try FormatMigration.makeEncoder().encode(contents.project))
        projectWrapper.preferredFilename = projectFile
        package.addFileWrapper(projectWrapper)
        
        package.addFileWrapper(folder(named: fontsFolder, files: contents.fonts))
        package.addFileWrapper(folder(named: assetsFolder, files: contents.assets))
        
        if !contents.bezels.isEmpty {
            package.addFileWrapper(folder(named: bezelsFolder, files: try bezelFiles(contents.bezels)))
        }
        package.addFileWrapper(try capturesFolder(contents, previous: previous?.fileWrappers?[capturesFolder]))
        
        return package
    }
    
    private static func capturesFolder(_ contents: ProjectContents, previous: FileWrapper?) throws -> FileWrapper {
        let folder = FileWrapper(directoryWithFileWrappers: [:])
        folder.preferredFilename = capturesFolder
        
        let index = FileWrapper(regularFileWithContents: try FormatMigration.makeEncoder().encode(contents.captures))
        index.preferredFilename = indexFile
        folder.addFileWrapper(index)
        
        let previousIndex = previous?.fileWrappers?[indexFile]?.regularFileContents
            .flatMap { try? FormatMigration.makeDecoder().decode(CaptureIndex.self, from: $0) }
        
        // Group by key, then class, so the folder tree is built once.
        var keys: [String: FileWrapper] = [:]
        var classes: [String: FileWrapper] = [:]
        
        for (address, record) in contents.captures.records.sorted(by: { $0.key < $1.key }) {
            let fileName = "\(address.locale).png"
            let unchanged = previousIndex?.records[address]?.revision == record.revision
            let file: FileWrapper
            
            if unchanged, let existing = wrapper(at: address.relativePath, in: previous) {
                file = existing
            } else if let data = contents.captureFiles[address] {
                file = FileWrapper(regularFileWithContents: data)
            } else {
                continue
            }
            
            file.preferredFilename = fileName
            
            let keyFolder = keys[address.key] ?? {
                let created = FileWrapper(directoryWithFileWrappers: [:])
                created.preferredFilename = address.key
                folder.addFileWrapper(created)
                keys[address.key] = created
                return created
            }()
            
            let classPath = "\(address.key)/\(address.deviceClass.rawValue)"
            let classFolder = classes[classPath] ?? {
                let created = FileWrapper(directoryWithFileWrappers: [:])
                created.preferredFilename = address.deviceClass.rawValue
                keyFolder.addFileWrapper(created)
                classes[classPath] = created
                return created
            }()
            
            classFolder.addFileWrapper(file)
        }
        
        return folder
    }
    
    // MARK: - Helpers
    
    static func folder(named name: String, files: [String: Data]) -> FileWrapper {
        let folder = FileWrapper(directoryWithFileWrappers: [:])
        folder.preferredFilename = name
        
        for (fileName, data) in files {
            let file = FileWrapper(regularFileWithContents: data)
            file.preferredFilename = fileName
            folder.addFileWrapper(file)
        }
        
        return folder
    }
    
    static func regularFiles(in folder: FileWrapper?) -> [String: Data] {
        var files: [String: Data] = [:]
        
        for (name, child) in folder?.fileWrappers ?? [:] where child.isRegularFile && !name.hasPrefix(".") {
            files[name] = child.regularFileContents
        }
        
        return files
    }
    
    static func wrapper(at path: String, in root: FileWrapper?) -> FileWrapper? {
        var current = root
        
        for component in path.split(separator: "/") {
            current = current?.fileWrappers?[String(component)]
        }
        
        return current
    }
}
