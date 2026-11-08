import Foundation
import StagehandModel
import Testing

@Suite struct DeviceTableTests {
    private let table = DeviceTable.standard
    
    @Test func noSizeIsInTwoTargets() {
        var seen: [String: String] = [:]
        
        for target in table.targets {
            for size in target.sizes {
                let key = "\(min(size.width, size.height))x\(max(size.width, size.height))"
                #expect(seen[key] == nil, "\(key) is in both \(seen[key] ?? "") and \(target.id)")
                seen[key] = target.id
            }
        }
    }
    
    @Test func everyDeviceClassHasATarget() {
        for deviceClass in DeviceClass.allCases {
            #expect(!table.targets(in: deviceClass).isEmpty, "\(deviceClass) has no target")
        }
    }
    
    @Test func targetIDsAreUnique() {
        let ids = table.targets.map(\.id)
        #expect(Set(ids).count == ids.count)
    }
    
    @Test func everySizeClassifiesToItsTarget() {
        for target in table.targets {
            for size in target.sizes {
                let classification = table.classify(width: size.width, height: size.height)
                #expect(classification?.target.id == target.id)
                #expect(classification?.isRotated == false)
            }
        }
    }
    
    @Test func rotatedSizesClassifyToTheSameTarget() {
        let classification = table.classify(width: 2868, height: 1320)
        #expect(classification?.target.id == "iphone-dynamic-island-large")
        #expect(classification?.isRotated == true)
    }
    
    @Test func anUnknownSizeClassifiesToNothing() {
        #expect(table.classify(width: 1000, height: 1000) == nil)
        #expect(table.classify(width: 1321, height: 2868) == nil)
    }
    
    @Test func theDuoDisplaysAreToldApartBySize() {
        #expect(table.classify(width: 1398, height: 2034)?.deviceClass == .duoOuter)
        #expect(table.classify(width: 2007, height: 2853)?.deviceClass == .duoInner)
    }
    
    @Test func exportSizeIsTheLargest() {
        for target in table.targets {
            let largest = target.sizes.max { $0.width * $0.height < $1.width * $1.height }
            #expect(target.exportSize == largest)
        }
    }
    
    @Test func watchSizesCarryTheirOwnDisplayTypes() throws {
        let watch = try #require(table.target(id: "watch"))
        let series3 = try #require(watch.sizes.first { $0.width == 312 })
        #expect(watch.displayType(for: series3) == "APP_WATCH_SERIES_3")
        #expect(watch.displayType(for: watch.sizes[0]) == "APP_WATCH_ULTRA")
    }
    
    @Test func macIsLandscape() throws {
        let mac = try #require(table.target(id: "mac"))
        #expect(mac.orientation == .landscape)
        #expect(mac.exportSize.width == 2880 && mac.exportSize.height == 1800)
    }
}
