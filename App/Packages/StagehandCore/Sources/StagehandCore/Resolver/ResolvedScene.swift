import CoreGraphics
import Foundation
import StagehandModel

/// A reference to an image the renderer loads: a capture, a bezel or a bezel's mask.
///
/// Capture references include the capture's revision, so a replaced capture gets a new reference and caches refresh.
public struct ImageRef: Hashable, Sendable, CustomStringConvertible {
    public var rawValue: String
    
    public init(_ rawValue: String) {
        self.rawValue = rawValue
    }
    
    public var description: String {
        rawValue
    }
}

/// Everything needed to draw one slide on one target, in absolute pixels.
public struct ResolvedScene: Hashable, Sendable {
    public var canvas: CGSize
    public var background: ResolvedFill
    
    /// The Main Device, unless its template hides it.
    public var device: ResolvedDevice?
    public var primary: ResolvedText?
    public var secondary: ResolvedText?
    
    /// The template's extra elements, in its order.
    public var extras: [ResolvedElement]
    public var flags: [SceneFlag]
    
    public init(
        canvas: CGSize,
        background: ResolvedFill,
        device: ResolvedDevice?,
        primary: ResolvedText?,
        secondary: ResolvedText?,
        extras: [ResolvedElement] = [],
        flags: [SceneFlag]
    ) {
        self.canvas = canvas
        self.background = background
        self.device = device
        self.primary = primary
        self.secondary = secondary
        self.extras = extras
        self.flags = flags
    }
    
    /// Every image the scene draws.
    public var imageRefs: [ImageRef] {
        var refs = [device?.capture, device?.bezel, device?.mask].compactMap { $0 }
        
        for extra in extras {
            switch extra.content {
            case let .device(device): refs += [device.capture, device.bezel, device.mask].compactMap { $0 }
            case let .image(image): refs += [image.image].compactMap { $0 }
            case .text: break
            }
        }
        
        return refs
    }
    
    public func text(_ role: TextRole) -> ResolvedText? {
        switch role {
        case .primary: primary
        case .secondary: secondary
        }
    }
    
    public func extra(_ id: ElementID) -> ResolvedElement? {
        extras.first { $0.id == id }
    }
    
    /// Images and extra devices, drawn behind the Main Device.
    public var extrasBehind: [ResolvedElement] {
        extras.filter { if case .text = $0.content { false } else { true } }
    }
    
    /// Extra text, drawn in front of everything.
    public var extrasInFront: [ResolvedElement] {
        extras.filter { if case .text = $0.content { true } else { false } }
    }
    
    /// An element's frame for snapping and selection: a device's or image's rotated bounding box, or a text box.
    public func frame(of element: ElementRef) -> CGRect? {
        switch element {
        case .device:
            return device?.boundingBox
        case .primary:
            return primary?.frame
        case .secondary:
            return secondary?.frame
        case let .extra(id):
            return switch extra(id)?.content {
            case let .text(text): text.frame
            case let .device(device): device.boundingBox
            case let .image(image): image.boundingBox
            case nil: nil
            }
        }
    }
    
    /// Every element drawn, for snapping.
    public var elements: [ElementRef] {
        var elements: [ElementRef] = []
        
        if device != nil { elements.append(.device) }
        if primary != nil { elements.append(.primary) }
        if secondary != nil { elements.append(.secondary) }
        
        return elements + extras.map { .extra($0.id) }
    }
}

/// One of a template's extra elements, resolved.
public struct ResolvedElement: Hashable, Sendable, Identifiable {
    public enum Content: Hashable, Sendable {
        case text(ResolvedText)
        case device(ResolvedDevice)
        case image(ResolvedImage)
    }
    
    public var id: ElementID
    public var content: Content
}

/// An image element: an asset, rotated around its center.
public struct ResolvedImage: Hashable, Sendable {
    public var center: CGPoint
    
    /// Before rotation.
    public var size: CGSize
    public var rotation: Double
    public var cornerRadius: Double
    
    /// `nil` when the asset is missing, which draws a placeholder.
    public var image: ImageRef?
    
    public var boundingBox: CGRect {
        ResolvedDevice.boundingBox(center: center, size: size, rotation: rotation)
    }
}

public enum ResolvedFill: Hashable, Sendable {
    case solid(RGBA)
    case linear([RGBA], angle: Double)
    case radial([RGBA], center: CGPoint, radius: Double)
}

/// A blurred, colored copy of the device's silhouette, drawn behind it.
public struct ResolvedGlow: Hashable, Sendable {
    /// From the device's center, in pixels.
    public var offset: CGPoint
    
    /// The blur radius, in pixels.
    public var blur: Double
    
