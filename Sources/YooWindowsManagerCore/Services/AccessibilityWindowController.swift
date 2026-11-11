import AppKit
import ApplicationServices
import CoreGraphics
import Foundation

public enum WindowManagerError: Error, LocalizedError, Sendable {
    case accessibilityNotGranted
    case applicationNotFound(pid: Int32)
    case windowNotFound(windowID: UInt32)
    case attributeSetFailed(String)

    public var errorDescription: String? {
        switch self {
        case .accessibilityNotGranted:
            return "未获得辅助功能权限，请在「系统设置 → 隐私与安全性 → 辅助功能」中授权本应用。"
        case let .applicationNotFound(pid):
            return "找不到 PID 为 \(pid) 的应用进程。"
        case let .windowNotFound(windowID):
            return "找不到窗口 ID \(windowID)。"
        case let .attributeSetFailed(name):
            return "无法设置窗口属性：\(name)。"
        }
    }
}

public struct AccessibilityWindowController: Sendable {
    public init() {}

    public func isTrusted() -> Bool {
        AXIsProcessTrusted()
    }

    public func requestTrust(prompt: Bool = true) {
        if prompt {
            let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
            _ = AXIsProcessTrustedWithOptions(options)
        }
        openAccessibilitySettings()
    }

    public func openAccessibilitySettings() {
        let urls = [
            "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_Accessibility",
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility",
        ]
        for link in urls {
            if let url = URL(string: link), NSWorkspace.shared.open(url) {
                return
            }
        }
    }

    public var trustedAppPath: String {
        if Bundle.main.bundleURL.pathExtension == "app" {
            return Bundle.main.bundlePath
        }

        let executable = ProcessInfo.processInfo.arguments.first ?? ProcessInfo.processInfo.processName
        return URL(fileURLWithPath: executable).standardizedFileURL.path
    }

    public func apply(placements: [WindowPlacement], animated: Bool = false) throws {
        guard isTrusted() else {
            throw WindowManagerError.accessibilityNotGranted
        }

        try apply(placements: placements, startingFrames: [:], animated: animated)
    }

    public func apply(
        placements: [WindowPlacement],
        startingFrames: [UInt32: CGRect],
        animated: Bool
    ) throws {
        guard isTrusted() else {
            throw WindowManagerError.accessibilityNotGranted
        }
        if !animated {
            let pending = placements.filter { placement in
                !frameClose(
                    startingFrames[placement.window.windowID],
                    placement.frame,
                    threshold: 2
                )
            }
            try applyInstant(pending)
            return
        }

        let (instant, animatedPlacements) = splitPlacements(
            placements,
            startingFrames: startingFrames,
            animationThreshold: 10
        )
        try applyInstant(instant)
        guard !animatedPlacements.isEmpty else { return }
        try applyAnimated(
            placements: animatedPlacements,
            startingFrames: startingFrames,
            duration: 0.22,
            steps: 12
        )
    }

    private func applyInstant(_ placements: [WindowPlacement]) throws {
        var appliedAny = false
        var lastError: Error?

        for placement in placements {
            do {
                try setFrame(placement.frame, for: placement.window)
                appliedAny = true
            } catch {
                lastError = error
            }
        }

        if !appliedAny, let lastError {
            throw lastError
        }
    }

    private func splitPlacements(
        _ placements: [WindowPlacement],
        startingFrames: [UInt32: CGRect],
        animationThreshold: CGFloat
    ) -> (instant: [WindowPlacement], animated: [WindowPlacement]) {
        var instant: [WindowPlacement] = []
        var animated: [WindowPlacement] = []
        for placement in placements {
            let current = startingFrames[placement.window.windowID]
            if frameClose(current, placement.frame, threshold: 2) {
                continue
            }
            if shouldAnimate(from: current, to: placement.frame, threshold: animationThreshold) {
                animated.append(placement)
            } else {
                instant.append(placement)
            }
        }
        return (instant, animated)
    }

    private func shouldAnimate(from current: CGRect?, to target: CGRect, threshold: CGFloat) -> Bool {
        guard let current else { return true }
        let delta = max(
            abs(current.origin.x - target.origin.x),
            abs(current.origin.y - target.origin.y),
            abs(current.width - target.width),
            abs(current.height - target.height)
        )
        return delta > threshold
    }

    private func frameClose(_ lhs: CGRect?, _ rhs: CGRect, threshold: CGFloat) -> Bool {
        guard let lhs else { return false }
        return abs(lhs.origin.x - rhs.origin.x) <= threshold
            && abs(lhs.origin.y - rhs.origin.y) <= threshold
            && abs(lhs.width - rhs.width) <= threshold
            && abs(lhs.height - rhs.height) <= threshold
    }

