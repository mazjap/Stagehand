import StagehandCore
import SwiftUI

/// Picks a side for each value both the project and the library changed, then pulls the library's changes.
struct MergeSheet: View {
    @Bindable private var coordinator: ProjectCoordinator
    @State private var resolutions: [String: StyleMerge.Side] = [:]
    
    init(coordinator: ProjectCoordinator) {
        self.coordinator = coordinator
    }
    
    var body: some View {
        NavigationStack {
            Group {
                if let pending = coordinator.pendingMerge {
                    List(pending.result.conflicts) { conflict in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(StyleMerge.displayPath(conflict.path))
                                .font(.headline)
                            
                            Picker("Keep", selection: Binding(get: { resolutions[conflict.path] ?? .project }, set: { resolutions[conflict.path] = $0 })) {
                                Text("Project: \(Self.describe(conflict.project))").tag(StyleMerge.Side.project)
                                Text("Library: \(Self.describe(conflict.library))").tag(StyleMerge.Side.library)
                            }
                            .radioPickerStyle()
                            .labelsHidden()
                        }
                        .padding(.vertical, 4)
                    }
                } else {
                    ProgressView()
                }
            }
            .navigationTitle("Pull Template Set Changes")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { coordinator.handle(.cancelMerge) }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Pull Changes") { coordinator.handle(.applyMerge(resolutions)) }
                }
            }
        }
        .frame(minWidth: 520, minHeight: 400)
    }
    
    private static func describe(_ value: JSONValue?) -> String {
        guard let value else {
            return "none"
        }
        
        return switch value {
        case let .string(string): string
        case let .number(number): number.formatted()
        case let .bool(bool): bool ? "on" : "off"
        case .null: "none"
        default: (try? String(decoding: JSONEncoder().encode(value), as: UTF8.self)) ?? "a value"
        }
    }
}

#Preview {
    MergeSheet(coordinator: ProjectCoordinator(document: ProjectDocument(contents: ProjectContents(project: .fixture()))))
}
