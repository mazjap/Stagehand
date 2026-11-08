#if os(macOS)
import AppKit
import StagehandCore
import SwiftUI

/// Shown at launch instead of the bare open panel, like Xcode's: the app's icon and version, Open…, New Project
/// (with New Template Set in its menu), and the recent documents. Double-click or Return opens one.
///
/// It closes when a document window appears (``ProjectWindow`` dismisses it), so cancelling New Project leaves it open.
struct WelcomeWindow: View {
    static let id = "welcome"
    
    private let newProject: NewProjectPicker
    @State private var recents: [URL]
    @State private var selection: URL?
    @FocusState private var isListFocused: Bool
    @Environment(\.openDocument) private var openDocument
    @Environment(\.newDocument) private var newDocument
    @Environment(\.dismissWindow) private var dismissWindow
    
    init(newProject: NewProjectPicker) {
        self.newProject = newProject
        self.recents = []
        self.selection = nil
    }
    
    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.top, 12)
            
            actions
                .padding(.top, 22)
                .padding(.horizontal, 24)
            
            recentList
                .padding([.horizontal, .bottom], 24)
                .padding(.top, 18)
        }
        // NOTE: - This sits under the hidden title bar's 32 points, so the window is 600 tall.
        .frame(width: 460, height: 568)
        // NOTE: - There's no title bar to drag, so anything that isn't a control drags the window. Buttons and the
        // list keep their own clicks, since a child's gesture wins over this one.
        .contentShape(.rect)
        .gesture(WindowDragGesture())
        .allowsWindowActivationEvents(true)
        .overlay(alignment: .topLeading) {
            closeButton
                .padding(16)
                .ignoresSafeArea()
        }
        .background(WelcomeWindowChrome())
        .onAppear {
            recents = RecentDocuments.urls
            selection = recents.first
            isListFocused = true
        }
    }
    
    // MARK: - Subviews
    
    private var closeButton: some View {
        Button {
            dismissWindow(id: Self.id)
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: 13, weight: .semibold))
                .frame(width: 30, height: 30)
                .background(.quaternary, in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .focusable(false)
        .keyboardShortcut(.cancelAction)
        .accessibilityLabel("Close")
        .help("Close")
    }
    
    private var header: some View {
        VStack(spacing: 6) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 112, height: 112)
                .accessibilityHidden(true)
            
            Text("Stagehand")
                .font(.title.bold())
            
            Text(Self.version)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }
    
    private var actions: some View {
        HStack(spacing: 10) {
            Button {
                NSDocumentController.shared.openDocument(nil)
            } label: {
                Text("Open…")
                    .padding(.horizontal, 28)
            }
            
            Menu {
                Button("New Template Set") { newDocument(contentType: .stagehandStyle) }
            } label: {
                Text("New Project")
                    .padding(.horizontal, 8)
            } primaryAction: {
                newProject.requestNewProject()
                newDocument(contentType: .stagehandProject)
            }
            .menuStyle(.button)
            .fixedSize()
        }
        .buttonStyle(.bordered)
        .buttonBorderShape(.capsule)
        .controlSize(.extraLarge)
    }
    
    @ViewBuilder
    private var recentList: some View {
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
        
        Group {
            if recents.isEmpty {
                ContentUnavailableView("No Recent Projects", systemImage: "clock", description: Text("Projects and template sets you open show up here."))
            } else {
                List(recents, id: \.self, selection: $selection) { url in
                    RecentRow(url: url)
                }
                .focused($isListFocused)
                .listStyle(.inset(alternatesRowBackgrounds: false))
                .scrollContentBackground(.hidden)
                .contextMenu(forSelectionType: URL.self) { urls in
                    if let url = urls.first {
                        Button("Open") { open(url) }
                        Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
                    }
                } primaryAction: { urls in
                    if let url = urls.first {
                        open(url)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.quaternary.opacity(0.5), in: shape)
        .clipShape(shape)
    }
    
    // MARK: - Helpers
    
    /// "Version 1.0 (1)", from the bundle.
    private static var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = info?["CFBundleVersion"] as? String
        return build.map { "Version \(short) (\($0))" } ?? "Version \(short)"
    }
    
    private func open(_ url: URL) {
        Task {
            try? await openDocument(at: url)
            dismissWindow(id: Self.id)
        }
    }
}

/// Hides the window's title and its close, minimize and zoom buttons, since the Welcome window has its own close
/// button, and lets its background drag it.
private struct WelcomeWindowChrome: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        ChromeView()
    }
    
    func updateNSView(_ view: NSView, context: Context) {}
    
    private final class ChromeView: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            
            guard let window else {
                return
            }
            
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            window.isMovableByWindowBackground = true
            
            for button in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
                window.standardWindowButton(button)?.isHidden = true
            }
        }
    }
}

/// A recent document: its Finder icon, its name, and its folder (shortened from the front, like Xcode's).
private struct RecentRow: View {
    private let url: URL
    
    init(url: URL) {
        self.url = url
    }
    
    var body: some View {
        HStack(spacing: 10) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path(percentEncoded: false)))
                .resizable()
                .frame(width: 32, height: 32)
                .accessibilityHidden(true)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(url.deletingPathExtension().lastPathComponent)
                    .font(.headline)
                    .lineLimit(1)
                
                Text(RecentDocuments.folder(of: url))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.head)
            }
        }
        .padding(.vertical, 4)
        .help(url.path(percentEncoded: false))
    }
}

/// The system's recent documents, which also fill File › Open Recent. Every document window notes its file here,
/// since SwiftUI's `Document` apps don't on their own.
enum RecentDocuments {
    /// Recent documents that still exist, newest first.
    static var urls: [URL] {
        var seen = Set<URL>()
        return NSDocumentController.shared.recentDocumentURLs.filter { url in
            FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) && seen.insert(url.standardizedFileURL).inserted
        }
    }
    
    static func note(_ url: URL) {
        NSDocumentController.shared.noteNewRecentDocumentURL(url)
    }
    
    /// The folder a document is in, with the home folder as `~`.
    static func folder(of url: URL) -> String {
        (url.deletingLastPathComponent().path(percentEncoded: false) as NSString).abbreviatingWithTildeInPath
    }
}

#Preview {
    WelcomeWindow(newProject: NewProjectPicker())
}
#endif
