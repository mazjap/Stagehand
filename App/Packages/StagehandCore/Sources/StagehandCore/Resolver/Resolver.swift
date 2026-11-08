import CoreGraphics
import Foundation
import StagehandModel

/// The captures a resolve can use.
public struct CaptureCatalog: Hashable, Sendable {
    public struct Entry: Hashable, Sendable {
        public var ref: ImageRef
        public var pixelWidth: Int
        public var pixelHeight: Int
        public var quirksToReview: [String]
        
        public init(ref: ImageRef, pixelWidth: Int, pixelHeight: Int, quirksToReview: [String] = []) {
            self.ref = ref
            self.pixelWidth = pixelWidth
            self.pixelHeight = pixelHeight
            self.quirksToReview = quirksToReview
        }
    }
    
    public var entries: [CaptureAddress: Entry]
    
    public init(entries: [CaptureAddress: Entry] = [:]) {
        self.entries = entries
    }
    
    /// A catalog of a project's captures, with references that change when a capture is replaced.
    public init(index: CaptureIndex) {
        self.entries = index.records.mapValues { record in
            Entry(
                ref: ImageRef.capture(record.address, revision: record.revision),
                pixelWidth: record.pixelWidth,
                pixelHeight: record.pixelHeight,
                quirksToReview: record.quirksToReview.map(\.id)
            )
        }
    }
}

extension ImageRef {
    public static func capture(_ address: CaptureAddress, revision: Int) -> ImageRef {
        ImageRef("capture:\(address.relativePath)#\(revision)")
    }
    
    /// A file from the project's `assets/`.
    public static func asset(_ name: String) -> ImageRef {
        ImageRef("asset:\(name)")
    }
}


/// Everything a resolve reads.
public struct ResolveRequest: Hashable, Sendable {
    public var slide: Slide
    public var style: Style
    public var target: DeviceTarget
    public var locale: LocaleID
    public var sourceLocale: LocaleID
    public var captures: CaptureCatalog
    public var bezels: BezelCatalog
    
    /// How many lines each text element wraps to, measured outside the resolver
    /// (``Resolver/lineCounts(in:measurer:)``). Text is drawn at its style's size and wraps as it needs; this only
    /// sets its box's height. A missing element is one line.
    public var lineCounts: [ElementRef: Int]
    
    /// Each font's line height as a multiple of its size, measured outside the resolver. A missing font uses 1.2.
    public var lineHeights: [FontSpec: Double]
    
    /// The canvas size, which is the target's export size unless a thumbnail or another accepted size is drawn.
    public var canvas: CGSize
    
    /// Each asset's pixel size, by file name, for image elements.
    public var assets: [String: CGSize]
    
    public init(
        slide: Slide,
        style: Style,
        target: DeviceTarget,
        locale: LocaleID,
        sourceLocale: LocaleID,
        captures: CaptureCatalog,
        bezels: BezelCatalog = .empty,
        lineCounts: [ElementRef: Int] = [:],
        lineHeights: [FontSpec: Double] = [:],
        canvas: CGSize? = nil,
        assets: [String: CGSize] = [:]
    ) {
        self.slide = slide
        self.style = style
        self.target = target
        self.locale = locale
        self.sourceLocale = sourceLocale
        self.captures = captures
        self.bezels = bezels
        self.lineCounts = lineCounts
        self.lineHeights = lineHeights
        self.canvas = canvas ?? CGSize(width: target.exportSize.width, height: target.exportSize.height)
        self.assets = assets
    }
}

/// Turns a slide, its style and a target into a ``ResolvedScene``.
///
/// > Warning: Keep this pure. Anything that measures, loads or renders happens before (wrapped text's line counts
/// > come in through ``ResolveRequest/lineCounts``) or after (the renderer loads the scene's ``ImageRef``s).
public enum Resolver {
    /// The line height used for a font no one has measured.
    public static let defaultLineHeight = 1.2
    
