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

    func testSplitCurrentFromEmptyCreatesLeaf() {
        let w = WindowReference(windowID: 9, ownerPID: 1, ownerName: "X", title: "T")
        let node = LayoutNode.empty.splitCurrent(inserting: w, direction: .horizontal)
        if case let .leaf(ref) = node {
            XCTAssertEqual(ref.windowID, 9)
        } else {
            XCTFail("应生成 leaf")
        }
    }

    func testRebalanceUsesHalfRatio() {
        var ws = LayoutWorkspace(id: "1", screenName: "Main", usableFrame: CGRect(x: 0, y: 0, width: 1200, height: 900))
        let w1 = WindowReference(windowID: 1, ownerPID: 1, ownerName: "A", title: "")
        let w2 = WindowReference(windowID: 2, ownerPID: 2, ownerName: "B", title: "")
        ws.apply(split: .horizontal, to: w1, ratio: 0.7)
        ws.root = ws.root.splitCurrent(inserting: w2, direction: .vertical, ratio: 0.3)
        ws.rebalance()
        if case let .split(_, ratio, _, _) = ws.root {
            XCTAssertEqual(ratio, 0.5, accuracy: 0.0001)
        } else {
            XCTFail("根节点应为 split")
        }
    }
}
