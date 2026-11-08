import StagehandCore
import SwiftUI

/// The menu commands for the frontmost project, with their keyboard shortcuts.
struct ProjectCommands: Commands {
    @FocusedValue(\.projectCoordinator) private var coordinator
    @FocusedValue(\.canvasCoordinator) private var canvas
    
    #if os(macOS)
    @FocusedValue(\.captureRunCoordinator) private var runs
    #endif
    
    @Environment(\.openWindow) private var openWindow
    
    #if os(macOS)
    @Environment(\.newDocument) private var newDocument
    #endif
    
    private let newProject: NewProjectPicker
    
    init(newProject: NewProjectPicker) {
        self.newProject = newProject
    }
    
    var body: some Commands {
        #if os(macOS)
        // NOTE: - New Project has to say it's a new project: `makeDocument` can't tell it from an opened file.
        CommandGroup(replacing: .newItem) {
            Button("New Project…") {
                newProject.requestNewProject()
                newDocument(contentType: .stagehandProject)
            }
            .keyboardShortcut("n")
            
            Button("New Template Set") {
                newDocument(contentType: .stagehandStyle)
            }
            .keyboardShortcut("n", modifiers: [.command, .option])
        }
        #endif
        
        CommandGroup(after: .importExport) {
            let isProject = coordinator?.document.kind == .project
            
            Button("Export Screenshots…") {
                coordinator?.handle(.present(.export))
            }
            .keyboardShortcut("e")
            .disabled(!isProject)
            
            Button("Upload to App Store Connect…") {
                coordinator?.handle(.present(.upload))
            }
            .disabled(!isProject)
            
            Divider()
            
            Button("Save Template Set to Library") {
                coordinator?.handle(.saveStyleToLibrary(asNewVersion: coordinator?.project.basedOn != nil))
            }
            .disabled(coordinator == nil)
            
            Button("Save Template Set to Library as New") {
                coordinator?.handle(.saveStyleToLibrary(asNewVersion: false))
            }
            .disabled(coordinator == nil)
            
            Button("New Project from This…") {
                coordinator?.handle(.present(.newProjectFromThis))
            }
            .disabled(coordinator == nil)
        }
        
        CommandGroup(before: .sidebar) {
            let isOnCanvas = coordinator?.mode == .canvas
            
            Button("Zoom In") {
                canvas?.handle(.zoomIn)
            }
            .keyboardShortcut("+")
            .disabled(!isOnCanvas)
            
            Button("Zoom Out") {
                canvas?.handle(.zoomOut)
            }
            .keyboardShortcut("-")
            .disabled(!isOnCanvas)
            
            Button("Zoom to Fit") {
                canvas?.handle(.zoomToFit)
            }
            .keyboardShortcut("0")
            .disabled(!isOnCanvas)
            
            Divider()
            
            Toggle("Preview", isOn: Binding(get: { canvas?.isPreviewing ?? false }, set: { canvas?.handle(.setPreviewing($0)) }))
                .keyboardShortcut("p", modifiers: [.command, .option])
                .disabled(!isOnCanvas)
            
            Divider()
        }
        
        CommandMenu("Slide") {
            Button("New Slide") {
                coordinator?.handle(.addSlide())
            }
            .keyboardShortcut("n", modifiers: [.command, .shift])
            .disabled(coordinator?.currentSet == nil)
            
            Button("Duplicate Slide") {
                coordinator?.handle(.duplicateSlide)
            }
            .keyboardShortcut("d")
            .disabled(coordinator?.currentSlide == nil)
            
            Divider()
            
            Button("Contact Sheet") {
                coordinator?.handle(.showContactSheet)
            }
            .keyboardShortcut("1")
            
            Button("Canvas") {
                coordinator?.handle(.showCanvas)
            }
            .keyboardShortcut("2")
            
            Divider()
            
            Button("Issues") {
                coordinator?.handle(.present(.issues))
            }
            .keyboardShortcut("i", modifiers: [.command, .shift])
            
            Button("Search Preview") {
                coordinator?.handle(.present(.searchPreview))
            }
            .keyboardShortcut("p", modifiers: [.command, .shift])
        }
        
        CommandMenu("Template") {
            Button("New Template") {
                coordinator?.handle(.addTemplate(duplicating: nil))
            }
            .keyboardShortcut("n", modifiers: [.command, .option, .shift])
            .disabled(coordinator == nil)
            
            Button("Edit Slide's Template") {
                if let coordinator, let slide = coordinator.currentSlide {
                    let device = coordinator.currentDeviceClass
                    
                    if let template = Resolver.layout(for: slide, style: coordinator.project.style, device: device).template {
                        coordinator.handle(.selectTemplate(template.id))
                    }
                }
            }
            .keyboardShortcut("t", modifiers: [.command, .option])
            .disabled(coordinator?.currentSlide == nil || coordinator?.isEditingTemplate == true)
            
            Button("Back to Slide") {
                coordinator?.handle(.selectTemplate(nil))
            }
            .keyboardShortcut(.escape, modifiers: [.command])
            .disabled(coordinator?.isEditingTemplate != true)
        }
        
        #if os(macOS)
        CommandMenu("Capture") {
            Button("Run Captures") {
                runs?.handle(.runAll)
            }
            .keyboardShortcut("r")
            .disabled(runs == nil || runs?.isRunning == true || coordinator?.document.kind != .project)
            
            Button("Stop Run") {
                runs?.handle(.cancel)
            }
            .keyboardShortcut(".")
            .disabled(runs?.isRunning != true)
            
            Divider()
            
            Button("Import Screenshots Folder…") {
                coordinator?.handle(.present(.importScreenshots))
            }
            .disabled(coordinator?.document.kind != .project)
            
            Divider()
            
            Button("Link App…") {
                coordinator?.handle(.present(.appLink))
            }
            
            Button("Show Run Log") {
                coordinator?.handle(.present(.runLog))
            }
        }
        #endif
        
        CommandGroup(after: .windowArrangement) {
            Button("Library") {
                openWindow(id: LibraryWindow.id)
            }
            .keyboardShortcut("l", modifiers: [.command, .shift])
        }
    }
}
