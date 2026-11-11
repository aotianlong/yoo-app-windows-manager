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

    func testSpiralLayoutFiveWindows() {
        let engine = LayoutEngine()
        let windows = makeWindows(count: 5)
        let frames = dictionary(engine.autoLayout(windows: windows).resolvedPlacements(in: area))

        assertEqual(frames[1], CGRect(x: 0, y: 0, width: 500, height: 800))
        assertEqual(frames[2], CGRect(x: 500, y: 400, width: 500, height: 400))
        assertEqual(frames[3], CGRect(x: 500, y: 0, width: 250, height: 400))
        assertEqual(frames[4], CGRect(x: 750, y: 200, width: 250, height: 200))
        assertEqual(frames[5], CGRect(x: 750, y: 0, width: 250, height: 200))
    }

    func testWorkspaceAddsTenPointGapBetweenWindows() {
        let windows = makeWindows(count: 2)
        let root = LayoutEngine().autoLayout(windows: windows)
        let workspace = LayoutWorkspace(
            id: "screen",
            screenName: "screen",
            usableFrame: area,
            root: root
        )
        let frames = dictionary(workspace.placements())

        assertEqual(frames[1], CGRect(x: 5, y: 5, width: 490, height: 790))
        assertEqual(frames[2], CGRect(x: 505, y: 5, width: 490, height: 790))
        XCTAssertEqual(frames[2]!.minX - frames[1]!.maxX, 10, accuracy: 0.1)
    }

    func testWorkspaceSupportsIndependentScreenEdgeGap() {
        let root = LayoutEngine().autoLayout(windows: makeWindows(count: 2))
        let workspace = LayoutWorkspace(
            id: "screen",
            screenName: "screen",
            usableFrame: area,
            root: root
        )
        let frames = dictionary(workspace.placements(windowGap: 10, edgeGap: 20))

        assertEqual(frames[1], CGRect(x: 20, y: 20, width: 475, height: 760))
        assertEqual(frames[2], CGRect(x: 505, y: 20, width: 475, height: 760))
        XCTAssertEqual(frames[2]!.minX - frames[1]!.maxX, 10, accuracy: 0.1)
    }

    func testResizingFirstWindowMovesHorizontalDivider() {
        let root = LayoutEngine().autoLayout(windows: makeWindows(count: 2))
        let resized = root.adjustingSplitRatios(
            for: 1,
            expectedFrame: CGRect(x: 0, y: 0, width: 500, height: 800),
            projectedFrame: CGRect(x: 0, y: 0, width: 650, height: 800),
            in: area
        )
        let frames = dictionary(resized.resolvedPlacements(in: area))

        assertEqual(frames[1], CGRect(x: 0, y: 0, width: 650, height: 800))
        assertEqual(frames[2], CGRect(x: 650, y: 0, width: 350, height: 800))
    }

    func testResizingLowerWindowMovesVerticalDivider() {
        let root = LayoutEngine().autoLayout(windows: makeWindows(count: 3))
        let resized = root.adjustingSplitRatios(
            for: 3,
            expectedFrame: CGRect(x: 500, y: 0, width: 500, height: 400),
            projectedFrame: CGRect(x: 500, y: 0, width: 500, height: 300),
            in: area
        )
        let frames = dictionary(resized.resolvedPlacements(in: area))

        assertEqual(frames[1], CGRect(x: 0, y: 0, width: 500, height: 800))
        assertEqual(frames[2], CGRect(x: 500, y: 300, width: 500, height: 500))
        assertEqual(frames[3], CGRect(x: 500, y: 0, width: 500, height: 300))
    }

    func testCoordinateConversionFlipsAroundMainScreenTop() {
        let cocoaFrame = CGRect(x: 0, y: 90, width: 1280, height: 1320)

        let accessibilityFrame = ScreenCoordinateConverter.flipVertically(
            cocoaFrame,
            mainScreenMaxY: 1440
        )

        assertEqual(accessibilityFrame, CGRect(x: 0, y: 30, width: 1280, height: 1320))
        assertEqual(
            ScreenCoordinateConverter.flipVertically(accessibilityFrame, mainScreenMaxY: 1440),
            cocoaFrame
        )
    }

    func testCoordinateConversionSupportsDisplayAboveMainScreen() {
        let cocoaFrame = CGRect(x: 0, y: 1440, width: 1920, height: 1080)

        let accessibilityFrame = ScreenCoordinateConverter.flipVertically(
            cocoaFrame,
            mainScreenMaxY: 1440
        )

        assertEqual(accessibilityFrame, CGRect(x: 0, y: -1080, width: 1920, height: 1080))
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

    private func assertEqual(_ actual: CGRect, _ expected: CGRect, file: StaticString = #file, line: UInt = #line) {
        assertEqual(Optional(actual), expected, file: file, line: line)
    }
}
