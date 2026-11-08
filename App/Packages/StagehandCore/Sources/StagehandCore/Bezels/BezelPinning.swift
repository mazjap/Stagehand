import Foundation
import StagehandModel

/// Pins templates' bezels and embeds the pinned ones in a document.
///
/// A template keeps the bezel it was made with: new layouts pin the best bezel for their class, and so does a new
/// project for every layout still on Library Default. Pinned bezels are copied into the document, so it opens with
/// them even when the library doesn't have them.
public enum BezelPinning {
    /// The bezel a new layout on a class pins: the best match for the project's first export size in the class, or
    /// `nil` when the library has no bezel for it.
    public static func bestChoice(for device: DeviceClass, targets: [DeviceTarget.ID], catalog: BezelCatalog) -> BezelChoice? {
        let target = targets.compactMap(DeviceTable.standard.target(id:)).first { $0.deviceClass == device }
            ?? DeviceTable.standard.targets(in: device).first
        
        return catalog.bestBezel(for: device, aspectRatio: target?.aspectRatio).map { .pinned($0.id) }
    }
    
    /// Pins every device placement still on Library Default, for classes the library has a bezel for, then embeds.
    public static func pinLibraryDefaults(in contents: inout ProjectContents, catalog: BezelCatalog, imageData: (BezelID) -> Data?) {
        let targets = contents.project.targets
        
        for index in contents.project.style.templates.indices {
            for device in contents.project.style.templates[index].layouts.keys {
                guard var layout = contents.project.style.templates[index].layouts[device],
                      let choice = bestChoice(for: device, targets: targets, catalog: catalog) else {
                    continue
                }
                
                if layout.device.bezel == .matchTarget {
                    layout.device.bezel = choice
                }
                
                for (id, placement) in layout.extras {
                    if case var .device(extra) = placement, extra.bezel == .matchTarget {
                        extra.bezel = choice
                        layout.extras[id] = .device(extra)
                    }
                }
                
                contents.project.style.templates[index].layouts[device] = layout
            }
        }
        
        embed(in: &contents, catalog: catalog, imageData: imageData)
    }
    
    /// Copies every pinned bezel into the document, and drops copies nothing pins anymore.
    public static func embed(in contents: inout ProjectContents, catalog: BezelCatalog, imageData: (BezelID) -> Data?) {
        let pinned = contents.project.style.pinnedBezels
        contents.bezels = contents.bezels.filter { pinned.contains($0.key) }
        
        for id in pinned where contents.bezels[id] == nil {
            guard let info = catalog.bezels[id], let png = imageData(id) else {
                continue
            }
            
            contents.bezels[id] = EmbeddedBezel(info: info, png: png)
        }
    }
}
