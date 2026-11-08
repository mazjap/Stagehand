import CoreGraphics
import StagehandModel
import SwiftUI

/// Draws a ``ResolvedScene``: background, extra images and devices, the Main Device's glow, its capture clipped to the
/// bezel's screen and its bezel, primary text, secondary text, then extra text.
///
/// One view draws both the editor's canvas (scaled) and the export (through `ImageRenderer` at scale 1), so what's on
/// the canvas is what's exported.
///
/// > Warning: Keep this pure SwiftUI. `ImageRenderer` doesn't draw views backed by AppKit or UIKit.
public struct SceneView: View {
    private let scene: ResolvedScene
    private let images: SceneImages
    private let clipsToCanvas: Bool
    
    /// - Parameter clipsToCanvas: Whether anything past the canvas's edges is cut off, as it is in the export. The
    ///   editor also draws the scene unclipped and faded underneath, so what's dragged past an edge stays visible.
    public init(scene: ResolvedScene, images: SceneImages, clipsToCanvas: Bool = true) {
        self.scene = scene
        self.images = images
        self.clipsToCanvas = clipsToCanvas
    }
    
    public var body: some View {
        ZStack(alignment: .topLeading) {
            if clipsToCanvas {
                BackgroundLayer(fill: scene.background)
            }
            
            ForEach(scene.extrasBehind) { element in
                ElementLayer(element: element, images: images)
            }
            
            if let device = scene.device {
                DeviceWithGlow(device: device, images: images)
            }
            
            if let primary = scene.primary {
                TextLayer(text: primary)
            }
            
            if let secondary = scene.secondary {
                TextLayer(text: secondary)
            }
            
            ForEach(scene.extrasInFront) { element in
                ElementLayer(element: element, images: images)
            }
        }
        .frame(width: scene.canvas.width, height: scene.canvas.height, alignment: .topLeading)
        .modifier(CanvasClip(isOn: clipsToCanvas))
        .environment(\.colorScheme, .light)
    }
}

// MARK: - Layers

/// Cuts off whatever's past the canvas's edges, unless the editor wants to see it.
private struct CanvasClip: ViewModifier {
    let isOn: Bool
    
    func body(content: Content) -> some View {
        if isOn {
            content.clipped()
        } else {
            content
        }
    }
}

private struct DeviceWithGlow: View {
    let device: ResolvedDevice
    let images: SceneImages
    
    var body: some View {
        if let glow = device.glow {
            GlowLayer(glow: glow, device: device, images: images)
        }
        
        DeviceLayer(device: device, images: images)
    }
}

private struct ElementLayer: View {
    let element: ResolvedElement
    let images: SceneImages
    
    var body: some View {
        switch element.content {
        case let .text(text):
            TextLayer(text: text)
        case let .device(device):
            DeviceWithGlow(device: device, images: images)
        case let .image(image):
            ImageLayer(image: image, images: images)
        }
    }
}

/// An image element, or a placeholder when its asset is missing.
private struct ImageLayer: View {
    let image: ResolvedImage
    let images: SceneImages
    
    var body: some View {
        Group {
            if let cgImage = images[image.image] {
                Image(decorative: cgImage, scale: 1)
                    .resizable()
                    .interpolation(.high)
            } else {
                ZStack {
                    Rectangle().fill(Color(white: 0.5, opacity: 0.3))
                    
                    Image(systemName: "photo")
                        .font(.system(size: image.size.width * 0.3, weight: .light))
                        .foregroundStyle(Color(white: 0.4))
                }
            }
        }
        .frame(width: image.size.width, height: image.size.height)
        .clipShape(RoundedRectangle(cornerRadius: image.cornerRadius, style: .continuous))
        .rotationEffect(.degrees(image.rotation))
        .position(image.center)
    }
}

private struct BackgroundLayer: View {
    let fill: ResolvedFill
    
    var body: some View {
        switch fill {
        case let .solid(color):
            Rectangle().fill(color.color)
        case let .linear(colors, angle):
            let radians = angle * .pi / 180
            let dx = sin(radians) / 2
            let dy = cos(radians) / 2
            
            Rectangle().fill(
                LinearGradient(
                    colors: colors.map(\.color),
                    startPoint: UnitPoint(x: 0.5 - dx, y: 0.5 - dy),
                    endPoint: UnitPoint(x: 0.5 + dx, y: 0.5 + dy)
                )
            )
        case let .radial(colors, center, radius):
            GeometryReader { proxy in
                Rectangle().fill(
                    RadialGradient(
                        colors: colors.map(\.color),
                        center: UnitPoint(x: center.x / max(proxy.size.width, 1), y: center.y / max(proxy.size.height, 1)),
                        startRadius: 0,
                        endRadius: radius
                    )
                )
            }
        }
    }
}

/// The device's silhouette (its bezel and screen, or its rounded frame) in the glow's color, blurred.
private struct GlowLayer: View {
    let glow: ResolvedGlow
    let device: ResolvedDevice
    let images: SceneImages
    