    private func applyAnimated(
        placements: [WindowPlacement],
        startingFrames: [UInt32: CGRect] = [:],
        duration: TimeInterval,
        steps: Int
    ) throws {
        guard steps > 0, !placements.isEmpty else { return }
        let stepDuration = duration / Double(steps)
        var appliedAny = false
        var lastError: Error?

        for step in 1 ... steps {
            let progress = Double(step) / Double(steps)
            let eased = 1 - pow(1 - progress, 3)

            for placement in placements {
                let start = startingFrames[placement.window.windowID] ?? placement.frame
                let frame = CGRect(
                    x: lerp(start.origin.x, placement.frame.origin.x, eased),
                    y: lerp(start.origin.y, placement.frame.origin.y, eased),
                    width: lerp(start.width, placement.frame.width, eased),
                    height: lerp(start.height, placement.frame.height, eased)
                )
                do {
                    try setFrame(frame, for: placement.window)
                    appliedAny = true
                } catch {
                    lastError = error
                }
            }

            if step < steps {
                Thread.sleep(forTimeInterval: stepDuration)
            }
        }

        if !appliedAny, let lastError {
            throw lastError
        }
    }

    private func lerp(_ from: CGFloat, _ to: CGFloat, _ t: Double) -> CGFloat {
        from + (to - from) * t
    }

    public func focus(window: WindowReference) throws {
        guard isTrusted() else {
            throw WindowManagerError.accessibilityNotGranted
        }

        let appElement = AXUIElementCreateApplication(window.ownerPID)
        var value: CFTypeRef?
        let copyResult = AXUIElementCopyAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, &value)
        if copyResult == .success, let focused = value {
            _ = AXUIElementPerformAction(focused as! AXUIElement, kAXRaiseAction as CFString)
        }

        guard let axWindow = try findAXWindow(pid: window.ownerPID, windowID: window.windowID) else {
            throw WindowManagerError.windowNotFound(windowID: window.windowID)
        }

        _ = AXUIElementSetAttributeValue(appElement, kAXMainAttribute as CFString, axWindow)
        _ = AXUIElementSetAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, axWindow)
        _ = AXUIElementPerformAction(axWindow, kAXRaiseAction as CFString)
    }

    private func setFrame(_ frame: CGRect, for window: WindowReference) throws {
        guard let axWindow = try findAXWindow(pid: window.ownerPID, windowID: window.windowID) else {
            throw WindowManagerError.windowNotFound(windowID: window.windowID)
        }

        let accessibilityFrame = ScreenCoordinateConverter.flipVertically(
            frame,
            mainScreenMaxY: NSScreen.screens.first?.frame.maxY ?? 0
        )
        let position = accessibilityFrame.origin
        guard let positionValue = axValue(position, type: .cgPoint) else {
            throw WindowManagerError.attributeSetFailed("kAXPositionAttribute")
        }
        guard AXUIElementSetAttributeValue(axWindow, kAXPositionAttribute as CFString, positionValue) == .success else {
            throw WindowManagerError.attributeSetFailed("kAXPositionAttribute")
        }

        let size = accessibilityFrame.size
        guard let sizeValue = axValue(size, type: .cgSize) else {
            throw WindowManagerError.attributeSetFailed("kAXSizeAttribute")
        }
        guard AXUIElementSetAttributeValue(axWindow, kAXSizeAttribute as CFString, sizeValue) == .success else {
            throw WindowManagerError.attributeSetFailed("kAXSizeAttribute")
        }
    }

    private func axValue<T>(_ value: T, type: AXValueType) -> AXValue? {
        var mutable = value
        return withUnsafePointer(to: &mutable) { pointer in
            AXValueCreate(type, pointer)
        }
    }

    private func findAXWindow(pid: Int32, windowID: UInt32) throws -> AXUIElement? {
        let appElement = AXUIElementCreateApplication(pid)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &value) == .success,
              let rawWindows = value as? [AXUIElement]
        else {
            throw WindowManagerError.applicationNotFound(pid: pid)
        }

        for axWindow in rawWindows {
            if let id = axWindowID(axWindow), id == windowID {
                return axWindow
            }
        }

        for axWindow in rawWindows {
            if axWindowIsVisible(axWindow) {
                return axWindow
            }
        }

        return rawWindows.first
    }

    private func axWindowID(_ window: AXUIElement) -> UInt32? {
        var windowID: CGWindowID = 0
        if AXUIElementGetWindowID(window, &windowID) == .success {
            return windowID
        }

        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window, "AXWindowID" as CFString, &value) == .success,
              let number = value
        else { return nil }

        if CFGetTypeID(number) == CFNumberGetTypeID() {
            var intValue: Int = 0
            CFNumberGetValue((number as! CFNumber), .sInt32Type, &intValue)
            return UInt32(intValue)
        }
        return nil
    }

    private func axWindowIsVisible(_ window: AXUIElement) -> Bool {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window, kAXMinimizedAttribute as CFString, &value) == .success,
              let minimized = value as? Bool
        else { return true }
        return !minimized
    }
}
