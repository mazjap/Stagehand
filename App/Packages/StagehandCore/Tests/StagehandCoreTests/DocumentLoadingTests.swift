import Foundation
@testable import StagehandCore
import Testing
import UniformTypeIdentifiers

@MainActor
@Suite struct DocumentLoadingTests {
    private var unreadablePackage: FileWrapper {
        FileWrapper(directoryWithFileWrappers: ["project.json": FileWrapper(regularFileWithContents: Data("{\"formatVersion\": 3}".utf8))])
    }

    /// Regression test: a project that couldn't be read opened as an empty project under its own name, and an edit there
    /// could have saved over the real file.
    @Test func aProjectThatCantBeReadReportsItAndRefusesToSave() async throws {
        let document = ProjectDocument()
        let empty = document.project
        let snapshot = ProjectDocument.load(unreadablePackage)

        #expect(throws: DocumentError.self) {
            try snapshot.contentsToWrite()
        }

        try await document.apply(snapshot: snapshot, previous: nil)

        #expect(document.loadFailure != nil)
        #expect(document.loadGeneration == 0)
        #expect(document.project == empty)

        await #expect(throws: DocumentError.self) {
            _ = try await document.snapshot(contentType: .stagehandProject)
        }
    }

    /// Regression test: the same for a style.
    @Test func aStyleThatCantBeReadReportsItAndRefusesToSave() async throws {
        let document = StyleDocument()
        let snapshot = StyleDocument.load(FileWrapper(directoryWithFileWrappers: [:]))

        try await document.apply(snapshot: snapshot, previous: nil)

        #expect(document.loadFailure != nil)
        #expect(document.loadGeneration == 0)

        await #expect(throws: DocumentError.self) {
            _ = try await document.snapshot(contentType: .stagehandStyle)
        }
    }

    @Test func aReadableProjectLoadsAndSaves() async throws {
        let contents = ProjectContents(project: .fixture())
        let document = ProjectDocument()
        let package = try ProjectPackage.write(contents, previous: nil)

        try await document.apply(snapshot: ProjectDocument.load(package), previous: nil)

        #expect(document.loadFailure == nil)
        #expect(document.loadGeneration == 1)
        #expect(document.project == contents.project)

        let snapshot = try await document.snapshot(contentType: .stagehandProject)
        #expect(try snapshot.contentsToWrite().project == contents.project)
    }

    @Test func aSuccessfulReadClearsAnEarlierFailure() async throws {
        let document = ProjectDocument()

        try await document.apply(snapshot: ProjectDocument.load(unreadablePackage), previous: nil)
        #expect(document.loadFailure != nil)

        let package = try ProjectPackage.write(ProjectContents(project: .fixture()), previous: nil)
        try await document.apply(snapshot: ProjectDocument.load(package), previous: nil)
        #expect(document.loadFailure == nil)
    }
}
