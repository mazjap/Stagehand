import StagehandCore
import SwiftUI

@main
struct StagehandApp: App {
    @State private var newProject = NewProjectPicker()
    
    #if os(macOS)
    @Environment(\.openWindow) private var openWindow
    #endif
    
    init() {
        #if os(macOS)
        // NOTE: - Stagehand always opens to the Welcome window, never to the last session's documents, whatever the
        // system's "Close windows when quitting an application" setting says. Setting this in the app's own domain
        // overrides the system's.
        UserDefaults.standard.set(false, forKey: "NSQuitAlwaysKeepsWindows")
        #endif
    }
    
    var body: some Scene {
        DocumentGroup { (document: ProjectDocument) in
            ProjectWindow(document: document)
        } makeDocument: { configuration, _ in
            #if os(macOS)
            // NOTE: - SwiftUI calls this for opened and restored files too, so only a creation the New Project command
            // asked for waits on the New Project window.
            let document = try await newProject.makeDocument {
                openWindow(id: NewProjectWindow.id)
            }
            #else
            let document = ProjectDocument()
            #endif
            
            document.fileConfiguration = configuration
            return document
        }
        .commands {
            ProjectCommands(newProject: newProject)
        }
        
        DocumentGroup { (document: StyleDocument) in
            ProjectWindow(document: document)
        } makeDocument: { configuration, _ in
            let document = StyleDocument()
            document.fileConfiguration = configuration
            return document
        }
        
        #if os(macOS)
        // NOTE: - Presented at launch, which keeps the system's open panel from showing instead. Like Xcode's, it has no
        // title bar or window buttons (it has its own close button) and drags by its background. It isn't `.plain`:
        // that's a borderless window, which can't become key (so no keyboard), has no shadow and doesn't drag.
        Window("Welcome to Stagehand", id: WelcomeWindow.id) {
            WelcomeWindow(newProject: newProject)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .windowBackgroundDragBehavior(.enabled)
        .defaultWindowPlacement { _, context in
            WindowPlacement(.center)
        }
        .defaultLaunchBehavior(.presented)
        .restorationBehavior(.disabled)
        .commands {
            CommandGroup(after: .windowArrangement) {
                Button("Welcome to Stagehand") {
                    openWindow(id: WelcomeWindow.id)
                }
                .keyboardShortcut("1", modifiers: [.command, .shift])
            }
        }
        
        // NOTE: - Never restored: it only means something while a new project's creation waits on it.
        Window("New Project", id: NewProjectWindow.id) {
            NewProjectWindow(picker: newProject)
        }
        .windowResizability(.contentSize)
        .restorationBehavior(.disabled)
        #endif
        
        #if os(macOS)
        Window("Library", id: LibraryWindow.id) {
            LibraryWindow()
        }
        
        Settings {
            SettingsView()
        }
        #else
        WindowGroup("Library", id: LibraryWindow.id) {
            LibraryWindow()
        }
        #endif
    }
}

