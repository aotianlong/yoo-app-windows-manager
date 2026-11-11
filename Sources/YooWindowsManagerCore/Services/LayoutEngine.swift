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

    /// 螺旋二分：每层只切出一个窗口，方向左右 / 上下交替。
    /// 2 个→左右；3 个→左 1 + 右上 1 + 右下 1；4 个→左 1 + 右上 1 + 右下左右 2……
    public func autoLayout(windows: [WindowReference]) -> LayoutNode {
        buildSpiral(windows: windows, direction: .horizontal)
    }

    private func buildSpiral(windows: [WindowReference], direction: SplitDirection) -> LayoutNode {
        guard let head = windows.first else { return .empty }
        if windows.count == 1 { return .leaf(head) }

        let tail = Array(windows.dropFirst())
        let nextDirection: SplitDirection = direction == .horizontal ? .vertical : .horizontal
        return .split(
            direction: direction,
            ratio: LayoutNode.defaultRatio,
            first: .leaf(head),
            second: buildSpiral(windows: tail, direction: nextDirection)
        )
    }

    public func applyAutoLayout(workspace: inout LayoutWorkspace, windows: [WindowReference]) {
        workspace.root = autoLayout(windows: windows)
        workspace.windowOrder = windows.map(\.windowID)
        workspace.focusedWindowID = windows.last?.windowID
    }

    /// 保留已有顺序，仅追加/移除窗口，不因拖动中的坐标变化重排。
    public func stabilize(discovered: [WindowReference], previousOrder: [UInt32]) -> [WindowReference] {
        if previousOrder.isEmpty {
            return discovered
        }
        let lookup = Dictionary(uniqueKeysWithValues: discovered.map { ($0.windowID, $0) })
        var ordered: [WindowReference] = []
        for id in previousOrder {
            if let window = lookup[id] {
                ordered.append(window)
            }
        }
        let newcomers = discovered
            .filter { !previousOrder.contains($0.windowID) }
            .sorted { $0.windowID < $1.windowID }
        ordered.append(contentsOf: newcomers)
        return ordered
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
