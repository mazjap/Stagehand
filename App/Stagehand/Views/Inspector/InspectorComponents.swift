import StagehandCore
import StagehandModel
import SwiftUI

/// The inspector's column widths, so every row lines up.
enum InspectorMetrics {
    static let labelWidth: Double = 84
    static let badgeWidth: Double = 18
    static let valueWidth: Double = 52
    static let rowSpacing: Double = 8
}

/// A titled group in the inspector, with a divider above it.
struct InspectorSection<Content: View>: View {
    private let title: String
    private let content: Content
    
    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: InspectorMetrics.rowSpacing) {
            Text(title)
                .font(.headline)
                .padding(.bottom, 2)
            
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// One inspector row: a fixed-width label, a control that fills the middle, and a slot for a link badge.
struct InspectorRow<Content: View, Badge: View>: View {
    private let label: String
    private let content: Content
    private let badge: Badge
    
    init(_ label: String, @ViewBuilder content: () -> Content, @ViewBuilder badge: () -> Badge) {
        self.label = label
        self.content = content()
        self.badge = badge()
    }
    
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(label)
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(width: InspectorMetrics.labelWidth, alignment: .leading)
            
            content
                .frame(maxWidth: .infinity, alignment: .leading)
            
            badge
                .frame(width: InspectorMetrics.badgeWidth)
        }
    }
}

extension InspectorRow where Badge == EmptyView {
    init(_ label: String, @ViewBuilder content: () -> Content) {
        self.init(label, content: content, badge: { EmptyView() })
    }
}

/// A number field with a unit, filling its row's control column.
struct NumberField: View {
    private let label: String
    @Binding private var value: Double
    private let digits: Int
    private let unit: String?
    
    init(_ label: String, value: Binding<Double>, digits: Int = 3, unit: String? = nil) {
        self.label = label
        self._value = value
        self.digits = digits
        self.unit = unit
    }
    
    var body: some View {
        InspectorRow(label) {
            // Half the column, like each field of a pair, so single and paired fields line up.
            HStack(spacing: 6) {
                HStack(spacing: 3) {
                    TextField(label, value: $value, format: .number.precision(.fractionLength(0...digits)))
                        .labelsHidden()
                        .multilineTextAlignment(.trailing)
                        .monospacedDigit()
                    
                    if let unit {
                        Text(unit)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity)
                
                Spacer()
                    .frame(maxWidth: .infinity)
            }
        }
    }
}

/// Two number fields side by side, like X and Y.
struct PairField: View {
    private let label: String
    private let first: (name: String, value: Binding<Double>)
    private let second: (name: String, value: Binding<Double>)?
    private let digits: Int
    
    init(_ label: String, _ firstName: String, _ first: Binding<Double>, _ secondName: String, _ second: Binding<Double>?, digits: Int = 0) {
        self.label = label
        self.first = (firstName, first)
        self.second = second.map { (secondName, $0) }
        self.digits = digits
    }
    
    var body: some View {
        InspectorRow(label) {
            HStack(spacing: 6) {
                field(first.name, first.value)
                
                if let second {
                    field(second.name, second.value)
                } else {
                    Spacer().frame(maxWidth: .infinity)
                }
            }
        }
    }
    
    private func field(_ name: String, _ value: Binding<Double>) -> some View {
        HStack(spacing: 3) {
            Text(name)
                .font(.caption)
                .foregroundStyle(.secondary)
            
            TextField(name, value: value, format: .number.precision(.fractionLength(0...digits)))
                .labelsHidden()
                .multilineTextAlignment(.trailing)
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity)
    }
}

/// A slider with its value shown at a fixed width.
struct SliderField: View {
    /// How a slider's value reads in its number field: multiplied by `scale`, with `digits` decimals and a unit.
    struct Display {
        var scale: Double
        var digits: Int
        var unit: String
        
        /// A fraction shown as a percentage, like 85%.
        static func percent(digits: Int = 1) -> Display {
            Display(scale: 100, digits: digits, unit: "%")
        }
        
        /// A fraction of the canvas's width shown in points on a canvas this wide, like 158 pt.
        static func points(canvasWidth: Double, digits: Int = 0) -> Display {
            Display(scale: canvasWidth, digits: digits, unit: "pt")
        }
    }
    
    @Binding private var value: Double
    private let range: ClosedRange<Double>
    private let typedRange: ClosedRange<Double>
    private let display: Display
    private let onEditing: (Bool) -> Void
    
    /// - Parameters:
    ///   - range: What the slider covers.
    ///   - typedRange: What a typed number is kept to: the slider's range unless given, so a value only the field can
    ///     reach (like a larger font) is still possible.
    init(
        value: Binding<Double>,
        in range: ClosedRange<Double>,
        typedRange: ClosedRange<Double>? = nil,
        display: Display = .percent(),
        onEditing: @escaping (Bool) -> Void = { _ in }
    ) {
        self._value = value
        self.range = range
        self.typedRange = typedRange ?? range
        self.display = display
        self.onEditing = onEditing
    }
    
