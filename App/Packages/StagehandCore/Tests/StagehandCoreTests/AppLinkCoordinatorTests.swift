#if os(macOS)
import Dependencies
import DependenciesTestSupport
import Foundation
@testable import StagehandCore
import Testing
import UniformTypeIdentifiers

/// Choosing the app's Xcode project in the Link App sheet.
@MainActor
@Suite(.dependencies) struct AppLinkCoordinatorTests {
    /// Regression test: Choose… asked for `UTType(filenameExtension: "xcodeproj")`, which assumes a data file and so
    /// made up a dynamic type that a real project (a package folder) never conforms to. Every project was greyed out.
    @Test(arguments: ["TrekPoint.xcodeproj", "TrekPoint.xcworkspace"])
    func theOpenPanelAcceptsARealXcodeProject(name: String) throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "AppLinkCoordinatorTests-\(UUID().uuidString)")
        let project = folder.appending(path: name)
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        
        let type = try #require(try project.resourceValues(forKeys: [.contentTypeKey]).contentType)
        
        #expect(AppLinkCoordinator.projectTypes.contains { type.conforms(to: $0) && $0 != .folder })
    }
    
    @Test func choosingAFolderFindsTheProjectInIt() {
        let folder = URL(filePath: "/Developer/TrekPoint-iOS")
        let files = InMemoryFileManager(files: [
            folder.appending(path: "README.md"): Data(),
            folder.appending(path: "TrekPoint.xcodeproj/project.pbxproj"): Data(),
        ])
        
        #expect(AppLinkCoordinator.xcodeProject(for: folder, fileManager: files) == folder.appending(path: "TrekPoint.xcodeproj"))
        #expect(AppLinkCoordinator.xcodeProject(for: folder.appending(path: "TrekPoint.xcodeproj"), fileManager: files) == folder.appending(path: "TrekPoint.xcodeproj"))
    }
    
    @Test func aWorkspaceWinsOverAProject() {
        let folder = URL(filePath: "/Developer/App")
        let files = InMemoryFileManager(files: [
            folder.appending(path: "App.xcodeproj/project.pbxproj"): Data(),
            folder.appending(path: "App.xcworkspace/contents.xcworkspacedata"): Data(),
        ])
        
        #expect(AppLinkCoordinator.xcodeProject(for: folder, fileManager: files) == folder.appending(path: "App.xcworkspace"))
    }
    
    @Test func aFolderWithoutAProjectFindsNothing() {
        let folder = URL(filePath: "/Developer/Notes")
        let files = InMemoryFileManager(files: [folder.appending(path: "README.md"): Data()])
        
        #expect(AppLinkCoordinator.xcodeProject(for: folder, fileManager: files) == nil)
    }
}
#endif
