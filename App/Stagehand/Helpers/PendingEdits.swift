#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// Ends a text field's edit in progress, which commits it. `ProjectCoordinator` calls this before the selection
/// changes (``ProjectCoordinator/commitPendingEdits``), so a typed value lands on what it was typed for.
@MainActor
enum PendingEdits {
    static func commit() {
        #if os(macOS)
        // NOTE: - Only while a field is editing (its field editor is the first responder), so the canvas keeps the
        // focus that its arrow keys need.
        guard let window = NSApp.keyWindow, window.firstResponder is NSTextView else {
            return
        }
        
        window.makeFirstResponder(nil)
        #else
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        #endif
    }
}
