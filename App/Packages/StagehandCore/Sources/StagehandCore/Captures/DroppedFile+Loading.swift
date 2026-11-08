import Foundation

extension DroppedFile {
    /// Reads dropped or picked files, skipping any that can't be read.
    public static func load(from urls: [URL]) -> [DroppedFile] {
        urls.compactMap { url in
            let accessing = url.startAccessingSecurityScopedResource()
            
            defer {
                if accessing {
                    url.stopAccessingSecurityScopedResource()
                }
            }
            
            return (try? Data(contentsOf: url)).map { DroppedFile(name: url.lastPathComponent, data: $0) }
        }
    }
}
