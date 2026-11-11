import CoreGraphics
import XCTest
@testable import YooWindowsManagerCore

final class LayoutNodeTests: XCTestCase {
    private let area = CGRect(x: 0, y: 0, width: 1000, height: 800)

    func testHorizontalSplitProducesTwoFrames() {
        let a = WindowReference(windowID: 1, ownerPID: 10, ownerName: "A", title: "A")
        let b = WindowReference(windowID: 2, ownerPID: 20, ownerName: "B", title: "B")

        let root: LayoutNode = .split(
            direction: .horizontal,
            ratio: 0.5,
            first: .leaf(a),
            second: .leaf(b)
        )

        let placements = root.resolvedPlacements(in: area)

        XCTAssertEqual(placements.count, 2)
        XCTAssertEqual(placements[0].frame.width, 500, accuracy: 0.1)
        XCTAssertEqual(placements[1].frame.minX, 500, accuracy: 0.1)
    }

    func testSpiralLayoutTwoWindowsSideBySide() {
        let engine = LayoutEngine()
        let windows = makeWindows(count: 2)
        let frames = dictionary(engine.autoLayout(windows: windows).resolvedPlacements(in: area))

        assertEqual(frames[1], CGRect(x: 0, y: 0, width: 500, height: 800))
        assertEqual(frames[2], CGRect(x: 500, y: 0, width: 500, height: 800))
    }

    func testSpiralLayoutThreeWindows() {
        let engine = LayoutEngine()
        let windows = makeWindows(count: 3)
        let frames = dictionary(engine.autoLayout(windows: windows).resolvedPlacements(in: area))

        assertEqual(frames[1], CGRect(x: 0, y: 0, width: 500, height: 800))
        assertEqual(frames[2], CGRect(x: 500, y: 400, width: 500, height: 400))
        assertEqual(frames[3], CGRect(x: 500, y: 0, width: 500, height: 400))
    }

    func testSpiralLayoutFourWindows() {
        let engine = LayoutEngine()
        let windows = makeWindows(count: 4)
        let frames = dictionary(engine.autoLayout(windows: windows).resolvedPlacements(in: area))

        assertEqual(frames[1], CGRect(x: 0, y: 0, width: 500, height: 800))
        assertEqual(frames[2], CGRect(x: 500, y: 400, width: 500, height: 400))
        assertEqual(frames[3], CGRect(x: 500, y: 0, width: 250, height: 400))
        assertEqual(frames[4], CGRect(x: 750, y: 0, width: 250, height: 400))
    }

    private func makeWindows(count: Int) -> [WindowReference] {
        (1 ... count).map {
            WindowReference(windowID: UInt32($0), ownerPID: Int32($0), ownerName: "A", title: "")
        }
    }

    private func dictionary(_ placements: [WindowPlacement]) -> [UInt32: CGRect] {
        Dictionary(uniqueKeysWithValues: placements.map { ($0.window.windowID, $0.frame) })
    }

    private func assertEqual(_ actual: CGRect?, _ expected: CGRect, file: StaticString = #file, line: UInt = #line) {
        guard let actual else {
            XCTFail("缺少窗口 frame", file: file, line: line)
            return
        }
        XCTAssertEqual(actual.origin.x, expected.origin.x, accuracy: 0.5, file: file, line: line)
        XCTAssertEqual(actual.origin.y, expected.origin.y, accuracy: 0.5, file: file, line: line)
        XCTAssertEqual(actual.size.width, expected.size.width, accuracy: 0.5, file: file, line: line)
        XCTAssertEqual(actual.size.height, expected.size.height, accuracy: 0.5, file: file, line: line)
    }
}
