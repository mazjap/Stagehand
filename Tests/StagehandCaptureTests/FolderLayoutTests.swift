import Foundation
import StagehandCapture
import StagehandModel
import Testing

@Suite struct FolderLayoutTests {
    @Test func theDefaultLayoutIsLocaleThenClass() {
        let path = ShotPath(name: "read-the-land", locale: "en-US", deviceClass: .duoInner, targetID: "iphone-duo-inner")
        #expect(FolderLayout.byLocaleAndClass.relativePath(for: path) == "en-US/duoInner/read-the-land.png")
    }
    
    @Test func unknownValuesStillMakeAPath() {
        let path = ShotPath(name: "x", locale: nil, deviceClass: nil, targetID: nil)
        #expect(FolderLayout.byLocaleAndClass.relativePath(for: path) == "unknown-locale/unclassified/x.png")
    }
    
    @Test func aCustomLayoutChoosesItsOwnPath() {
        let layout = FolderLayout.custom { path in
            let folder = switch path.deviceClass {
            case .duoOuter: "iPhone Duo Closed"
            case .duoInner: "iPhone Duo"
            case .pad: "iPad"
            default: "iPhone"
            }
            return "\(folder)/\(path.name).png"
        }
        
        let path = ShotPath(name: "read-the-land", locale: "en-US", deviceClass: .duoOuter, targetID: nil)
        #expect(layout.relativePath(for: path) == "iPhone Duo Closed/read-the-land.png")
    }
    
    @Test func writingCreatesTheFolders() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "stagehand-folder-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        
        let output = FolderOutput(root: root)
        let url = try output.write(Data([1, 2, 3]), for: ShotPath(name: "a", locale: "de", deviceClass: .pad, targetID: nil))
        
        #expect(url.path(percentEncoded: false).hasSuffix("de/pad/a.png"))
        #expect(try Data(contentsOf: url) == Data([1, 2, 3]))
    }
}
