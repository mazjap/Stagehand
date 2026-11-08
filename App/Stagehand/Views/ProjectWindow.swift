import StagehandCore
import SwiftUI
import UniformTypeIdentifiers

/// One open project: the sets and slides, the contact sheet or canvas, and the inspector.
struct ProjectWindow: View {
    private let document: any EditableDocument
    @State private var coordinator: ProjectCoordinator
    @State private var canvas: CanvasCoordinator
    
    #if os(macOS)
    @State private var runs: CaptureRunCoordinator
    #endif
    
    @State private var isInspectorPresented = true
    @Environment(\.undoManager) private var undoManager
    
    #if os(macOS)
    @Environment(\.dismissWindow) private var dismissWindow
    #endif
    
    init(document: any EditableDocument) {
        self.document = document
        let coordinator = ProjectCoordinator(document: document)
        coordinator.commitPendingEdits = PendingEdits.commit
        self.coordinator = coordinator
        self.canvas = CanvasCoordinator(project: coordinator)
        
        #if os(macOS)
        self.runs = CaptureRunCoordinator(project: coordinator)
        #endif
    }
    
    var body: some View {
        if let failure = document.loadFailure {
            UnreadableDocumentView(fileName: document.fileConfiguration?.fileURL?.lastPathComponent, failure: failure)
        } else {
            editor
        }
    }
    
    private var editor: some View {
        NavigationSplitView {
            SidebarView(coordinator: coordinator)
                .navigationSplitViewColumnWidth(min: 220, ideal: 260)
        } detail: {
            detail
                // NOTE: - Its own view's: SwiftUI honors one file importer per view, and the window has export's.
                .fileImporter(isPresented: isPresenting(.importScreenshots), allowedContentTypes: [.folder]) { result in
                    if case let .success(folder) = result {
                        let accessing = folder.startAccessingSecurityScopedResource()
                        coordinator.handle(.importScreenshotsFolder(folder))
                        
                        if accessing {
                            folder.stopAccessingSecurityScopedResource()
                        }
                    }
                }
                .inspector(isPresented: $isInspectorPresented) {
                    InspectorView(coordinator: coordinator, canvas: canvas, runs: runCoordinator)
                        .inspectorColumnWidth(min: 300, ideal: 340, max: 480)
                }
        }
        .toolbar {
            ProjectToolbar(coordinator: coordinator, runs: runCoordinator, isInspectorPresented: $isInspectorPresented)
        }
        .navigationTitle(coordinator.project.name)
        .focusedSceneValue(\.projectCoordinator, coordinator)
        .focusedSceneValue(\.canvasCoordinator, canvas)
        #if os(macOS)
        .focusedSceneValue(\.captureRunCoordinator, runs)
        #endif
        .task {
            #if os(macOS)
            dismissWindow(id: WelcomeWindow.id)
            #endif
            
            coordinator.undoManager = undoManager
            await coordinator.start()
        }
        #if os(macOS)
        .onChange(of: document.fileConfiguration?.fileURL, initial: true) { _, url in
            if let url {
                RecentDocuments.note(url)
            }
        }
        #endif
        .onChange(of: undoManager) { _, manager in
            coordinator.undoManager = manager
        }
        .onChange(of: document.loadGeneration) {
            coordinator.handle(.documentReloaded)
        }
        .onReceive(NotificationCenter.default.publisher(for: .stagehandBezelsChanged)) { _ in
            coordinator.handle(.reloadBezels)
        }
        .fileImporter(isPresented: isPresenting(.export), allowedContentTypes: [.folder]) { result in
            if case let .success(folder) = result {
                let accessing = folder.startAccessingSecurityScopedResource()
                coordinator.export(to: folder)
                
                if accessing {
                    folder.stopAccessingSecurityScopedResource()
                }
            }
        }
        .sheet(isPresented: isPresenting(.merge)) {
            MergeSheet(coordinator: coordinator)
        }
        .sheet(isPresented: isPresenting(.newProjectFromThis)) {
            NewProjectFromThisSheet(coordinator: coordinator, onDismiss: { coordinator.handle(.present(nil)) })
        }
        .sheet(isPresented: isPresenting(.searchPreview)) {
            SearchPreviewSheet(coordinator: coordinator, onDismiss: { coordinator.handle(.present(nil)) })
        }
        .sheet(isPresented: isPresenting(.upload)) {
            UploadSheet(project: coordinator, onDismiss: { coordinator.handle(.present(nil)) })
        }
        .sheet(isPresented: isPresenting(.issues)) {
            IssuesView(coordinator: coordinator, onDismiss: { coordinator.handle(.present(nil)) })
        }
        #if os(macOS)
        .sheet(isPresented: isPresenting(.appLink)) {
            AppLinkSheet(project: coordinator, onDismiss: { coordinator.handle(.present(nil)) })
        }
        .sheet(isPresented: isPresenting(.runLog)) {
            RunLogView(runs: runs, onDismiss: { coordinator.handle(.present(nil)) })
        }
        .alert("Unfold the iPhone Duo", item: Binding(get: { runs.prompt }, set: { if $0 == nil { runs.handle(.answerPrompt(false)) } })) { prompt in
            Button("Continue") { runs.handle(.answerPrompt(true)) }
            Button("Stop Run", role: .cancel) { runs.handle(.answerPrompt(false)) }
        } message: { prompt in
            switch prompt {
            case let .unfoldDuo(name, attempt):
                Text(attempt > 1
                    ? "\(name) still looks folded. Unfold it in Device Hub, then click Continue."
                    : "Unfold the \(name) simulator in Device Hub, then click Continue.")
            }
        }
        .alert(runs.alert?.title ?? "", item: Binding(get: { runs.alert }, set: { runs.alert = $0 })) { _ in
            Button("OK") {}
        } message: { alert in
            Text(alert.message)
        }
        #endif
        .alert(coordinator.alert?.title ?? "", item: $coordinator.alert) { _ in
            Button("OK") {}
        } message: { alert in
            Text(alert.message)
        }
    }
    