    /// The template and layout a slide uses on a class, with its detachments laid over it. Without any template for
    /// the class, the standard layout and no template.
    public static func layout(for slide: Slide, style: Style, device: DeviceClass) -> (template: Template?, layout: TemplateLayout, fellBack: Bool) {
        guard let resolved = style.resolvedTemplate(slide.template[device], for: device) else {
            return (nil, slide.detachments[device]?.applied(to: .standard) ?? .standard, true)
        }
        
        let layout = slide.detachments[device]?.applied(to: resolved.layout) ?? resolved.layout
        return (resolved.template, layout, resolved.fellBack)
    }
    
    public static func resolve(_ request: ResolveRequest) -> ResolvedScene {
        let device = request.target.deviceClass
        let canvas = request.canvas
        let style = request.style
        let slide = request.slide
        var flags: [SceneFlag] = []
        
        // Template and layout.
        let (template, layout, fellBack) = Self.layout(for: slide, style: style, device: device)
        
        if template == nil {
            flags.append(.missingLayout(device))
        } else if fellBack {
            flags.append(.templateFallback(slide.template[device]))
        }
        
        // The main device.
        let mainDevice = layout.isHidden(.device) ? nil : resolveDevice(
            layout.device,
            key: slide.captureKey[device],
            request: request,
            flags: &flags
        )
        
        // Text.
        func text(_ role: TextRole) -> ResolvedText? {
            guard !layout.isHidden(role == .primary ? .primary : .secondary) else {
                return nil
            }
            
            guard let resolved = slide.text(role).text(for: device, locale: request.locale, source: request.sourceLocale),
                  !resolved.text.isEmpty else {
                if role == .primary {
                    flags.append(.missingText(role))
                }
                
                return nil
            }
            
            if resolved.fellBackToSource {
                flags.append(.textFallback(role, locale: request.locale))
            }
            
            return resolveText(resolved.text, style: role, placement: layout.textPlacement(role), element: .text(role), request: request)
        }
        
        let primary = text(.primary)
        let secondary = text(.secondary)
        
        // Extra elements, in the template's order.
        var extras: [ResolvedElement] = []
        
        for element in template?.elements ?? [] {
            guard let placement = layout.extras[element.id] else {
                continue
            }
            
            let content = slide.extraContent[element.id]
            
            switch (element.kind, placement) {
            case let (.text, .text(textPlacement)):
                guard let string = content?.text?.text(for: device, locale: request.locale, source: request.sourceLocale)?.text, !string.isEmpty else {
                    continue
                }
                
                extras.append(ResolvedElement(id: element.id, content: .text(resolveText(string, style: element.textStyle, placement: textPlacement, element: .extra(element.id), request: request))))
            case let (.device, .device(devicePlacement)):
                let key = content?.captureKey?[device] ?? ""
                extras.append(ResolvedElement(id: element.id, content: .device(resolveDevice(devicePlacement, key: key, request: request, flags: &flags))))
            case let (.image, .image(imagePlacement)):
                let name = content?.imageName
                let size = name.flatMap { request.assets[$0] }
                
                if let name, size == nil {
                    flags.append(.missingImage(name))
                }
                
                let aspect = size.map { $0.width / max($0.height, 1) } ?? 1
                let width = imagePlacement.width * canvas.width
                let imageSize = CGSize(width: width, height: width / aspect)
                let anchorPoint = imagePlacement.position.absolute(in: canvas)
                
                extras.append(ResolvedElement(id: element.id, content: .image(ResolvedImage(
                    center: deviceCenter(anchorPoint: anchorPoint, anchor: imagePlacement.anchor, size: imageSize, rotation: imagePlacement.rotation),
                    size: imageSize,
                    rotation: imagePlacement.rotation,
                    cornerRadius: imagePlacement.cornerRadius * width,
                    image: size == nil ? nil : name.map(ImageRef.asset)
                ))))
            default:
                continue
            }
        }
        
        return ResolvedScene(
            canvas: canvas,
            background: resolveFill(style.background[device], style: style, canvas: canvas),
            device: mainDevice,
            primary: primary,
            secondary: secondary,
            extras: extras,
            flags: flags
        )
    }
    
