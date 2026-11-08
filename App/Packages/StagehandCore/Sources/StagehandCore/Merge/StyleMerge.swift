import Foundation

/// A three-way merge of a project's style with a newer version of the library style it came from.
///
/// The merge runs over flattened key paths: each JSON leaf, with each `Varying` override as its own path. Fills and
/// bezel choices are enums with associated values, so each is merged whole.
public enum StyleMerge {
    /// A value both sides changed differently, which the user picks.
    public struct Conflict: Hashable, Sendable, Identifiable {
        public var path: String
        public var project: JSONValue?
        public var library: JSONValue?
        
        public var id: String {
            path
        }
    }
    
    public enum Side: Hashable, Sendable {
        case project
        case library
    }
    
    public struct Result: Hashable, Sendable {
        public var merged: Style
        public var conflicts: [Conflict]
    }
    
    public enum MergeError: Error, LocalizedError {
        case unmergeable(String)
        
        public var errorDescription: String? {
            switch self {
            case let .unmergeable(reason): "The styles couldn't be merged: \(reason)"
            }
        }
    }
    
    /// Takes what only the library changed and keeps what only the project changed. A path both changed differently
    /// is a conflict, which keeps the project's value unless `resolutions` picks the library's.
    public static func merge(base: Style, library: Style, project: Style, resolutions: [String: Side] = [:]) throws -> Result {
        let base = try flatten(base)
        let library = try flatten(library)
        let project = try flatten(project)
        var merged: [String: JSONValue] = [:]
        var conflicts: [Conflict] = []
        
        for path in Set(base.keys).union(library.keys).union(project.keys).sorted() {
            let original = base[path]
            let theirs = library[path]
            let ours = project[path]
            let value: JSONValue?
            
            if theirs == original {
                value = ours
            } else if ours == original || ours == theirs {
                value = theirs
            } else {
                conflicts.append(Conflict(path: path, project: ours, library: theirs))
                value = resolutions[path] == .library ? theirs : ours
            }
            
            merged[path] = value
        }
        
        var style = try unflatten(merged)
        
        // The merged style is the project's, at the library's version.
        style.id = try Self.decode(Style.self, from: project).id
        style.version = try Self.decode(Style.self, from: library).version
        return Result(merged: style, conflicts: conflicts)
    }
    
    // MARK: - Flattening
    
    /// Paths merged whole instead of leaf by leaf.
    static func isWhole(_ path: [String]) -> Bool {
        guard let last = path.last else {
            return false
        }
        
        if last == "bezel" {
            return true
        }
        
        // `background` is a Varying<Fill>: its base and each override are whole fills.
        if path.count >= 2, path[0] == "background" {
            return path.count == 2 && path[1] == "base" || path.count == 3 && path[1] == "overrides"
        }
        
        return false
    }
    
    static func flatten(_ style: Style) throws -> [String: JSONValue] {
        let value = try JSONDecoder().decode(JSONValue.self, from: FormatMigration.makeEncoder().encode(style))
        var result: [String: JSONValue] = [:]
        
        func visit(_ value: JSONValue, path: [String]) {
            if case let .object(object) = value, !object.isEmpty, !isWhole(path) {
                for (key, child) in object {
                    visit(child, path: path + [key])
                }
            } else {
                result[path.joined(separator: "\u{1F}")] = value
            }
        }
        
        visit(value, path: [])
        return result
    }
    
    static func unflatten(_ paths: [String: JSONValue]) throws -> Style {
        var root: [String: JSONValue] = [:]
        
        func insert(_ value: JSONValue, at path: ArraySlice<String>, into object: inout [String: JSONValue]) {
            guard let key = path.first else {
                return
            }
            
            if path.count == 1 {
                object[key] = value
                return
            }
            
            var child: [String: JSONValue] = if case let .object(existing) = object[key] { existing } else { [:] }
            insert(value, at: path.dropFirst(), into: &child)
            object[key] = .object(child)
        }
        
        for (path, value) in paths {
            insert(value, at: ArraySlice(path.split(separator: "\u{1F}", omittingEmptySubsequences: false).map(String.init)), into: &root)
        }
        
        do {
            return try FormatMigration.makeDecoder().decode(Style.self, from: JSONEncoder().encode(JSONValue.object(root)))
        } catch {
            throw MergeError.unmergeable(String(describing: error))
        }
    }
    
    private static func decode<T: Decodable>(_ type: T.Type, from paths: [String: JSONValue]) throws -> T {
        try FormatMigration.makeDecoder().decode(T.self, from: JSONEncoder().encode(try unflatten(paths)))
    }
    
    /// A path for people: `primary › size › overrides › pad`.
    public static func displayPath(_ path: String) -> String {
        path.split(separator: "\u{1F}").joined(separator: " › ")
    }
}
