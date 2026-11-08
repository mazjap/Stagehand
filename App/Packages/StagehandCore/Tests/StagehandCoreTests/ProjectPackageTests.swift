import Foundation
@testable import StagehandCore
import StagehandModel
import Testing

@Suite struct ProjectPackageTests {
    private func contents() -> ProjectContents {
        let address = CaptureAddress(key: "read-the-land", deviceClass: .phone, locale: "en-US")
        let png = TestImages.solid(width: 1320, height: 2868).pngData()!
        let record = CaptureRecord(address: address, pixelWidth: 1320, pixelHeight: 2868, targetID: "iphone-dynamic-island-large", source: .dropped, importedAt: .sampleDate)
        
        return ProjectContents(
            project: .fixture(),
            captures: CaptureIndex(records: [address: record]),
            captureFiles: [address: png],
            fonts: ["PressStart2P-Regular.ttf": TestResources.data("PressStart2P-Regular.ttf")],
            assets: ["notes.txt": Data("hello".utf8)]
        )
    }
    
    @Test func aProjectRoundTripsThroughAPackage() throws {
        let original = contents()
        let wrapper = try ProjectPackage.write(original, previous: nil)
        let read = try ProjectPackage.read(wrapper)
        #expect(read == original)
    }
    
    @Test func aProjectRoundTripsThroughDisk() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "Package-\(UUID().uuidString).stagehand")
        defer { try? FileManager.default.removeItem(at: url) }
        
        let original = contents()
        try ProjectPackage.write(original, previous: nil).write(to: url, options: .atomic, originalContentsURL: nil)
        
        #expect(FileManager.default.fileExists(atPath: url.appending(path: "captures/read-the-land/phone/en-US.png").path(percentEncoded: false)))
        #expect(FileManager.default.fileExists(atPath: url.appending(path: "fonts/PressStart2P-Regular.ttf").path(percentEncoded: false)))
        
        let read = try ProjectPackage.read(FileWrapper(url: url))
        #expect(read == original)
    }
    
    @Test func aNewerFormatIsRefused() throws {
        var project = Project.fixture()
        project.formatVersion = Project.currentFormatVersion + 1
        let data = try FormatMigration.makeEncoder().encode(project)
        let wrapper = FileWrapper(directoryWithFileWrappers: ["project.json": FileWrapper(regularFileWithContents: data)])
        
        #expect(throws: DocumentError.newerFormat(found: Project.currentFormatVersion + 1, supported: Project.currentFormatVersion)) {
            try ProjectPackage.read(wrapper)
        }
    }
    
    @Test func anOlderFormatRunsItsMigration() throws {
        struct Versioned: Codable { var formatVersion: Int; var name: String }
        let data = Data(#"{"formatVersion":1,"title":"Old"}"#.utf8)
        
        let decoded = try FormatMigration.decode(Versioned.self, from: data, fileName: "x.json", currentVersion: 2, steps: [
            1: { object in object["name"] = object.removeValue(forKey: "title") },
        ])
        
        #expect(decoded.formatVersion == 2)
        #expect(decoded.name == "Old")
    }
    
    @Test func aMissingProjectFileIsAnError() {
        #expect(throws: DocumentError.missingFile("project.json")) {
            try ProjectPackage.read(FileWrapper(directoryWithFileWrappers: [:]))
        }
    }
    
    @Test func anUnchangedCaptureReusesItsPreviousFile() throws {
        let original = contents()
        let first = try ProjectPackage.write(original, previous: nil)
        let address = original.captures.records.keys.first!
        let firstFile = ProjectPackage.wrapper(at: "captures/" + address.relativePath, in: first)
        
        var changed = original
        changed.project.name = "Renamed"
        let second = try ProjectPackage.write(changed, previous: first)
        
        #expect(ProjectPackage.wrapper(at: "captures/" + address.relativePath, in: second) === firstFile)
        
        changed.captures.records[address]?.revision += 1
        let third = try ProjectPackage.write(changed, previous: second)
        #expect(ProjectPackage.wrapper(at: "captures/" + address.relativePath, in: third) !== firstFile)
    }
    
    @Test func aFormatOneProjectMigratesToAnchoredPlacements() throws {
        let data = TestResources.data("formats/project-v1.json")
        let project = try FormatMigration.decode(Project.self, from: data, fileName: "project.json", currentVersion: Project.currentFormatVersion, steps: FormatMigration.projectSteps)
        let old = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let oldStyle = try #require(old["style"] as? [String: Any])
        let oldPhone = try #require((oldStyle["layouts"] as? [String: Any])?["phone"] as? [String: Any])
        let oldFrame = try #require((oldPhone["primary"] as? [String: Any])?["frame"] as? [String: Double])
        let straight = try #require(project.style.template(.straight)?.layouts[.phone])
        
        #expect(project.formatVersion == 3)
        
        // A centered, top-aligned box keeps its top center.
        #expect(straight.primary.anchor == .top)
        #expect(abs(straight.primary.position.x - (oldFrame["x"]! + oldFrame["width"]! / 2)) < 0.000001)
        #expect(straight.primary.position.y == oldFrame["y"])
        #expect(straight.primary.width == oldFrame["width"])
        
        // A device keeps its center, and its glow becomes a blur of its shape.
        let tilted = try #require(project.style.template(.tilted)?.layouts[.phone]?.device)
        #expect(tilted.anchor == .center)
        #expect(tilted.position == NormPoint(x: 0.62, y: 0.64))
        #expect(tilted.rotation == 9)
        #expect(tilted.glow?.blur == 0.06)
        #expect(tilted.glow?.opacity == 0.55)
    }
    
    @Test func aFormatTwoProjectMigratesSetsIntoDevicesOneOrderAndProductPages() throws {
        let project = try migratedFormatTwo()
        let (a1, a2, a3, a4, a5) = (slideID(1), slideID(2), slideID(3), slideID(4), slideID(5))
        
        #expect(project.formatVersion == 3)
        #expect(project.devices == [.phone, .pad, .duoOuter, .watch])
        #expect(project.targets == ["iphone-dynamic-island-large", "ipad-13", "iphone-duo-outer", "watch"])
        #expect(project.slideOrder == [a1, a2, a3, a4])
        #expect(project.productPages == [ProductPage(id: UUID(uuidString: "00000000-0000-0000-0000-00000000B003")!, name: "Hikers", pageID: "cpp-1", slideIDs: [a3, a2])])
        #expect(project.drafts.map(\.id) == [a5])
        
        // A slide is off for the devices no set it was in had.
        #expect(project.slides[a1]?.excludedDevices == [])
        #expect(project.slides[a2]?.excludedDevices == [.watch])
        #expect(project.slides[a4]?.excludedDevices == [.phone, .pad, .duoOuter])
        #expect(project.slides[a5]?.excludedDevices == [])
        
        // Variants became templates, and the Duo got copies of the iPad layouts it borrowed.
        #expect(project.style.templates.map(\.id) == [.straight, .tilted, .zoomed])
        #expect(project.style.templates.map(\.name) == ["Straight", "Tilted", "Zoomed"])
        #expect(project.style.template(.straight)?.layouts[.duoOuter] == project.style.template(.straight)?.layouts[.pad])
        #expect(project.style.template(.zoomed)?.layouts.keys.sorted { $0.rawValue < $1.rawValue } == [.phone])
        #expect(project.slides[a2]?.template == Varying(.straight, overrides: [.phone: .tilted]))
        
        // A nudge became a detached device placement.
        let detached = try #require(project.slides[a3]?.detachments[.phone]?.device)
        #expect(abs(detached.position.x - 0.6) < 0.000001)
        #expect(abs(detached.position.y - 0.58) < 0.000001)
        #expect(abs(detached.width - 0.88) < 0.000001)
        #expect(detached.rotation == 3)
    }
    
    /// Every cell format 2 drew for the format 2 fixture (recorded with format 2's resolver, in
    /// `project-v2-geometry.json`) draws in the same place after migrating. Text boxes compare by their position and
    /// width: their height now follows the lines the text wraps to, where format 2's followed a line limit.
    @Test func aMigratedFormatTwoProjectDrawsEveryCellTheSame() throws {
        let project = try migratedFormatTwo()
        let rows = try #require(try JSONSerialization.jsonObject(with: TestResources.data("formats/project-v2-geometry.json")) as? [[String: Any]])
        #expect(rows.count == 17)
        
        for row in rows {
            let slide = try #require(project.slides[UUID(uuidString: row["slide"] as! String)!])
            let target = DeviceTable.target(row["target"] as! String)
            #expect(slide.isOn(target.deviceClass), "\(slide.title) is off for \(target.id)")
            
            let scene = Resolver.resolve(ResolveRequest(slide: slide, style: project.style, target: target, locale: "en-US", sourceLocale: "en-US", captures: CaptureCatalog()))
            let device = try #require(scene.device)
            let context = "\(row["set"]!) › \(slide.title) › \(target.id)"
            
            #expect(close([device.center.x, device.center.y], row["deviceCenter"]), "\(context): device center")
            #expect(close([device.size.width, device.size.height], row["deviceSize"]), "\(context): device size")
            #expect(close([device.rotation], [row["deviceRotation"]!]), "\(context): rotation")
            #expect(close(scene.primary.map { [$0.frame.minX, $0.frame.minY, $0.frame.width] } ?? [], (row["primary"] as? [Double])?.prefix(3).map { $0 }), "\(context): primary")
            #expect(close(scene.secondary.map { [$0.frame.minX, $0.frame.minY, $0.frame.width] } ?? [], (row["secondary"] as? [Double])?.prefix(3).map { $0 }), "\(context): secondary")
            #expect((device.glow != nil) == (row["glow"] as? Bool), "\(context): glow")
        }
    }
    
    // MARK: - Helpers
    
    private func migratedFormatTwo() throws -> Project {
        try FormatMigration.decode(
            Project.self,
            from: TestResources.data("formats/project-v2.json"),
            fileName: "project.json",
            currentVersion: Project.currentFormatVersion,
            steps: FormatMigration.projectSteps
        )
    }
    
    private func slideID(_ number: Int) -> UUID {
        UUID(uuidString: "00000000-0000-0000-0000-00000000A00\(number)")!
    }
    
    private func close(_ values: [Double], _ recorded: Any?) -> Bool {
        let recorded = (recorded as? [Any])?.compactMap { ($0 as? NSNumber)?.doubleValue } ?? []
        return values.count == recorded.count && zip(values, recorded).allSatisfy { abs($0 - $1) < 0.0001 }
    }
}
