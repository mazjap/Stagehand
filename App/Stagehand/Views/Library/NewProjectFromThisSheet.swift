import StagehandCore
import SwiftUI
import UniformTypeIdentifiers

/// Saves a new project carrying this one's style, and optionally its slide skeleton and text, then opens it.
struct NewProjectFromThisSheet: View {
    @Bindable private var coordinator: ProjectCoordinator
    private let onDismiss: () -> Void
    @State private var name = "Untitled"
    @State private var carrySkeleton = true
    @State private var carryText = false
    @State private var exported: ProjectDocument?
    @Environment(\.openURL) private var openURL
    
    init(coordinator: ProjectCoordinator, onDismiss: @escaping () -> Void) {
        self.coordinator = coordinator
        self.onDismiss = onDismiss
    }
    
    var body: some View {
        NavigationStack {
            Form {
                TextField("Name", text: $name)
                
                Section {
                    LabeledContent("Style", value: coordinator.project.style.name)
                    Toggle("Slide skeleton: the slides, their order, templates and capture keys", isOn: $carrySkeleton)
                    Toggle("Text", isOn: $carryText)
                        .disabled(!carrySkeleton)
                } footer: {
                    Text("Captures and the app link stay behind, since they belong to this app.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
            .navigationTitle("New Project from This")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onDismiss)
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save…") {
                        exported = ProjectDocument(contents: coordinator.derivedProject(name: name, carrySkeleton: carrySkeleton, carryText: carrySkeleton && carryText))
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .fileExporter(isPresented: Binding(get: { exported != nil }, set: { if !$0 { exported = nil } }), document: exported, contentType: .stagehandProject, defaultFilename: name) { result in
                if case let .success(url) = result {
                    openURL(url)
                    onDismiss()
                }
            }
        }
        .frame(minWidth: 460, minHeight: 300)
    }
}

#Preview {
    NewProjectFromThisSheet(coordinator: ProjectCoordinator(document: ProjectDocument(contents: ProjectContents(project: .fixture()))), onDismiss: {})
}
