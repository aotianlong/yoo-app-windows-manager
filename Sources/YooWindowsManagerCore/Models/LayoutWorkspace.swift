import CoreGraphics
import Foundation

/// 单个显示器上的二分布局工作区。
public struct LayoutWorkspace: Codable, Sendable, Equatable, Identifiable {
    public static let defaultWindowGap: CGFloat = 10
    public static let defaultEdgeGap: CGFloat = 5

    public let id: String
    public var screenName: String
    public var usableFrame: CGRect
    public var root: LayoutNode
    public var focusedWindowID: UInt32?
    /// 稳定顺序，避免拖动时按坐标重排导致布局树抖动。
    public var windowOrder: [UInt32]

    public init(
        id: String,
        screenName: String,
        usableFrame: CGRect,
        root: LayoutNode = .empty,
        focusedWindowID: UInt32? = nil,
        windowOrder: [UInt32] = []
    ) {
        self.id = id
        self.screenName = screenName
        self.usableFrame = usableFrame
        self.root = root
        self.focusedWindowID = focusedWindowID
        self.windowOrder = windowOrder
    }

    public mutating func apply(split direction: SplitDirection, to window: WindowReference, ratio: Double = LayoutNode.defaultRatio) {
        root = root.splitCurrent(inserting: window, direction: direction, ratio: ratio)
        focusedWindowID = window.windowID
    }

    public mutating func setFocused(_ window: WindowReference) {
        focusedWindowID = window.windowID
        switch root {
        case .empty:
            root = .leaf(window)
        case let .leaf(existing):
            if existing.windowID != window.windowID {
                root = root.splitCurrent(inserting: window, direction: .horizontal, ratio: LayoutNode.defaultRatio)
            }
        case .split:
            if !contains(windowID: window.windowID) {
                root = root.splitCurrent(inserting: window, direction: .horizontal, ratio: LayoutNode.defaultRatio)
            }
        }
    }

    public mutating func removeWindow(id: UInt32) {
        root = root.removing(windowID: id)
        if focusedWindowID == id {
            focusedWindowID = nil
        }
    }

    public func placements(
        windowGap: CGFloat = LayoutWorkspace.defaultWindowGap,
        edgeGap: CGFloat = LayoutWorkspace.defaultEdgeGap
    ) -> [WindowPlacement] {
        let halfGap = max(0, windowGap) / 2
        let outerGap = max(0, edgeGap)
        return root.resolvedPlacements(in: usableFrame).map { placement in
            let raw = placement.frame
            let minX = approximatelyEqual(raw.minX, usableFrame.minX) ? raw.minX + outerGap : raw.minX + halfGap
            let maxX = approximatelyEqual(raw.maxX, usableFrame.maxX) ? raw.maxX - outerGap : raw.maxX - halfGap
            let minY = approximatelyEqual(raw.minY, usableFrame.minY) ? raw.minY + outerGap : raw.minY + halfGap
            let maxY = approximatelyEqual(raw.maxY, usableFrame.maxY) ? raw.maxY - outerGap : raw.maxY - halfGap
            return WindowPlacement(
                window: placement.window,
                frame: CGRect(
                    x: minX,
                    y: minY,
                    width: max(1, maxX - minX),
                    height: max(1, maxY - minY)
                )
            )
        }
    }

    public func contains(windowID: UInt32) -> Bool {
        placements().contains { $0.window.windowID == windowID }
    }

    public mutating func rebalance() {
        root = rebalance(node: root)
    }

    private func rebalance(node: LayoutNode) -> LayoutNode {
        switch node {
        case .empty, .leaf:
            return node
        case let .split(direction, _, first, second):
            return .split(direction: direction, ratio: LayoutNode.defaultRatio, first: rebalance(node: first), second: rebalance(node: second))
        }
    }
}

private func approximatelyEqual(_ lhs: CGFloat, _ rhs: CGFloat) -> Bool {
    abs(lhs - rhs) < 0.5
}
