import AppKit
import CoreGraphics
import Foundation

public struct WindowDiscovery: Sendable {
    public init() {}

  /// 枚举当前屏幕上可管理的普通应用窗口。
    public func onScreenWindows(excludingPID: pid_t? = nil) -> [WindowReference] {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let infoList = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return []
        }

        var results: [WindowReference] = []
        for info in infoList {
            guard let layer = info[kCGWindowLayer as String] as? Int, layer == 0 else { continue }
            guard let windowID = info[kCGWindowNumber as String] as? UInt32 else { continue }
            guard let ownerPID = info[kCGWindowOwnerPID as String] as? Int32 else { continue }
            if let excludingPID, ownerPID == excludingPID { continue }
            guard let ownerName = info[kCGWindowOwnerName as String] as? String else { continue }

            let title = info[kCGWindowName as String] as? String ?? ""
            let boundsDict = info[kCGWindowBounds as String] as? [String: CGFloat] ?? [:]
            let width = boundsDict["Width"] ?? 0
            let height = boundsDict["Height"] ?? 0
            guard width > 120, height > 80 else { continue }

            if ownerName == "Window Server" || ownerName == "Dock" {
                continue
            }

            results.append(WindowReference(windowID: windowID, ownerPID: ownerPID, ownerName: ownerName, title: title))
        }

        return results
    }

    public func frontmostWindow(excludingPID: pid_t? = nil) -> WindowReference? {
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
        let pid = app.processIdentifier
        if let excludingPID, pid == excludingPID { return nil }

        let appWindows = onScreenWindows(excludingPID: excludingPID).filter { $0.ownerPID == pid }
        return appWindows.first
    }
}
