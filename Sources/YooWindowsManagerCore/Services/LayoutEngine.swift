import CoreGraphics
import Foundation

public enum LayoutCommand: String, Sendable, CaseIterable {
    case splitLeft
    case splitRight
    case splitTop
    case splitBottom
    case balance
    case reset
}

public struct LayoutEngine: Sendable {
    public init() {}

    public func direction(for command: LayoutCommand) -> SplitDirection? {
        switch command {
        case .splitLeft, .splitRight:
            return .horizontal
        case .splitTop, .splitBottom:
            return .vertical
        case .balance, .reset:
            return nil
        }
    }

    public func ratio(for command: LayoutCommand) -> Double {
        switch command {
        case .splitLeft, .splitTop:
            return 0.5
        case .splitRight, .splitBottom:
            return 0.5
        case .balance, .reset:
            return LayoutNode.defaultRatio
        }
    }

    /// 针对水平/垂直二分，决定在 first 还是 second 侧放入新焦点窗口。
    public func preferFirstChild(for command: LayoutCommand) -> Bool {
        switch command {
        case .splitLeft, .splitTop:
            return true
        case .splitRight, .splitBottom:
            return false
        case .balance, .reset:
            return true
        }
    }

    public func apply(command: LayoutCommand, workspace: inout LayoutWorkspace, focused: WindowReference) {
        switch command {
        case .splitLeft:
            workspace.apply(split: .horizontal, to: focused, ratio: 0.5)
        case .splitRight:
            workspace.root = splitWithFocusOnSecond(workspace: workspace, window: focused, direction: .horizontal)
            workspace.focusedWindowID = focused.windowID
        case .splitTop:
            workspace.apply(split: .vertical, to: focused, ratio: 0.5)
        case .splitBottom:
            workspace.root = splitWithFocusOnSecond(workspace: workspace, window: focused, direction: .vertical)
            workspace.focusedWindowID = focused.windowID
        case .balance:
            workspace.rebalance()
        case .reset:
            workspace.root = .leaf(focused)
            workspace.focusedWindowID = focused.windowID
        }
    }

    private func splitWithFocusOnSecond(
        workspace: LayoutWorkspace,
        window: WindowReference,
        direction: SplitDirection
    ) -> LayoutNode {
        switch workspace.root {
        case .empty:
            return .leaf(window)
        case let .leaf(existing):
            return .split(direction: direction, ratio: 0.5, first: .leaf(existing), second: .leaf(window))
        case let .split(dir, ratio, first, second):
            if first.containsEmpty {
                return .split(direction: dir, ratio: ratio, first: first.splitCurrent(inserting: window, direction: direction), second: second)
            }
            return .split(
                direction: direction,
                ratio: 0.5,
                first: .split(direction: dir, ratio: ratio, first: first, second: second),
                second: .leaf(window)
            )
        }
    }
}
