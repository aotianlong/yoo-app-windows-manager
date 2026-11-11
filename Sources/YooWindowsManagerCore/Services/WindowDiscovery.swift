import AppKit
import CoreGraphics
import Foundation

public struct WindowDiscovery: Sendable {
    public struct OnScreenWindow: Sendable {
        public let reference: WindowReference
        public let bounds: CGRect

        public init(reference: WindowReference, bounds: CGRect) {
            self.reference = reference
            self.bounds = bounds
        }
    }

    public init() {}

    public func onScreenWindows(excludingPID: pid_t? = nil) -> [WindowReference] {
        scanned(excludingPID: excludingPID).map(\.reference)
    }

    public func scanned(excludingPID: pid_t? = nil) -> [OnScreenWindow] {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let infoList = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return []
        }

        var results: [OnScreenWindow] = []
        for info in infoList {
            guard let layer = info[kCGWindowLayer as String] as? Int, layer == 0 else { continue }
            guard let windowID = info[kCGWindowNumber as String] as? UInt32 else { continue }
            guard let ownerPID = info[kCGWindowOwnerPID as String] as? Int32 else { continue }
            if let excludingPID, ownerPID == excludingPID { continue }
            guard let ownerName = info[kCGWindowOwnerName as String] as? String else { continue }

            let title = info[kCGWindowName as String] as? String ?? ""
            let bounds = cgBounds(from: info[kCGWindowBounds as String] as? [String: CGFloat] ?? [:])
            guard bounds.width > 120, bounds.height > 80 else { continue }

            if ownerName == "Window Server" || ownerName == "Dock" || ownerName == "Control Centre" {
                continue
            }

            let reference = WindowReference(windowID: windowID, ownerPID: ownerPID, ownerName: ownerName, title: title)
            results.append(OnScreenWindow(reference: reference, bounds: bounds))
        }

        return results
    }

    public func windows(on screen: NSScreen, excludingPID: pid_t? = nil) -> [WindowReference] {
        let candidates = scanned(excludingPID: excludingPID).filter { item in
            guard let ownerScreen = screenContainingWindow(bounds: item.bounds) else { return false }
            return ownerScreen.localizedName == screen.localizedName
        }

        let sorted = candidates.sorted { lhs, rhs in
            let la = cocoaBounds(from: lhs.bounds)
            let ra = cocoaBounds(from: rhs.bounds)
            if la.minY != ra.minY { return la.minY > ra.minY }
            return la.minX < ra.minX
        }

        return sorted.map(\.reference)
    }

    public func frontmostWindow(excludingPID: pid_t? = nil) -> WindowReference? {
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
        let pid = app.processIdentifier
        if let excludingPID, pid == excludingPID { return nil }

        let appWindows = onScreenWindows(excludingPID: excludingPID).filter { $0.ownerPID == pid }
        return appWindows.first
    }

    private func cgBounds(from dict: [String: CGFloat]) -> CGRect {
        CGRect(
            x: dict["X"] ?? 0,
            y: dict["Y"] ?? 0,
            width: dict["Width"] ?? 0,
            height: dict["Height"] ?? 0
        )
    }

    private func cocoaBounds(from quartzBounds: CGRect) -> CGRect {
        let flippedMaxY = NSScreen.screens.map(\.frame.maxY).max() ?? 0
        return CGRect(
            x: quartzBounds.origin.x,
            y: flippedMaxY - quartzBounds.origin.y - quartzBounds.height,
            width: quartzBounds.width,
            height: quartzBounds.height
        )
    }

    private func screenContainingWindow(bounds: CGRect) -> NSScreen? {
        let cocoa = cocoaBounds(from: bounds)
        let center = CGPoint(x: cocoa.midX, y: cocoa.midY)
        return NSScreen.screens.first { $0.frame.contains(center) }
    }
}