    /// The silhouette's size as a multiple of the device's.
    public var spread: Double
    public var color: RGBA
    public var opacity: Double
}

public struct ResolvedDevice: Hashable, Sendable {
    /// The device's rotated frame's bounding box, for snapping.
    public var boundingBox: CGRect {
        Self.boundingBox(center: center, size: size, rotation: rotation)
    }
    
    /// A rotated box's bounding box.
    public static func boundingBox(center: CGPoint, size: CGSize, rotation: Double) -> CGRect {
        let corners = [BoxAnchor.topLeading, .topTrailing, .bottomLeading, .bottomTrailing].map {
            Resolver.devicePoint($0, center: center, size: size, rotation: rotation)
        }
        let xs = corners.map(\.x)
        let ys = corners.map(\.y)
        return CGRect(x: xs.min()!, y: ys.min()!, width: xs.max()! - xs.min()!, height: ys.max()! - ys.min()!)
    }
    
    public enum Frame: Hashable, Sendable {
        /// A bezel image drawn over the capture.
        case bezel
        
        /// The capture alone, with rounded corners and a shadow.
        case bare
        
        /// A plain rounded frame, drawn when the bezel is missing.
        case placeholder
    }
    
    public var center: CGPoint
    
    /// The device's size before rotation: the bezel's, or the capture's when bare.
    public var size: CGSize
    
    /// Degrees, clockwise.
    public var rotation: Double
    
    /// The screen within the device's frame, from its top left.
    public var screen: CGRect
    public var screenCornerRadius: Double
    public var frame: Frame
    public var capture: ImageRef?
    public var captureSize: CGSize?
    public var bezel: ImageRef?
    public var mask: ImageRef?
    
    /// A blurred copy of the device's silhouette, drawn behind it.
    public var glow: ResolvedGlow?
}

public struct ResolvedFont: Hashable, Sendable {
    public var spec: FontSpec
    
    /// Pixels.
    public var size: Double
}

public struct ResolvedText: Hashable, Sendable {
    public var role: TextRole
    
    /// With the letter case already applied.
    public var string: String
    public var font: ResolvedFont
    public var color: RGBA
    
    /// Pixels.
    public var tracking: Double
    
    /// Extra pixels between lines.
    public var lineSpacing: Double
    public var alignment: TextAlign
    public var verticalAlignment: VerticalAlign
    
    /// As tall as the lines the text wraps to (``ResolveRequest/lineCounts``).
    public var frame: CGRect
}

/// Something a cell is flagged for.
public enum SceneFlag: Hashable, Sendable {
    case textFallback(TextRole, locale: LocaleID)
    case missingText(TextRole)
    case missingLayout(DeviceClass)
    case templateFallback(TemplateID)
    case missingImage(String)
    case captureFallbackLocale(CaptureAddress)
    case missingCapture(CaptureAddress)
    case captureSizeMismatch(CaptureAddress)
    case missingBezel(DeviceClass)
    case quirkReview(CaptureAddress, quirks: [String])
    
    public enum Severity: Int, Comparable, Sendable {
        case info
        case warning
        case error
        
        public static func < (lhs: Severity, rhs: Severity) -> Bool {
            lhs.rawValue < rhs.rawValue
        }
    }
    
    // MARK: - Computed Properties
    
    public var severity: Severity {
        switch self {
        case .templateFallback: .info
        case .textFallback, .captureFallbackLocale, .missingBezel, .quirkReview, .captureSizeMismatch, .missingImage: .warning
        case .missingText, .missingLayout, .missingCapture: .error
        }
    }
    
    public var message: String {
        switch self {
        case let .textFallback(role, locale): "\(role.displayName) text has no \(locale) translation and uses the source locale"
        case let .missingText(role): "\(role.displayName) text is empty"
        case let .missingLayout(device): "No template has a layout for \(device.displayName)"
        case .templateFallback: "The slide's template has no layout for this device, so the first template that does is used"
        case let .missingImage(name): "The image \(name) isn't in the project's assets"
        case let .captureFallbackLocale(address): "No \(address.locale) capture for \(address.key), so the source locale's is used"
        case let .missingCapture(address): "No capture for \(address.key) on \(address.deviceClass.displayName) (\(address.locale))"
        case let .captureSizeMismatch(address): "The \(address.key) capture's size doesn't match \(address.deviceClass.displayName)"
        case let .missingBezel(device): "No bezel for \(device.displayName), so a plain frame is drawn"
        case let .quirkReview(address, quirks): "\(address.key) was corrected for \(quirks.joined(separator: ", ")) on a newer runtime; check it once"
        }
    }
}
