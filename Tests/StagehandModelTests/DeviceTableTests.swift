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
        #expect(table.classify(width: 1323, height: 2868) == nil)
    }
    
    /// Regression test: the iPhone Duo's iOS 27.2 simulator takes inner display screenshots at 2006 × 2852, one pixel
    /// short of the 2007 × 2853 App Store Connect asks for, so every capture failed the size check.
    @Test func aSizeWithinTheToleranceClassifiesAsItsTarget() throws {
        let inner = try #require(table.classify(width: 2006, height: 2852))
        #expect(inner.deviceClass == .duoInner)
        #expect(inner.size.width == 2007 && inner.size.height == 2853)
        #expect(inner.isRotated == false)
        
        #expect(table.classify(width: 2852, height: 2006)?.isRotated == true)
        #expect(table.classify(width: 2009, height: 2851)?.deviceClass == .duoInner)
        #expect(table.classify(width: 2010, height: 2853) == nil)
        #expect(table.classify(width: 2007, height: 2850) == nil)
    }
    
    /// A capture can only match one size, so two sizes can't be within twice the tolerance of each other.
    @Test func noCaptureCanMatchTwoSizes() {
        let sizes = table.targets.flatMap { target in target.sizes.map { (target: target.id, width: $0.width, height: $0.height) } }
        let reach = DeviceTable.sizeTolerance * 2
        
        for (index, first) in sizes.enumerated() {
            for second in sizes[(index + 1)...] {
                let isNear = abs(first.width - second.width) <= reach && abs(first.height - second.height) <= reach
                let isNearRotated = abs(first.width - second.height) <= reach && abs(first.height - second.width) <= reach
                #expect(!isNear && !isNearRotated, "\(first) and \(second) are too close")
            }
        }
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