    var body: some View {
        silhouette
            .frame(width: device.size.width, height: device.size.height)
            .scaleEffect(glow.spread)
            .blur(radius: glow.blur)
            .opacity(glow.opacity)
            .rotationEffect(.degrees(device.rotation))
            .position(x: device.center.x + glow.offset.x, y: device.center.y + glow.offset.y)
    }
    
    @ViewBuilder
    private var silhouette: some View {
        if let bezel = images[device.bezel] {
            Rectangle()
                .fill(glow.color.color)
                .mask {
                    ZStack {
                        Image(decorative: bezel, scale: 1).resizable()
                        
                        if let mask = images[device.mask] {
                            Image(decorative: mask, scale: 1).resizable()
                        }
                    }
                }
        } else {
            let radius = device.frame == .bare ? device.screenCornerRadius : device.screenCornerRadius + device.screen.minX
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(glow.color.color)
        }
    }
}

private struct DeviceLayer: View {
    let device: ResolvedDevice
    let images: SceneImages
    
    var body: some View {
        ZStack(alignment: .topLeading) {
            if device.frame == .placeholder {
                RoundedRectangle(cornerRadius: device.screenCornerRadius + device.screen.minX, style: .continuous)
                    .fill(Color(white: 0.08))
                    .overlay {
                        RoundedRectangle(cornerRadius: device.screenCornerRadius + device.screen.minX, style: .continuous)
                            .strokeBorder(Color(white: 0.32), lineWidth: max(device.screen.minX * 0.15, 1))
                    }
            }
            
            screenLayer
            
            if let bezel = images[device.bezel] {
                Image(decorative: bezel, scale: 1)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: device.size.width, height: device.size.height)
            }
        }
        .frame(width: device.size.width, height: device.size.height, alignment: .topLeading)
        .shadow(color: .black.opacity(device.frame == .bare ? 0.35 : 0), radius: device.size.width * 0.03, y: device.size.width * 0.015)
        .rotationEffect(.degrees(device.rotation))
        .position(device.center)
    }
    
    @ViewBuilder
    private var screenLayer: some View {
        let content = ZStack(alignment: .topLeading) {
            screenContent
                .frame(width: device.screen.width, height: device.screen.height)
                .clipShape(RoundedRectangle(cornerRadius: device.screenCornerRadius, style: .continuous))
                .offset(x: device.screen.minX, y: device.screen.minY)
        }
        .frame(width: device.size.width, height: device.size.height, alignment: .topLeading)
        
        if let mask = images[device.mask] {
            content.mask {
                Image(decorative: mask, scale: 1)
                    .resizable()
                    .frame(width: device.size.width, height: device.size.height)
            }
        } else {
            content
        }
    }
    
    @ViewBuilder
    private var screenContent: some View {
        if let capture = images[device.capture] {
            Image(decorative: capture, scale: 1)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fill)
                .frame(width: device.screen.width, height: device.screen.height)
                .clipped()
        } else {
            ZStack {
                Rectangle().fill(Color(white: 0.22))
                
                Image(systemName: "photo")
                    .font(.system(size: device.screen.width * 0.18, weight: .light))
                    .foregroundStyle(Color(white: 0.45))
            }
        }
    }
}

/// Text wraps to as many lines as it needs at its box's width. It takes its full height whatever the box's (which
/// is measured to match), so a line is never cut off or turned into an ellipsis.
private struct TextLayer: View {
    let text: ResolvedText
    
    var body: some View {
        Text(text.string)
            .font(text.font.font)
            .tracking(text.tracking)
            .lineSpacing(text.lineSpacing)
            .foregroundStyle(text.color.color)
            .multilineTextAlignment(text.alignment.textAlignment)
            .fixedSize(horizontal: false, vertical: true)
            // NOTE: - A line shorter than the box is narrower than this width, so the frame aligns it (alignment
            // within the text only aligns its lines against each other).
            .frame(width: text.frame.width, alignment: Alignment(horizontal: text.alignment.horizontalAlignment, vertical: .top))
            .frame(
                width: text.frame.width,
                height: text.frame.height,
                alignment: Alignment(horizontal: text.alignment.horizontalAlignment, vertical: text.verticalAlignment.verticalAlignment)
            )
            .position(x: text.frame.midX, y: text.frame.midY)
    }
}

#Preview {
    let project = Project.fixture()
    let slide = project.slides(in: project.mainLineup)[1]
    let scene = Resolver.resolve(
        ResolveRequest(
            slide: slide,
            style: project.style,
            target: DeviceTable.standard.target(id: "iphone-dynamic-island-large")!,
            locale: "en-US",
            sourceLocale: "en-US",
            captures: CaptureCatalog()
        )
    )
    
    SceneView(scene: scene, images: SceneImages())
        .scaleEffect(0.2)
        .frame(width: scene.canvas.width * 0.2, height: scene.canvas.height * 0.2)
}
