import StagehandCore
import StagehandModel
import SwiftUI

/// One row for any `Varying` value: its control, with a link badge when it's shared across classes, or a dot
/// when it's overridden for the class being viewed, and Override for <class> or Revert to Shared.
struct VaryingRow<Content: View>: View {
    private let label: String
    private let isOverridden: Bool
    private let deviceClass: DeviceClass
    private let onOverride: () -> Void
    private let onRevert: () -> Void
    private let content: Content
    
    init(
        _ label: String,
        isOverridden: Bool,
        deviceClass: DeviceClass,
        onOverride: @escaping () -> Void,
        onRevert: @escaping () -> Void,
        @ViewBuilder content: () -> Content
    ) {
        self.label = label
        self.isOverridden = isOverridden
        self.deviceClass = deviceClass
        self.onOverride = onOverride
        self.onRevert = onRevert
        self.content = content()
    }
    
    var body: some View {
        InspectorRow(label) {
            content
        } badge: {
            Menu {
                if isOverridden {
                    Button("Revert to Shared", action: onRevert)
                } else {
                    Button("Override for \(deviceClass.displayName)", action: onOverride)
                }
            } label: {
                Image(systemName: isOverridden ? "circle.fill" : "link")
                    .font(isOverridden ? .system(size: 7) : .caption)
                    .foregroundStyle(isOverridden ? AnyShapeStyle(.tint) : AnyShapeStyle(.tertiary))
                    .frame(width: InspectorMetrics.badgeWidth, height: 16)
                    .contentShape(Rectangle())
            }
            .menuStyle(.button)
            .buttonStyle(.borderless)
            .menuIndicator(.hidden)
            .fixedSize()
            .accessibilityLabel(isOverridden ? "Overridden for \(deviceClass.displayName)" : "Shared across devices")
            .help(isOverridden ? "Overridden for \(deviceClass.displayName). Click to revert." : "Shared across devices. Click to override for \(deviceClass.displayName).")
        }
    }
}

#Preview {
    VStack {
        VaryingRow("Size", isOverridden: false, deviceClass: .pad, onOverride: {}, onRevert: {}) {
            Slider(value: .constant(0.5))
        }
        
        VaryingRow("Font", isOverridden: true, deviceClass: .pad, onOverride: {}, onRevert: {}) {
            Text("System Heavy")
        }
    }
    .padding()
    .frame(width: 300)
}
