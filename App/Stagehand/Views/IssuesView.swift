import StagehandCore
import SwiftUI

/// Every flagged cell, plus the set-level checks.
struct IssuesView: View {
    @Bindable private var coordinator: ProjectCoordinator
    private let onDismiss: () -> Void
    
    init(coordinator: ProjectCoordinator, onDismiss: @escaping () -> Void) {
        self.coordinator = coordinator
        self.onDismiss = onDismiss
    }
    
    var body: some View {
        let issues = coordinator.issues.sorted { $0.severity > $1.severity }
        
        NavigationStack {
            Group {
                if issues.isEmpty {
                    ContentUnavailableView("No Issues", systemImage: "checkmark.seal", description: Text("Every cell has its text, capture and bezel."))
                } else {
                    List(issues) { issue in
                        Button {
                            if let cell = issue.cell {
                                coordinator.handle(.selectCell(cell))
                                onDismiss()
                            }
                        } label: {
                            Label {
                                Text(issue.message)
                                    .foregroundStyle(.primary)
                            } icon: {
                                Image(systemName: issue.severity == .error ? "exclamationmark.triangle.fill" : "exclamationmark.circle.fill")
                                    .foregroundStyle(issue.severity == .error ? .red : .orange)
                            }
                        }
                        .buttonStyle(.plain)
                        .pointerHoverEffect()
                        .disabled(issue.cell == nil)
                    }
                }
            }
            .navigationTitle("Issues")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", action: onDismiss)
                }
            }
        }
        .frame(minWidth: 520, minHeight: 420)
    }
}

#Preview {
    IssuesView(coordinator: ProjectCoordinator(document: ProjectDocument(contents: ProjectContents(project: .fixture()))), onDismiss: {})
}
