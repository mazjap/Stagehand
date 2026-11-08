import Foundation
import StagehandModel

public enum StringCatalogError: Error, Equatable, LocalizedError {
    case unreadable(String)
    
    public var errorDescription: String? {
        switch self {
        case let .unreadable(reason): "The String Catalog couldn't be read: \(reason)"
        }
    }
}

/// Marketing text as a String Catalog (`.xcstrings`), so it's translated the same way as the apps' strings.
///
/// Keys are `<slide slug>.primary` and `<slide slug>.secondary`. Per-device overrides become the catalog's
/// Vary by Device variations for iPhone, iPad, Mac and Watch. The Duo's classes have no variation, so they get
/// keys of their own, like `<slide slug>.primary.duoInner`.
public enum StringCatalog {
    struct Catalog: Codable, Equatable {
        var sourceLanguage: String
        var strings: [String: Entry]
        var version: String
    }
    
    struct Entry: Codable, Equatable {
        var comment: String?
        var extractionState: String?
        var localizations: [String: Localization]?
    }
    
    struct Localization: Codable, Equatable {
        var stringUnit: StringUnit?
        var variations: Variations?
    }
    
    struct Variations: Codable, Equatable {
        var device: [String: Localization]?
    }
    
    struct StringUnit: Codable, Equatable {
        var state: String
        var value: String
    }
    
    /// The catalog's device variation for a class, or `nil` for the Duo's, which get their own keys.
    static func variation(for device: DeviceClass) -> String? {
        switch device {
        case .phone: "iphone"
        case .pad: "ipad"
        case .mac: "mac"
        case .watch: "applewatch"
        case .duoOuter, .duoInner: nil
        }
    }
    
    static func device(forVariation variation: String) -> DeviceClass? {
        DeviceClass.allCases.first { self.variation(for: $0) == variation }
    }
    
    // MARK: - Export
    
    public static func export(_ project: Project) throws -> Data {
        var strings: [String: Entry] = [:]
        
        for slide in project.slides.values {
            for role in TextRole.allCases {
                strings.merge(entries(for: slide.text(role), key: "\(slide.slug).\(role.rawValue)", comment: "\(slide.title), \(role.displayName.lowercased()) text")) { first, _ in first }
            }
            
            // Extra text elements, keyed by their name.
            for (id, content) in slide.extraContent {
                guard let text = content.text, let element = textElement(id, in: project.style) else {
                    continue
                }
                
                strings.merge(entries(for: text, key: "\(slide.slug).\(extraKey(element))", comment: "\(slide.title), \(element.name)")) { first, _ in first }
            }
        }
        
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(Catalog(sourceLanguage: project.sourceLocale, strings: strings, version: "1.0"))
    }
    
    /// One text's entry, with device variations for its overrides, and keys of their own for the Duo's classes.
    static func entries(for text: Varying<Localized>, key: String, comment: String) -> [String: Entry] {
        var strings: [String: Entry] = [:]
        var localizations: [String: Localization] = [:]
        let locales = Set(text.base.keys).union(text.overrides.filter { variation(for: $0.key) != nil }.flatMap(\.value.keys))
        
        for locale in locales {
            var devices: [String: Localization] = [:]
            
            for (device, localized) in text.overrides {
                if let name = variation(for: device), let value = localized[locale] {
                    devices[name] = Localization(stringUnit: StringUnit(state: "translated", value: value))
                }
            }
            
            let base = text.base[locale].map { StringUnit(state: "translated", value: $0) }
            
            if devices.isEmpty {
                localizations[locale] = Localization(stringUnit: base)
            } else {
                devices["other"] = base.map { Localization(stringUnit: $0) }
                localizations[locale] = Localization(variations: Variations(device: devices))
            }
        }
        
        strings[key] = Entry(comment: comment, extractionState: "manual", localizations: localizations)
        
        for device in [DeviceClass.duoOuter, .duoInner] {
            guard let localized = text.overrides[device], !localized.isEmpty else {
                continue
            }
            
            strings["\(key).\(device.rawValue)"] = Entry(
                comment: "\(comment) on \(device.displayName)",
                extractionState: "manual",
                localizations: localized.mapValues { Localization(stringUnit: StringUnit(state: "translated", value: $0)) }
            )
        }
        
        return strings
    }
    
    /// An extra text element's key part: its name as a slug, kept clear of the standard roles' keys.
    static func extraKey(_ element: TemplateElement) -> String {
        let slug = element.name.slugified
        return TextRole(rawValue: slug) == nil && DeviceClass(rawValue: slug) == nil ? slug : "extra-\(slug)"
    }
    
    /// A text element's definition, from whichever template has it.
    static func textElement(_ id: ElementID, in style: Style) -> TemplateElement? {
        style.templates.lazy.compactMap { $0.element(id) }.first { $0.kind == .text }
    }
    
    // MARK: - Import
    
    /// Reads translations back into the slides, matching keys by slug. Unknown keys are ignored.
    public static func importCatalog(_ data: Data, into project: Project) throws(StringCatalogError) -> Project {
        let catalog: Catalog
        
        do {
            catalog = try JSONDecoder().decode(Catalog.self, from: data)
        } catch {
            throw .unreadable(error.localizedDescription)
        }
        
        var project = project
        let slugs = Dictionary(project.slides.values.map { ($0.slug, $0.id) }, uniquingKeysWith: { first, _ in first })
        let extraKeys = Dictionary(
            project.style.templates.flatMap(\.elements).filter { $0.kind == .text }.map { (extraKey($0), $0.id) },
            uniquingKeysWith: { first, _ in first }
        )
        
        for (key, entry) in catalog.strings {
            let parts = key.split(separator: ".").map(String.init)
            
            guard parts.count >= 2, let id = slugs[parts[0]] else {
                continue
            }
            
            let duo = parts.count > 2 ? DeviceClass(rawValue: parts[2]) : nil
            
            if let role = TextRole(rawValue: parts[1]) {
                project.slides[id]?.updateText(role) { apply(entry, duo: duo, to: &$0) }
            } else if let element = extraKeys[parts[1]] {
                var text = project.slides[id]?.extraContent[element]?.text ?? Varying(Localized())
                apply(entry, duo: duo, to: &text)
                project.slides[id]?.extraContent[element] = .text(text)
            }
        }
        
        return project
    }
    
    /// Reads one entry's translations into a text: its base and device variations, or a Duo class's own key.
    static func apply(_ entry: Entry, duo: DeviceClass?, to text: inout Varying<Localized>) {
        for (locale, localization) in entry.localizations ?? [:] {
            if let duo {
                if let value = localization.stringUnit?.value {
                    text.overrides[duo, default: [:]][locale] = value
                }
                
                continue
            }
            
            if let value = localization.stringUnit?.value {
                text.base[locale] = value
            }
            
            for (name, variation) in localization.variations?.device ?? [:] {
                guard let value = variation.stringUnit?.value else {
                    continue
                }
                
                if name == "other" {
                    text.base[locale] = value
                } else if let device = device(forVariation: name) {
                    text.overrides[device, default: [:]][locale] = value
                }
            }
        }
        
        text.normalizeLocalized()
    }
}
