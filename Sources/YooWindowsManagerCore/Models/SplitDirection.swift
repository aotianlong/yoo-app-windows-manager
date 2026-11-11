import Foundation

/// 二分分割方向：水平为左右，垂直为上下。
public enum SplitDirection: String, Codable, Sendable, CaseIterable {
    case horizontal
    case vertical
}
