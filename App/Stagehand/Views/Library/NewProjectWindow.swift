#if os(macOS)
import StagehandCore
import StagehandModel
import SwiftUI

/// Chooses what a new project starts with: its devices (iPhone alone by default; more can be added later), and a
/// template set (a built-in starter, one from the library, or a blank one to design from scratch).
struct NewProjectWindow: View {
    static let id = "new-project"
    
    /// What the template set comes from.
    enum Source: Hashable {
        case starter(StarterTemplateSet)
        case library(LibraryStyle.ID)
        case scratch
    }
    
    private let picker: NewProjectPicker
    @State private var library: LibraryCoordinator
    @State private var devices: Set<DeviceClass>
    @State private var source: Source?
    @Environment(\.dismissWindow) private var dismissWindow
    
    init(picker: NewProjectPicker) {
        self.picker = picker
        self.library = LibraryCoordinator()
        self.devices = [.phone]
        self.source = .starter(.darkGlow)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("New Project")
                .font(.title2.bold())
            
            VStack(alignment: .leading, spacing: 6) {
                Text("Devices")
                    .font(.headline)
                
                HStack(spacing: 14) {
                    ForEach(DeviceClass.allCases, id: \.self) { device in
                        Toggle(device.displayName, isOn: Binding(get: { devices.contains(device) }, set: { on in
                            if on {
                                devices.insert(device)
                            } else if devices.count > 1 {
                                devices.remove(device)
                            }
                        }))
                        .toggleStyle(.checkbox)
                    }
                }
                
                Text("Start with the devices you're ready for. Add more later from the Project inspector.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            VStack(alignment: .leading, spacing: 6) {
                Text("Template Set")
                    .font(.headline)
                
                List(selection: $source) {
                    Section("Starters") {
                        ForEach(StarterTemplateSet.allCases) { starter in
                            VStack(alignment: .leading, spacing: 2) {
                                Label(starter.name, systemImage: "rectangle.on.rectangle")
                                
                                Text(starter.summary)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .tag(Source.starter(starter))
                        }
                    }
                    
                    if !library.styles.isEmpty {
                        Section("Your Library") {
                            ForEach(library.styles) { style in
                                Label("\(style.name) (version \(style.version))", systemImage: "paintpalette")
                                    .tag(Source.library(style.id))
                            }
                        }
                    }
                    
                    Section {
                        VStack(alignment: .leading, spacing: 2) {
                            Label("Start from Scratch", systemImage: "square.dashed")
                            
                            Text("One blank template to design. Make as many as you like before adding slides.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .tag(Source.scratch)
                    }
                }
                .frame(minHeight: 260)
            }
            
            HStack {
                Spacer()
                
                Button("Cancel", role: .cancel) {
                    picker.cancel()
                    dismissWindow(id: Self.id)
                }
                .keyboardShortcut(.cancelAction)
                
                Button("Create") { create() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!picker.isWaiting || source == nil)
            }
        }
        .padding(20)
        .frame(width: 560)
        .task { library.handle(.load) }
        .onDisappear { picker.cancel() }
        .alert(library.alert?.title ?? "", item: $library.alert) { _ in
            Button("OK") {}
        } message: { alert in
            Text(alert.message)
        }
    }
    
    private func create() {
        let devices = DeviceClass.allCases.filter(devices.contains)
        
        do {
            let contents: ProjectContents
            
            switch source {
            case let .starter(starter):
                contents = ProjectContents(project: .empty(devices: devices, style: starter.style()))
            case let .library(id):
                guard let style = library.styles.first(where: { $0.id == id }) else { return }
                contents = try library.newProject(from: style, devices: devices)
            case .scratch, nil:
                contents = ProjectContents(project: .empty(devices: devices))
            }
            
            // The new templates keep the bezels they're made with.
            picker.finish(with: library.pinningBezels(contents))
            dismissWindow(id: Self.id)
        } catch {
            library.alert = CoordinatorAlert(title: "Couldn't Use This Template Set", error: error)
        }
    }
}

#Preview {
    NewProjectWindow(picker: NewProjectPicker())
}
#endif
