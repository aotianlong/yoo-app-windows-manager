import CoreGraphics
import XCTest
@testable import YooWindowsManagerCore

final class LayoutNodeTests: XCTestCase {
    func testHorizontalSplitProducesTwoFrames() {
        let a = WindowReference(windowID: 1, ownerPID: 10, ownerName: "A", title: "A")
        let b = WindowReference(windowID: 2, ownerPID: 20, ownerName: "B", title: "B")

        let root: LayoutNode = .split(
            direction: .horizontal,
            ratio: 0.5,
            first: .leaf(a),
            second: .leaf(b)
        )

        let area = CGRect(x: 0, y: 0, width: 1000, height: 800)
        let placements = root.resolvedPlacements(in: area)

        XCTAssertEqual(placements.count, 2)
        XCTAssertEqual(placements[0].frame.width, 500, accuracy: 0.1)
        XCTAssertEqual(placements[1].frame.minX, 500, accuracy: 0.1)
    }

    func testAutoLayoutProducesLeafPerWindow() {
        let engine = LayoutEngine()
        let windows = (1 ... 4).map {
            WindowReference(windowID: UInt32($0), ownerPID: Int32($0), ownerName: "A", title: "")
        }
        let root = engine.autoLayout(windows: windows)
        XCTAssertEqual(root.windowCount, 4)
        let frames = root.resolvedPlacements(in: CGRect(x: 0, y: 0, width: 1000, height: 800))
        XCTAssertEqual(frames.count, 4)
    }
}