    /// A percentage with `digits` decimals.
    init(value: Binding<Double>, in range: ClosedRange<Double>, digits: Int, onEditing: @escaping (Bool) -> Void = { _ in }) {
        self.init(value: value, in: range, display: .percent(digits: digits), onEditing: onEditing)
    }
    
    var body: some View {
        HStack(spacing: 6) {
            Slider(value: Binding(get: { min(max(value, range.lowerBound), range.upperBound) }, set: { value = $0 }), in: range, onEditingChanged: onEditing)
                .controlSize(.small)
            
            HStack(spacing: 2) {
                TextField("Value", value: typed, format: .number.precision(.fractionLength(0...display.digits)))
                    .labelsHidden()
                    .multilineTextAlignment(.trailing)
                    .monospacedDigit()
                    .controlSize(.small)
                
                Text(display.unit)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(width: InspectorMetrics.valueWidth + 10)
        }
    }
    
    /// The value in the field's units, kept to `typedRange` when it's typed.
    private var typed: Binding<Double> {
        Binding {
            value * display.scale
        } set: { shown in
            let raw = shown / max(display.scale, .ulpOfOne)
            value = min(max(raw, typedRange.lowerBound), typedRange.upperBound)
        }
    }
}

/// The nine points of a box, one of which places it.
struct AnchorGrid: View {
    private let selection: BoxAnchor
    private let onSelect: (BoxAnchor) -> Void
    
    init(selection: BoxAnchor, onSelect: @escaping (BoxAnchor) -> Void) {
        self.selection = selection
        self.onSelect = onSelect
    }
    
    var body: some View {
        let rows: [[BoxAnchor]] = [
            [.topLeading, .top, .topTrailing],
            [.leading, .center, .trailing],
            [.bottomLeading, .bottom, .bottomTrailing],
        ]
        
        Grid(horizontalSpacing: 0, verticalSpacing: 0) {
            ForEach(rows, id: \.self) { row in
                GridRow {
                    ForEach(row, id: \.self) { anchor in
                        Button {
                            onSelect(anchor)
                        } label: {
                            RoundedRectangle(cornerRadius: 1.5)
                                .fill(anchor == selection ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary.opacity(0.35)))
                                .frame(width: 8, height: 8)
                                .frame(width: 18, height: 18)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .pointerHoverEffect()
                        .accessibilityLabel(anchor.displayName)
                        .accessibilityAddTraits(anchor == selection ? .isSelected : [])
                        .help(anchor.displayName)
                    }
                }
            }
        }
        .padding(3)
        .background(RoundedRectangle(cornerRadius: 4).strokeBorder(.separator))
    }
}

/// Every font: the system font's weights, the document's fonts, then every installed family.
struct FontMenu: View {
    private let selection: FontSpec
    private let documentFonts: [String]
    private let families: [FontFamily]
    private let onSelect: (FontSpec) -> Void
    
    init(selection: FontSpec, documentFonts: [String], families: [FontFamily], onSelect: @escaping (FontSpec) -> Void) {
        self.selection = selection
        self.documentFonts = documentFonts
        self.families = families
        self.onSelect = onSelect
    }
    
    var body: some View {
        Menu {
            Section("System") {
                ForEach([FontSpec.systemRegular, .systemMedium, .systemBold, .systemHeavy], id: \.self) { spec in
                    button(spec.displayName, spec)
                }
            }
            
            if !documentFonts.isEmpty {
                Section("In This Document") {
                    ForEach(documentFonts, id: \.self) { name in
                        button(name, FontSpec(postScriptName: name))
                    }
                }
            }
            
            Section("All Fonts") {
                ForEach(families) { family in
                    if family.faces.count == 1, let face = family.faces.first {
                        button(family.name, FontSpec(postScriptName: face.postScriptName))
                    } else {
                        Menu(family.name) {
                            ForEach(family.faces) { face in
                                button(face.styleName, FontSpec(postScriptName: face.postScriptName))
                            }
                        }
                    }
                }
            }
        } label: {
            Text(selection.displayName)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    private func button(_ title: String, _ spec: FontSpec) -> some View {
        Button {
            onSelect(spec)
        } label: {
            if spec == selection {
                Label(title, systemImage: "checkmark")
            } else {
                Text(title)
            }
        }
    }
}

#Preview {
    VStack(alignment: .leading, spacing: 8) {
        InspectorSection("Arrange") {
            InspectorRow("Anchor") {
                AnchorGrid(selection: .top, onSelect: { _ in })
            }
            
            PairField("Position", "X", .constant(660), "Y", .constant(158))
            NumberField("Width", value: .constant(1108), digits: 0, unit: "px")
            
            InspectorRow("Size") {
                SliderField(value: .constant(0.085), in: 0.01...0.2)
            }
        }
    }
    .padding()
    .frame(width: 320)
}
