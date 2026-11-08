import Foundation

extension String {
    /// Lowercased, with runs of anything but letters and digits replaced by a hyphen: "Read the Land!" becomes `read-the-land`.
    public var slugified: String {
        let folded = folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US_POSIX")).lowercased()
        var result = ""
        var pendingHyphen = false
        
        for scalar in folded.unicodeScalars {
            if CharacterSet.alphanumerics.contains(scalar) && scalar.isASCII {
                if pendingHyphen && !result.isEmpty {
                    result.append("-")
                }
                
                result.unicodeScalars.append(scalar)
                pendingHyphen = false
            } else {
                pendingHyphen = true
            }
        }
        
        return result.isEmpty ? "slide" : result
    }
}
