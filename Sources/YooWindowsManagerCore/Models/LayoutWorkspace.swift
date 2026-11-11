import CoreGraphics
import Foundation

/// 单个显示器上的二分布局工作区。
public struct LayoutWorkspace: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public var screenName: String
    public var usableFrame: CGRect
    public var root: LayoutNode
    public var focusedWindowID: UInt32?

    public init(
        id: String,
        screenName: String,
        usableFrame: CGRect,
        root: LayoutNode = .empty,
        focusedWindowID: UInt32? = nil
    ) {
        self.id = id
        self.screenName = screenName
        self.usableFrame = usableFrame
        self.root = root
        self.focusedWindowID = focusedWindowID
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

    public func placements() -> [WindowPlacement] {
        root.resolvedPlacements(in: usableFrame)
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