    @ViewBuilder
    private var detail: some View {
        if !coordinator.fontsReady {
            ProgressView("Loading fonts…")
        } else {
            switch coordinator.mode {
            case .contactSheet:
                ContactSheetView(coordinator: coordinator, runs: runCoordinator)
            case .canvas:
                CanvasView(coordinator: coordinator, canvas: canvas)
            }
        }
    }
    
    /// Style documents are never exported or captured, so they get no runs.
    private var runCoordinator: RunStatusSource? {
        #if os(macOS)
        document.kind == .project ? runs : nil
        #else
        nil
        #endif
    }
    
    private func isPresenting(_ presentation: ProjectCoordinator.Presentation) -> Binding<Bool> {
        Binding {
            coordinator.presentation == presentation
        } set: { isPresented in
            if !isPresented, coordinator.presentation == presentation {
                coordinator.handle(.present(nil))
            }
        }
    }
}

/// Shown in place of the editor when a document's file can't be read, so nothing can be edited and saved over it.
private struct UnreadableDocumentView: View {
    private let fileName: String?
    private let failure: DocumentError
    
    #if os(macOS)
    @Environment(\.dismissWindow) private var dismissWindow
    #endif
    
    init(fileName: String?, failure: DocumentError) {
        self.fileName = fileName
        self.failure = failure
    }
    
    var body: some View {
        ContentUnavailableView {
            Label(fileName.map { "Can't Open \($0)" } ?? "Can't Open This Document", systemImage: "exclamationmark.triangle")
        } description: {
            Text("The file wasn't changed. It may have been saved by a newer build of Stagehand, so try updating and opening it again.\n\n\(failure.errorDescription ?? String(describing: failure))")
                .textSelection(.enabled)
        }
        .frame(minWidth: 600, minHeight: 400)
        #if os(macOS)
        .task {
            dismissWindow(id: WelcomeWindow.id)
        }
        #endif
    }
}

#Preview {
    ProjectWindow(document: ProjectDocument(contents: ProjectContents(project: .fixture())))
        .frame(width: 1200, height: 800)
}

#Preview("Can't Be Read") {
    UnreadableDocumentView(fileName: "TrekPoint.stagehand", failure: .missingFile("project.json"))
}
