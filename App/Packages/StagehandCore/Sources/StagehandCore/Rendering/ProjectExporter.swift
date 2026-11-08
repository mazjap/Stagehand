import CoreGraphics
import Foundation
import StagehandModel

/// One exported image.
public struct ExportItem: Hashable, Sendable {
    public var setID: ShotSet.ID
    public var slideID: Slide.ID
    public var target: DeviceTarget
    public var locale: LocaleID
    
    /// The slide's position among the lineup's slides on this device, from 1.
    public var number: Int
    public var slug: String
    
    /// A custom product page's folder, or `nil` for the main lineup.
    public var pageFolder: String?
    
    /// `<listing locale>/<target ID>/<NN>-<slide slug>.png`, inside `<page name>/` for a custom product page.
    public var relativePath: String {
        let path = String(format: "%@/%@/%02d-%@.png", locale, target.id, number, slug)
        return pageFolder.map { "\($0)/\(path)" } ?? path
    }
}

/// Works out what an export writes, and writes it.
public struct ProjectExporter {
    public init() {}
    
    // MARK: - Functions
    
    /// Every image to export: each listing locale, lineup, target and slide that's on the target's device.
    public func items(for project: Project, table: DeviceTable = .standard) -> [ExportItem] {
        var items: [ExportItem] = []
        
        for locale in project.listingLocales {
            for set in project.sets {
                let pageFolder = set.id == ShotSet.mainID ? nil : set.name.slugified
                
                for target in set.resolvedTargets(table: table) {
                    // NOTE: - Numbered per device, so a slide that's off for a device leaves no gap in its order.
                    for (index, slide) in project.slides(in: set, on: target.deviceClass).enumerated() {
                        items.append(ExportItem(
                            setID: set.id,
                            slideID: slide.id,
                            target: target,
                            locale: locale,
                            number: index + 1,
                            slug: slide.slug,
                            pageFolder: pageFolder
                        ))
                    }
                }
            }
        }
        
        return items
    }
    
    /// Renders each item with `render` and writes it under the folder, returning the files written.
    @MainActor
    public func export(
        _ items: [ExportItem],
        to folder: URL,
        fileManager: any FileManagerProvider,
        render: (ExportItem) throws(ExportError) -> Data
    ) throws(ExportError) -> [URL] {
        guard !items.isEmpty else {
            throw .nothingToExport
        }
        
        var written: [URL] = []
        
        for item in items {
            let data = try render(item)
            let url = folder.appending(path: item.relativePath)
            
            do {
                try fileManager.write(data, to: url)
            } catch {
                throw .writeFailed(item.relativePath, reason: error.localizedDescription)
            }
            
            written.append(url)
        }
        
        return written
    }
}
