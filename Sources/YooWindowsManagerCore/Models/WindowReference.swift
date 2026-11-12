import CoreGraphics
import Foundation

/// 窗口在系统中的轻量标识，用于布局树叶子节点。
public struct WindowReference: Hashable, Codable, Sendable, CustomStringConvertible {
    public let windowID: UInt32
    public let ownerPID: Int32
    public let ownerName: String
    public let title: String

    public init(windowID: UInt32, ownerPID: Int32, ownerName: String, title: String) {
        self.windowID = windowID
        self.ownerPID = ownerPID
        self.ownerName = ownerName
        self.title = title
    }

    public var description: String {
        let safeTitle = title.isEmpty
            ? Bundle.main.localizedString(forKey: "window.untitled", value: "Untitled", table: nil)
            : title
        return "\(ownerName) — \(safeTitle)"
    }
}

public struct WindowPlacement: Sendable, Equatable {
    public let window: WindowReference
    public let frame: CGRect

    public init(window: WindowReference, frame: CGRect) {
        self.window = window
        self.frame = frame
    }
}