    /// A device and its capture: the bezel's frame, the bare capture, or a placeholder frame when the bezel is missing.
    static func resolveDevice(_ placement: DevicePlacement, key: String, request: ResolveRequest, flags: inout [SceneFlag]) -> ResolvedDevice {
        let device = request.target.deviceClass
        let canvas = request.canvas
        var capture: CaptureCatalog.Entry?
        
        // Capture, falling back to the source locale. An extra device with no key shows an empty screen.
        if !key.isEmpty {
            let address = CaptureAddress(key: key, deviceClass: device, locale: request.locale)
            let sourceAddress = CaptureAddress(key: key, deviceClass: device, locale: request.sourceLocale)
            capture = request.captures.entries[address]
            
            if capture == nil, address != sourceAddress, let fallback = request.captures.entries[sourceAddress] {
                capture = fallback
                flags.append(.captureFallbackLocale(address))
            } else if capture == nil {
                flags.append(.missingCapture(address))
            }
            
            if let capture {
                let classification = DeviceTable.standard.classify(width: capture.pixelWidth, height: capture.pixelHeight)
                
                if classification?.deviceClass != device {
                    flags.append(.captureSizeMismatch(address))
                }
                
                if !capture.quirksToReview.isEmpty {
                    flags.append(.quirkReview(address, quirks: capture.quirksToReview))
                }
            }
        }
        
        // Geometry: the size first, then the center from the anchor, which it rotates and scales around.
        let width = placement.width * canvas.width
        let rotation = placement.rotation
        let anchorPoint = placement.position.absolute(in: canvas)
        let screenAspect: Double = if let capture, capture.pixelHeight > 0 {
            Double(capture.pixelWidth) / Double(capture.pixelHeight)
        } else {
            request.target.aspectRatio
        }
        
        let bezel = request.bezels.bezel(for: placement.bezel, deviceClass: device, aspectRatio: request.target.aspectRatio)
        let frame: ResolvedDevice.Frame
        let size: CGSize
        let screen: CGRect
        let cornerRadius: Double
        
        if let bezel {
            let scale = width / Double(bezel.imageWidth)
            let rect = bezel.screenRect.cgRect
            frame = .bezel
            size = CGSize(width: width, height: Double(bezel.imageHeight) * scale)
            screen = CGRect(x: rect.minX * scale, y: rect.minY * scale, width: rect.width * scale, height: rect.height * scale)
            cornerRadius = 0
        } else if placement.bezel == .none {
            frame = .bare
            size = CGSize(width: width, height: width / screenAspect)
            screen = CGRect(origin: .zero, size: size)
            cornerRadius = placement.bareCornerRadius * width
        } else {
            let border = width * 0.035
            let screenWidth = width - border * 2
            let screenHeight = screenWidth / screenAspect
            frame = .placeholder
            size = CGSize(width: width, height: screenHeight + border * 2)
            screen = CGRect(x: border, y: border, width: screenWidth, height: screenHeight)
            cornerRadius = placement.bareCornerRadius * screenWidth
            
            if !flags.contains(.missingBezel(device)) {
                flags.append(.missingBezel(device))
            }
        }
        
        // Glow, in the device's shape, which moves and rotates with it.
        let glow = placement.glow.map { glow in
            ResolvedGlow(
                offset: CGPoint(x: glow.offset.x * canvas.width, y: glow.offset.y * canvas.height),
                blur: glow.blur * canvas.width,
                spread: glow.spread,
                color: request.style.color(glow.colorToken),
                opacity: glow.opacity
            )
        }
        
        return ResolvedDevice(
            center: deviceCenter(anchorPoint: anchorPoint, anchor: placement.anchor, size: size, rotation: rotation),
            size: size,
            rotation: rotation,
            screen: screen,
            screenCornerRadius: cornerRadius,
            frame: frame,
            capture: capture?.ref,
            captureSize: capture.map { CGSize(width: $0.pixelWidth, height: $0.pixelHeight) },
            bezel: bezel?.imageRef,
            mask: bezel?.maskRef,
            glow: glow
        )
    }
    
