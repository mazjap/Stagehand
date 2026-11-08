import CoreGraphics
import Foundation
@testable import StagehandCore
import Testing

@Suite struct SnapperTests {
    private let canvas = CGSize(width: 1000, height: 2000)
    
    @Test func aCenterNearTheCanvasCenterSnapsToIt() {
        let rect = CGRect(x: 395, y: 100, width: 200, height: 50)
        let result = Snapper.snap(rect, to: Snapper.Targets(canvas: canvas, others: []), tolerance: 10)
        
        #expect(result.offset.width == 5)
        #expect(result.guides.contains(SnapGuide(axis: .vertical, position: 500)))
    }
    
    @Test func nothingWithinToleranceDoesNotSnap() {
        let rect = CGRect(x: 380, y: 100, width: 200, height: 50)
        let result = Snapper.snap(rect, to: Snapper.Targets(canvas: canvas, others: []), tolerance: 10)
        
        #expect(result.offset.width == 0)
        #expect(!result.guides.contains { $0.axis == .vertical })
    }
    
    @Test func edgesSnapToOtherElementsEdges() {
        let other = CGRect(x: 100, y: 300, width: 300, height: 40)
        let rect = CGRect(x: 103, y: 352, width: 120, height: 40)
        let result = Snapper.snap(rect, to: Snapper.Targets(canvas: canvas, others: [other]), tolerance: 6)
        
        #expect(result.offset.width == -3)
        #expect(result.guides.contains(SnapGuide(axis: .vertical, position: 100)))
    }
    
    @Test func onlyTheGivenEdgesSnap() {
        let rect = CGRect(x: 0, y: 0, width: 497, height: 10)
        let maxOnly = Snapper.snap(rect, xEdges: [.max], yEdges: [], to: Snapper.Targets(canvas: canvas, others: []), tolerance: 5)
        #expect(maxOnly.offset.width == 3)
        #expect(maxOnly.offset.height == 0)
    }
}
