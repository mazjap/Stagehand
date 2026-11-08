import StagehandCore
import SwiftUI

extension FocusedValues {
    /// The coordinator of the frontmost project window, for menu commands.
    @Entry var projectCoordinator: ProjectCoordinator?
    
    /// The frontmost project window's canvas, for the View menu's zoom commands.
    @Entry var canvasCoordinator: CanvasCoordinator?
    
    #if os(macOS)
    @Entry var captureRunCoordinator: CaptureRunCoordinator?
    #endif
}
