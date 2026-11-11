import AppKit
import ApplicationServices
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
        var checkedPIDs: Set<pid_t> = []
        var standardWindowIDsByPID: [pid_t: Set<CGWindowID>] = [:]
        for info in infoList {
            guard let layer = info[kCGWindowLayer as String] as? Int, layer == 0 else { continue }
            guard let windowID = info[kCGWindowNumber as String] as? UInt32 else { continue }
            guard let ownerPID = info[kCGWindowOwnerPID as String] as? Int32 else { continue }
            if let excludingPID, ownerPID == excludingPID { continue }
            guard let ownerName = info[kCGWindowOwnerName as String] as? String else { continue }

            let title = info[kCGWindowName as String] as? String ?? ""
            let bounds = cgBounds(from: info[kCGWindowBounds as String] as? [String: CGFloat] ?? [:])
            guard bounds.width > 120, bounds.height > 80 else { continue }

            if ownerName == "Window Server" || ownerName == "Dock" || ownerName == "Control Centre"
                || ownerName == "universalAccessAuthWarn"
            {
                continue
            }

            if !checkedPIDs.contains(ownerPID) {
                checkedPIDs.insert(ownerPID)
                standardWindowIDsByPID[ownerPID] = standardWindowIDs(for: ownerPID)
            }
            if let standardIDs = standardWindowIDsByPID[ownerPID], !standardIDs.contains(windowID) {
                continue
            }

            let reference = WindowReference(windowID: windowID, ownerPID: ownerPID, ownerName: ownerName, title: title)
            results.append(OnScreenWindow(reference: reference, bounds: bounds))
        }

        return results
    }

    private func standardWindowIDs(for pid: pid_t) -> Set<CGWindowID>? {
        let appElement = AXUIElementCreateApplication(pid)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &value) == .success,
              let windows = value as? [AXUIElement]
        else { return nil }

        return Set(windows.compactMap { window in
            var subroleValue: CFTypeRef?
            guard AXUIElementCopyAttributeValue(window, kAXSubroleAttribute as CFString, &subroleValue) == .success,
                  let subrole = subroleValue as? String,
                  subrole == kAXStandardWindowSubrole
            else { return nil }

            var windowID: CGWindowID = 0
            guard AXUIElementGetWindowID(window, &windowID) == .success else { return nil }
            return windowID
        })
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
        ScreenCoordinateConverter.flipVertically(
            quartzBounds,
            mainScreenMaxY: NSScreen.screens.first?.frame.maxY ?? 0
        )
    }

    private func screenContainingWindow(bounds: CGRect) -> NSScreen? {
        let cocoa = cocoaBounds(from: bounds)
        var bestScreen: NSScreen?
        var bestArea: CGFloat = 0

        for screen in NSScreen.screens {
            let intersection = screen.frame.intersection(cocoa)
            guard intersection.width > 0, intersection.height > 0 else { continue }
            let area = intersection.width * intersection.height
            if area > bestArea {
                bestArea = area
                bestScreen = screen
            }
        }

        return bestScreen
    }

    public func cocoaFrame(for windowID: UInt32, excludingPID: pid_t? = nil) -> CGRect? {
        for item in scanned(excludingPID: excludingPID) where item.reference.windowID == windowID {
            return cocoaBounds(from: item.bounds)
        }
        return nil
    }

    public func cocoaFramesByID(excludingPID: pid_t? = nil) -> [UInt32: CGRect] {
        var map: [UInt32: CGRect] = [:]
        for item in scanned(excludingPID: excludingPID) {
            map[item.reference.windowID] = cocoaBounds(from: item.bounds)
        }
        return map
    }
}
