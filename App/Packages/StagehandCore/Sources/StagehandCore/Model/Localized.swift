import Foundation
import StagehandModel

/// A BCP 47 locale identifier, like `en-US` or `de`.
public typealias LocaleID = String

/// Text in each locale.
public typealias Localized = [LocaleID: String]

/// Text that resolved for a device class and locale.
public struct ResolvedString: Equatable, Sendable {
    public var text: String
    
    /// Set when the text came from the source locale because the requested locale had none.
    public var fellBackToSource: Bool
}

extension Varying where Value == Localized {
    /// Text for a device class and locale.
    ///
    /// The order is the class's override in the locale, the shared text in the locale, the class's override in
    /// the source locale, then the shared text in the source locale. A fallback to the source locale is flagged.
    public func text(for device: DeviceClass, locale: LocaleID, source: LocaleID) -> ResolvedString? {
        let override = overrides[device]
        
        if let text = override?[locale] ?? base[locale] {
            return ResolvedString(text: text, fellBackToSource: false)
        }
        
        if let text = override?[source] ?? base[source] {
            return ResolvedString(text: text, fellBackToSource: locale != source)
        }
        
        return nil
    }
    
    /// Whether the class overrides the text in this locale.
    public func isOverridden(for device: DeviceClass, locale: LocaleID) -> Bool {
        overrides[device]?[locale] != nil
    }
    
    /// Sets the text in one locale, for the class's override when it has one in that locale, or else the shared text.
    public mutating func setText(_ text: String, for device: DeviceClass, locale: LocaleID, scope: EditScope = .automatic) {
        let resolved: EditScope.Resolved = switch scope {
        case .automatic: isOverridden(for: device, locale: locale) ? .override : .shared
        case .shared: .shared
        case .override: .override
        }
        
        switch resolved {
        case .shared:
            base[locale] = text
        case .override:
            overrides[device, default: [:]][locale] = text
        }
        
        normalizeLocalized()
    }
    
    /// Gives a class its own text in a locale, starting from what it shows now.
    public mutating func overrideText(for device: DeviceClass, locale: LocaleID, source: LocaleID) {
        let current = text(for: device, locale: locale, source: source)?.text ?? ""
        overrides[device, default: [:]][locale] = current
    }
    
    /// Removes a class's override in a locale.
    public mutating func revertText(for device: DeviceClass, locale: LocaleID) {
        overrides[device]?[locale] = nil
        normalizeLocalized()
    }
    
    /// Removes override entries equal to the shared text, and empty overrides.
    ///
    /// An override only needs the locales it changes, so each locale is compared on its own.
    public mutating func normalizeLocalized() {
        var cleaned: [DeviceClass: Localized] = [:]
        
        for (device, localized) in overrides {
            let kept = localized.filter { base[$0.key] != $0.value }
            
            if !kept.isEmpty {
                cleaned[device] = kept
            }
        }
        
        overrides = cleaned
    }
}
