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

    /// 按窗口数量生成平衡二分树（窗口多时优先水平再垂直交替）。
    public func autoLayout(windows: [WindowReference]) -> LayoutNode {
        buildAutoTree(windows: windows, depth: 0)
    }

    private func buildAutoTree(windows: [WindowReference], depth: Int) -> LayoutNode {
        guard let first = windows.first else { return .empty }
        if windows.count == 1 { return .leaf(first) }

        let mid = windows.count / 2
        let lhs = Array(windows.prefix(mid))
        let rhs = Array(windows.suffix(windows.count - mid))
        let direction: SplitDirection = depth.isMultiple(of: 2) ? .horizontal : .vertical
        let ratio = Double(lhs.count) / Double(windows.count)

        return .split(
            direction: direction,
            ratio: ratio,
            first: buildAutoTree(windows: lhs, depth: depth + 1),
            second: buildAutoTree(windows: rhs, depth: depth + 1)
        )
    }

    public func applyAutoLayout(workspace: inout LayoutWorkspace, windows: [WindowReference]) {
        workspace.root = autoLayout(windows: windows)
        workspace.focusedWindowID = windows.last?.windowID
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
