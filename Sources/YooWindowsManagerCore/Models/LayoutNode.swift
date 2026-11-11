import CoreGraphics
import Foundation

/// 二分树布局节点：要么承载一个窗口，要么按方向与比例继续二分。
public indirect enum LayoutNode: Codable, Sendable, Equatable {
    case empty
    case leaf(WindowReference)
    case split(
        direction: SplitDirection,
        ratio: Double,
        first: LayoutNode,
        second: LayoutNode
    )

    public static let defaultRatio: Double = 0.5

    public var windowCount: Int {
        switch self {
        case .empty:
            return 0
        case .leaf:
            return 1
        case let .split(_, _, first, second):
            return first.windowCount + second.windowCount
        }
    }

    public var containsEmpty: Bool {
        switch self {
        case .empty:
            return true
        case .leaf:
            return false
        case let .split(_, _, first, second):
            return first.containsEmpty || second.containsEmpty
        }
    }

    /// 将当前叶子替换为二分节点，原窗口移到 first，新窗口在 second。
    public func splitCurrent(
        inserting newWindow: WindowReference,
        direction: SplitDirection,
        ratio: Double = LayoutNode.defaultRatio
    ) -> LayoutNode {
        switch self {
        case .empty:
            return .leaf(newWindow)
        case let .leaf(existing):
            return .split(
                direction: direction,
                ratio: clampRatio(ratio),
                first: .leaf(existing),
                second: .leaf(newWindow)
            )
        case let .split(dir, existingRatio, first, second):
            if first.containsEmpty {
                return .split(direction: dir, ratio: existingRatio, first: first.splitCurrent(inserting: newWindow, direction: direction, ratio: ratio), second: second)
            }
            if second.containsEmpty {
                return .split(direction: dir, ratio: existingRatio, first: first, second: second.splitCurrent(inserting: newWindow, direction: direction, ratio: ratio))
            }
            return .split(
                direction: direction,
                ratio: clampRatio(ratio),
                first: .leaf(newWindow),
                second: .split(direction: dir, ratio: existingRatio, first: first, second: second)
            )
        }
    }

    /// 根据屏幕区域递归计算每个窗口应占据的 frame。
    public func resolvedPlacements(in area: CGRect) -> [WindowPlacement] {
        switch self {
        case .empty:
            return []
        case let .leaf(window):
            return [WindowPlacement(window: window, frame: area)]
        case let .split(direction, ratio, first, second):
            let r = clampRatio(ratio)
            switch direction {
            case .horizontal:
                let w = area.width * r
                let left = CGRect(x: area.minX, y: area.minY, width: w, height: area.height)
                let right = CGRect(x: area.minX + w, y: area.minY, width: area.width - w, height: area.height)
                return first.resolvedPlacements(in: left) + second.resolvedPlacements(in: right)
            case .vertical:
                let h = area.height * r
                let lower = CGRect(x: area.minX, y: area.minY, width: area.width, height: area.height - h)
                let upper = CGRect(x: area.minX, y: area.maxY - h, width: area.width, height: h)
                return first.resolvedPlacements(in: upper) + second.resolvedPlacements(in: lower)
            }
        }
    }

    /// 根据用户实际拖动后的窗口边缘，更新与该窗口直接相邻的二分线。
    /// `expectedFrame` 和 `projectedFrame` 都是不含窗口间距的布局坐标。
    public func adjustingSplitRatios(
        for windowID: UInt32,
        expectedFrame: CGRect,
        projectedFrame: CGRect,
        in area: CGRect,
        edgeTolerance: CGFloat = 2
    ) -> LayoutNode {
        switch self {
        case .empty, .leaf:
            return self
        case let .split(direction, ratio, first, second):
            let originalRatio = clampRatio(ratio)
            let (originalFirstArea, originalSecondArea) = splitAreas(
                direction: direction,
                ratio: originalRatio,
                area: area
            )
            let isInFirst = first.contains(windowID: windowID)
            let isInSecond = second.contains(windowID: windowID)
            guard isInFirst || isInSecond else { return self }

            var adjustedRatio = originalRatio
            switch direction {
            case .horizontal:
                let boundary = originalFirstArea.maxX
                if isInFirst, abs(expectedFrame.maxX - boundary) <= edgeTolerance {
                    adjustedRatio = clampRatio(Double((projectedFrame.maxX - area.minX) / area.width))
                } else if isInSecond, abs(expectedFrame.minX - boundary) <= edgeTolerance {
                    adjustedRatio = clampRatio(Double((projectedFrame.minX - area.minX) / area.width))
                }
            case .vertical:
                let boundary = originalFirstArea.minY
                if isInFirst, abs(expectedFrame.minY - boundary) <= edgeTolerance {
                    adjustedRatio = clampRatio(Double((area.maxY - projectedFrame.minY) / area.height))
                } else if isInSecond, abs(expectedFrame.maxY - boundary) <= edgeTolerance {
                    adjustedRatio = clampRatio(Double((area.maxY - projectedFrame.maxY) / area.height))
                }
            }

            let adjustedFirst = isInFirst
                ? first.adjustingSplitRatios(
                    for: windowID,
                    expectedFrame: expectedFrame,
                    projectedFrame: projectedFrame,
                    in: originalFirstArea,
                    edgeTolerance: edgeTolerance
                )
                : first
            let adjustedSecond = isInSecond
                ? second.adjustingSplitRatios(
                    for: windowID,
                    expectedFrame: expectedFrame,
                    projectedFrame: projectedFrame,
                    in: originalSecondArea,
                    edgeTolerance: edgeTolerance
                )
                : second

            return .split(
                direction: direction,
                ratio: adjustedRatio,
                first: adjustedFirst,
                second: adjustedSecond
            )
        }
    }

    public func contains(windowID: UInt32) -> Bool {
        switch self {
        case .empty:
            return false
        case let .leaf(window):
            return window.windowID == windowID
        case let .split(_, _, first, second):
            return first.contains(windowID: windowID) || second.contains(windowID: windowID)
        }
    }

    public func replacing(windowID: UInt32, with newWindow: WindowReference) -> LayoutNode {
        switch self {
        case .empty:
            return self
        case let .leaf(existing):
            if existing.windowID == windowID {
                return .leaf(newWindow)
            }
            return self
        case let .split(direction, ratio, first, second):
            return .split(
                direction: direction,
                ratio: ratio,
                first: first.replacing(windowID: windowID, with: newWindow),
                second: second.replacing(windowID: windowID, with: newWindow)
            )
        }
    }

    public func removing(windowID: UInt32) -> LayoutNode {
        switch self {
        case .empty:
            return .empty
        case let .leaf(existing):
            return existing.windowID == windowID ? .empty : self
        case let .split(direction, ratio, first, second):
            let nf = first.removing(windowID: windowID)
            let ns = second.removing(windowID: windowID)
            return Self.collapse(direction: direction, ratio: ratio, first: nf, second: ns)
        }
    }

    private static func collapse(
        direction: SplitDirection,
        ratio: Double,
        first: LayoutNode,
        second: LayoutNode
    ) -> LayoutNode {
        switch (first, second) {
        case (.empty, .empty):
            return .empty
        case (.empty, let node):
            return node
        case (_, .empty):
            return first
        default:
            return .split(direction: direction, ratio: ratio, first: first, second: second)
        }
    }

}

private func splitAreas(direction: SplitDirection, ratio: Double, area: CGRect) -> (CGRect, CGRect) {
    switch direction {
    case .horizontal:
        let width = area.width * ratio
        return (
            CGRect(x: area.minX, y: area.minY, width: width, height: area.height),
            CGRect(x: area.minX + width, y: area.minY, width: area.width - width, height: area.height)
        )
    case .vertical:
        let height = area.height * ratio
        return (
            CGRect(x: area.minX, y: area.maxY - height, width: area.width, height: height),
            CGRect(x: area.minX, y: area.minY, width: area.width, height: area.height - height)
        )
    }
}

private func clampRatio(_ value: Double) -> Double {
    min(0.9, max(0.1, value))
}