    /// Text in a text style at the style's size, in a placement, with a box as tall as the lines it wraps to.
    static func resolveText(_ string: String, style role: TextRole, placement: TextPlacement, element: ElementRef, request: ResolveRequest) -> ResolvedText {
        let device = request.target.deviceClass
        let canvas = request.canvas
        let textStyle = request.style.textStyle(role)
        let size = textStyle.size[device] * canvas.width
        let font = textStyle.font[device]
        let lineSpacing = textStyle.lineSpacing[device] * size
        let height = TextPlacement.height(
            lines: request.lineCounts[element] ?? 1,
            fontSize: size,
            lineHeight: request.lineHeights[font] ?? defaultLineHeight,
            lineSpacing: lineSpacing
        )
        
        return ResolvedText(
            role: role,
            string: applyCase(textStyle.letterCase[device], to: string, locale: request.locale),
            font: ResolvedFont(spec: font, size: size),
            color: request.style.color(textStyle.colorToken[device]),
            tracking: textStyle.tracking[device] * size,
            lineSpacing: lineSpacing,
            alignment: placement.alignment,
            verticalAlignment: placement.verticalAlignment,
            frame: placement.frame(in: canvas, height: height)
        )
    }
    
    // MARK: - Helpers
    
    /// The center of a device whose anchor point sits at a point, rotated around that point.
    public static func deviceCenter(anchorPoint: CGPoint, anchor: BoxAnchor, size: CGSize, rotation: Double) -> CGPoint {
        let offset = CGPoint(x: (0.5 - anchor.unit.x) * size.width, y: (0.5 - anchor.unit.y) * size.height)
        let rotated = rotate(offset, degrees: rotation)
        return CGPoint(x: anchorPoint.x + rotated.x, y: anchorPoint.y + rotated.y)
    }
    
    /// Where one of a device's anchor points is on the canvas.
    public static func devicePoint(_ anchor: BoxAnchor, center: CGPoint, size: CGSize, rotation: Double) -> CGPoint {
        let offset = CGPoint(x: (anchor.unit.x - 0.5) * size.width, y: (anchor.unit.y - 0.5) * size.height)
        let rotated = rotate(offset, degrees: rotation)
        return CGPoint(x: center.x + rotated.x, y: center.y + rotated.y)
    }
    
    /// A vector turned clockwise on screen (y points down).
    public static func rotate(_ point: CGPoint, degrees: Double) -> CGPoint {
        let radians = degrees * .pi / 180
        return CGPoint(x: point.x * cos(radians) - point.y * sin(radians), y: point.x * sin(radians) + point.y * cos(radians))
    }
    
    public static func applyCase(_ letterCase: LetterCase, to text: String, locale: LocaleID) -> String {
        let locale = Locale(identifier: locale)
        
        return switch letterCase {
        case .asWritten: text
        case .uppercase: text.uppercased(with: locale)
        case .lowercase: text.lowercased(with: locale)
        }
    }
    
    static func resolveFill(_ fill: Fill, style: Style, canvas: CGSize) -> ResolvedFill {
        switch fill {
        case let .color(token):
            .solid(style.color(token))
        case let .linearGradient(tokens, angle):
            .linear(tokens.map(style.color), angle: angle)
        case let .radialGradient(tokens, center, radius):
            .radial(tokens.map(style.color), center: center.absolute(in: canvas), radius: radius * canvas.width)
        }
    }
}
