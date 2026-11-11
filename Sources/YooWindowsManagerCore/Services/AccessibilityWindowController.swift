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

    public func requestTrust() {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    public func apply(placements: [WindowPlacement]) throws {
        guard isTrusted() else {
            throw WindowManagerError.accessibilityNotGranted
        }

        for placement in placements {
            try setFrame(placement.frame, for: placement.window)
        }
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

        let position = CGPoint(x: frame.origin.x, y: frame.origin.y)
        guard let positionValue = axValue(position, type: .cgPoint) else {
            throw WindowManagerError.attributeSetFailed("kAXPositionAttribute")
        }
        guard AXUIElementSetAttributeValue(axWindow, kAXPositionAttribute as CFString, positionValue) == .success else {
            throw WindowManagerError.attributeSetFailed("kAXPositionAttribute")
        }

        let size = CGSize(width: frame.width, height: frame.height)
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
