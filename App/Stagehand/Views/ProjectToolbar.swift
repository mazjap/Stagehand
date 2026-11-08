import StagehandCore
import SwiftUI

struct ProjectToolbar: ToolbarContent {
    @Bindable private var coordinator: ProjectCoordinator
    private let runs: RunStatusSource?
    @Binding private var isInspectorPresented: Bool
    
    init(coordinator: ProjectCoordinator, runs: RunStatusSource?, isInspectorPresented: Binding<Bool>) {
        self.coordinator = coordinator
        self.runs = runs
        self._isInspectorPresented = isInspectorPresented
    }
    
    var body: some ToolbarContent {
        ToolbarItem(placement: .principal) {
            Picker("View", selection: Binding(get: { coordinator.mode }, set: { mode in
                coordinator.handle(mode == .canvas ? .showCanvas : .showContactSheet)
            })) {
                Label("Contact Sheet", systemImage: "square.grid.3x3").tag(ProjectCoordinator.Mode.contactSheet)
                Label("Canvas", systemImage: "rectangle.portrait").tag(ProjectCoordinator.Mode.canvas)
            }
            .pickerStyle(.segmented)
            .labelStyle(.iconOnly)
            .help("Contact Sheet (⌘1) or Canvas (⌘2)")
        }
        
        ToolbarItem {
            Picker("Locale", selection: Binding(get: { coordinator.selection.locale }, set: { coordinator.handle(.selectLocale($0)) })) {
                ForEach(coordinator.project.allLocales, id: \.self) { locale in
                    Text(locale).tag(locale)
                }
            }
            .help("Locale")
        }
        
        if let runs {
            ToolbarItem {
                if runs.isRunning {
                    Button {
                        runs.cancel()
                    } label: {
                        Label(runs.step ?? "Capturing", systemImage: "stop.circle")
                    }
                    .help("Stop the run (⌘.)")
                } else {
                    Button {
                        runs.runAll()
                    } label: {
                        Label("Run Captures", systemImage: "camera.viewfinder")
                    }
                    .help("Run every capture (⌘R)")
                }
            }
        }
        
        ToolbarItem {
            Button {
                coordinator.handle(.present(.issues))
            } label: {
                Label("Issues", systemImage: coordinator.issues.isEmpty ? "checkmark.seal" : "exclamationmark.triangle")
            }
            .help("Issues")
        }
        
        if coordinator.document.kind == .project {
            ToolbarItem {
                Button {
                    coordinator.handle(.present(.export))
                } label: {
                    Label("Export", systemImage: "square.and.arrow.up")
                }
                .help("Export every listing locale (⌘E)")
            }
        }
        
        ToolbarItem {
            Button {
                isInspectorPresented.toggle()
            } label: {
                Label("Inspector", systemImage: "sidebar.trailing")
            }
            .help("Show or hide the inspector")
        }
    }
}
