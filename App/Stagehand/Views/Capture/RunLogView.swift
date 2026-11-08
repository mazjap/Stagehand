#if os(macOS)
import StagehandCore
import SwiftUI

/// The current or last run's step and `xcodebuild` output.
struct RunLogView: View {
    @Bindable private var runs: CaptureRunCoordinator
    private let onDismiss: () -> Void
    
    init(runs: CaptureRunCoordinator, onDismiss: @escaping () -> Void) {
        self.runs = runs
        self.onDismiss = onDismiss
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                Text(runs.log.isEmpty ? "Nothing has run yet." : runs.log)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
            }
            .defaultScrollAnchor(.bottom)
            .navigationTitle(runs.step ?? (runs.isRunning ? "Running" : "Run Log"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Clear") { runs.handle(.clearLog) }
                        .disabled(runs.isRunning)
                }
                
                if runs.isRunning {
                    ToolbarItem {
                        Button("Stop Run") { runs.handle(.cancel) }
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", action: onDismiss)
                }
            }
        }
        .frame(minWidth: 720, minHeight: 480)
    }
}

#Preview {
    RunLogView(runs: CaptureRunCoordinator(project: ProjectCoordinator(document: ProjectDocument(contents: ProjectContents(project: .fixture())))), onDismiss: {})
}
#endif
