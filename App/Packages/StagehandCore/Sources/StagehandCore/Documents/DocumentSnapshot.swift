import Foundation

/// What reading a document gave: its contents, or why it can't be read.
///
/// A reader that throws leaves SwiftUI's new, empty document on screen under the file's name, where an edit could save
/// over the file. So readers catch their errors and hand them to the document, which shows them and refuses to save.
public enum DocumentSnapshot: Equatable, Sendable {
    case contents(ProjectContents)
    case unreadable(DocumentError)

    public init(reading read: () throws(DocumentError) -> ProjectContents) {
        do {
            self = .contents(try read())
        } catch {
            self = .unreadable(error)
        }
    }

    // MARK: - Functions

    /// The contents to write, or the reason there are none.
    public func contentsToWrite() throws(DocumentError) -> ProjectContents {
        switch self {
        case let .contents(contents): contents
        case let .unreadable(error): throw error
        }
    }
}
