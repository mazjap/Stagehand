import StagehandCore
import SwiftUI

/// What views need from capture runs, so the iPad build (which can't capture) compiles the same views.
@MainActor
protocol RunStatusSource: AnyObject {
    var isRunning: Bool { get }
    var step: String? { get }
    func status(for cell: CellID) -> RunCellStatus?
    func resultBundle(for cell: CellID) -> URL?
    func runAll()
    func recapture(_ cell: CellID)
    func cancel()
}

#if os(macOS)
extension CaptureRunCoordinator: RunStatusSource {
    func runAll() {
        handle(.runAll)
    }
    
    func recapture(_ cell: CellID) {
        handle(.recapture(cell))
    }
    
    func cancel() {
        handle(.cancel)
    }
}
#endif
