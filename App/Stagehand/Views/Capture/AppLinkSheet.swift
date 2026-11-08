#if os(macOS)
import StagehandCore
import StagehandModel
import SwiftUI

/// Links a project to an app's Xcode project: its scheme, test target and a simulator for each device class.
struct AppLinkSheet: View {
    @State private var coordinator: AppLinkCoordinator
    @State private var isChoosingProject = false
    private let onDismiss: () -> Void
    
    init(project: ProjectCoordinator, onDismiss: @escaping () -> Void) {
        self.onDismiss = onDismiss
        self.coordinator = AppLinkCoordinator(project: project)
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Xcode Project") {
                    LabeledContent("Project") {
                        HStack {
                            Text(coordinator.projectURL?.lastPathComponent ?? "None")
                                .foregroundStyle(coordinator.projectURL == nil ? .secondary : .primary)
                            Button("Choose…") { isChoosingProject = true }
                        }
                    }
                    
                    if coordinator.isLoading {
                        ProgressView().controlSize(.small)
                    }
                    
                    Picker("Scheme", selection: Binding(get: { coordinator.draft?.scheme ?? "" }, set: { coordinator.handle(.setScheme($0)) })) {
                        Text("None").tag("")
                        ForEach(coordinator.schemes, id: \.self) { Text($0).tag($0) }
                    }
                    .disabled(coordinator.draft == nil)
                    
                    Picker("Test Target", selection: Binding(get: { coordinator.draft?.testTarget ?? "" }, set: { coordinator.handle(.setTestTarget($0)) })) {
                        Text("None").tag("")
                        ForEach(coordinator.targets, id: \.self) { Text($0).tag($0) }
                    }
                    .disabled(coordinator.draft == nil)
                    
                    Toggle("Override the Status Bar", isOn: Binding(get: { coordinator.draft?.overridesStatusBar ?? true }, set: { coordinator.handle(.setOverridesStatusBar($0)) }))
                        .help("Turn this off when the app hides the status bar itself.")
                }
                
                ForEach(coordinator.otherPlatforms, id: \.self) { platform in
                    Section(platform.rawValue) {
                        Picker("Scheme", selection: Binding(get: { coordinator.draft?.platformSchemes?[platform.rawValue] ?? "" }, set: { coordinator.handle(.setPlatformScheme(platform, $0)) })) {
                            Text("Same as Above").tag("")
                            ForEach(coordinator.schemes, id: \.self) { Text($0).tag($0) }
                        }
                        
                        Picker("Test Target", selection: Binding(get: { coordinator.draft?.platformTestTargets?[platform.rawValue] ?? "" }, set: { coordinator.handle(.setPlatformTestTarget(platform, $0)) })) {
                            Text("Same as Above").tag("")
                            ForEach(coordinator.targets, id: \.self) { Text($0).tag($0) }
                        }
                    }
                    .disabled(coordinator.draft == nil)
                }
                
                Section("Simulators") {
                    ForEach(coordinator.deviceClasses, id: \.self) { device in
                        SimulatorPicker(coordinator: coordinator, device: device)
                    }
                    
                    Text("Captures run on Stagehand's own simulators, named \"Stagehand …\". Your simulators are never touched.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                if let error = coordinator.errorMessage {
                    Text(error)
                        .foregroundStyle(.red)
                        .font(.callout)
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Link App")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onDismiss)
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        coordinator.handle(.save)
                        onDismiss()
                    }
                    .disabled(!coordinator.canSave)
                }
            }
            .fileImporter(isPresented: $isChoosingProject, allowedContentTypes: AppLinkCoordinator.projectTypes) { result in
                if case let .success(url) = result {
                    coordinator.handle(.chooseProject(url))
                }
            }
        }
        .frame(minWidth: 560, minHeight: 560)
        .task { coordinator.handle(.load) }
    }
}

private struct SimulatorPicker: View {
    @Bindable private var coordinator: AppLinkCoordinator
    private let device: DeviceClass
    
    init(coordinator: AppLinkCoordinator, device: DeviceClass) {
        self.coordinator = coordinator
        self.device = device
    }
    
    var body: some View {
        let spec = coordinator.draft?.simulators[device]
        
        VStack(alignment: .leading) {
            Picker(device.displayName, selection: Binding(get: { spec?.deviceType ?? "" }, set: { type in
                let runtime = coordinator.runtimes(for: type).last?.identifier ?? ""
                coordinator.handle(.setSimulator(device, type.isEmpty ? nil : SimulatorSpec(deviceType: type, runtime: runtime, developerDir: spec?.developerDir)))
            })) {
                Text("None").tag("")
                ForEach(coordinator.deviceTypes(for: device)) { type in
                    Text(type.name).tag(type.identifier)
                }
            }
            
            if let spec {
                Picker("Runtime", selection: Binding(get: { spec.runtime }, set: { runtime in
                    coordinator.handle(.setSimulator(device, SimulatorSpec(deviceType: spec.deviceType, runtime: runtime, developerDir: spec.developerDir)))
                })) {
                    ForEach(coordinator.runtimes(for: spec.deviceType)) { runtime in
                        Text(runtime.name).tag(runtime.identifier)
                    }
                }
                
                TextField("Developer Directory", text: Binding(get: { spec.developerDir ?? "" }, set: { dir in
                    coordinator.handle(.setSimulator(device, SimulatorSpec(deviceType: spec.deviceType, runtime: spec.runtime, developerDir: dir.isEmpty ? nil : dir)))
                }), prompt: Text("The selected Xcode"))
            }
        }
    }
}

#Preview {
    AppLinkSheet(project: ProjectCoordinator(document: ProjectDocument(contents: ProjectContents(project: .fixture()))), onDismiss: {})
}
#endif
