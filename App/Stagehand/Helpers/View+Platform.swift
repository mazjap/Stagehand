import SwiftUI

extension View {
    /// The iPad pointer's hover effect. The Mac has none, so it's a no-op there.
    func pointerHoverEffect() -> some View {
        #if os(iOS)
        hoverEffect()
        #else
        self
        #endif
    }
}

extension View {
    /// Tracks held modifier keys on the Mac. The iPad has no equivalent yet, so it's a no-op there.
    func trackingModifiers(_ mask: EventModifiers, into modifiers: Binding<EventModifiers>) -> some View {
        #if os(macOS)
        onModifierKeysChanged(mask: mask) { _, new in
            modifiers.wrappedValue = new
        }
        #else
        // TODO: - Give the iPad a way to turn snapping off, like a toolbar toggle.
        self
        #endif
    }
}

extension View {
    /// Radio buttons on the Mac, and an inline list on the iPad, which has none.
    func radioPickerStyle() -> some View {
        #if os(macOS)
        pickerStyle(.radioGroup)
        #else
        pickerStyle(.inline)
        #endif
    }
}

extension View {
    /// Scrolling over the view on the Mac: with ⌘ held it zooms (`onZoom` gets a factor and the pointer, in points
    /// from the view's center), and otherwise it pans (`onPan` gets how far the content should move, in points).
    ///
    /// The iPad has no scroll wheel, so it's a no-op there.
    func canvasScrolling(onPan: @escaping (CGSize) -> Void, onZoom: @escaping (Double, CGPoint) -> Void) -> some View {
        #if os(macOS)
        modifier(ScrollWheelModifier(onPan: onPan, onZoom: onZoom))
        #else
        // TODO: - Give the iPad a way to pan a zoomed canvas, like a two-finger drag.
        self
        #endif
    }
}

#if os(macOS)
import AppKit

private struct ScrollWheelModifier: ViewModifier {
    private let onPan: (CGSize) -> Void
    private let onZoom: (Double, CGPoint) -> Void
    @State private var monitor: ScrollWheelMonitor
    
    init(onPan: @escaping (CGSize) -> Void, onZoom: @escaping (Double, CGPoint) -> Void) {
        self.onPan = onPan
        self.onZoom = onZoom
        self.monitor = ScrollWheelMonitor()
    }
    
    func body(content: Content) -> some View {
        // NOTE: - The monitor isn't observed, so updating its callbacks here doesn't redraw anything.
        monitor.onPan = onPan
        monitor.onZoom = onZoom
        
        return content
            .onContinuousHover { phase in
                switch phase {
                case let .active(location): monitor.pointer = location
                case .ended: monitor.pointer = nil
                }
            }
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { monitor.frame = $0 }
            .onAppear { monitor.start() }
            .onDisappear { monitor.stop() }
    }
}

/// Watches the app's scroll wheel events and takes the ones over its view.
///
/// SwiftUI has no scroll wheel event of its own on the Mac, so this is an `NSEvent` monitor. It only takes an event
/// while the pointer is over the view, and never one meant for a sheet or a window with a sheet open.
@MainActor
private final class ScrollWheelMonitor {
    var pointer: CGPoint?
    var frame: CGRect = .zero
    var onPan: (CGSize) -> Void = { _ in }
    var onZoom: (Double, CGPoint) -> Void = { _, _ in }
    private var token: Any?
    
    /// How much one point of ⌘-scrolling zooms.
    private static let zoomPerPoint = 0.01
    
    /// A mouse wheel's deltas are in lines, and a trackpad's in points.
    private static let pointsPerLine = 10.0
    
    func start() {
        guard token == nil else {
            return
        }
        
        token = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            let window = event.window
            let isOverView = window.map { $0.attachedSheet == nil && $0.sheetParent == nil } ?? false
            let location = window?.contentView.map { CGPoint(x: event.locationInWindow.x, y: $0.bounds.height - event.locationInWindow.y) }
            let perLine = event.hasPreciseScrollingDeltas ? 1 : Self.pointsPerLine
            let delta = CGSize(width: event.scrollingDeltaX * perLine, height: event.scrollingDeltaY * perLine)
            let zooms = event.modifierFlags.contains(.command)
            
            let handled = MainActor.assumeIsolated {
                guard isOverView, let location else {
                    return false
                }
                
                return self?.handle(delta: delta, zooms: zooms, at: location) ?? false
            }
            
            return handled ? nil : event
        }
    }
    
    func stop() {
        if let token {
            NSEvent.removeMonitor(token)
        }
        
        token = nil
    }
    
    private func handle(delta: CGSize, zooms: Bool, at location: CGPoint) -> Bool {
        guard pointer != nil, frame.contains(location) else {
            return false
        }
        
        if zooms {
            onZoom(exp(delta.height * Self.zoomPerPoint), CGPoint(x: location.x - frame.midX, y: location.y - frame.midY))
        } else {
            onPan(delta)
        }
        
        return true
    }
}
#endif
