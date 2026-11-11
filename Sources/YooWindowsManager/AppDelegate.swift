import AppKit
import YooWindowsManagerCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let store = WorkspaceStore()
    private let engine = LayoutEngine()
    private let discovery = WindowDiscovery()
    private let ax = AccessibilityWindowController()
    private let interactionPause = InteractionPauseMonitor()

    private var statusItem: NSStatusItem?
    private var toggleItem: NSMenuItem?
    private var autoLayoutTimer: Timer?
    private var lastSignature = ""
    private var lastScreenByWindow: [UInt32: String] = [:]
    private var isApplyingLayout = false

    private let enabledDefaultsKey = "yoo.windowsManager.enabled"
    private var isEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: enabledDefaultsKey) }
        set {
            UserDefaults.standard.set(newValue, forKey: enabledDefaultsKey)
            refreshUI()
            if newValue {
                startAutoLayout()
            } else {
                stopAutoLayout()
            }
        }
    }

    private var ownPID: pid_t { ProcessInfo.processInfo.processIdentifier }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        if UserDefaults.standard.object(forKey: enabledDefaultsKey) == nil {
            UserDefaults.standard.set(true, forKey: enabledDefaultsKey)
        }
        setupStatusItem()
        refreshUI()
        if isEnabled {
            startAutoLayout()
        }
        interactionPause.start()
        interactionPause.onInteractionEnded = { [weak self] in
            self?.relayoutAllScreensIfNeeded(force: true, animated: true)
        }

        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(workspaceDidChange),
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil
        )
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        guard let button = statusItem?.button else { return }
        button.imagePosition = .imageOnly

        let menu = NSMenu()
        toggleItem = NSMenuItem(title: "停用", action: #selector(toggleEnabled), keyEquivalent: "")
        toggleItem?.target = self
        menu.addItem(toggleItem!)
        statusItem?.menu = menu
    }

    @objc private func toggleEnabled() {
        if !isEnabled {
            guard ensureAccessibilityPermission() else { return }
            isEnabled = true
            relayoutAllScreens(animated: true)
            return
        }
        isEnabled = false
    }

    @objc private func workspaceDidChange() {
        guard isEnabled else { return }
        relayoutAllScreensIfNeeded(animated: true)
    }

    private func startAutoLayout() {
        stopAutoLayout()
        autoLayoutTimer = Timer.scheduledTimer(withTimeInterval: 1.25, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.relayoutAllScreensIfNeeded(animated: true)
            }
        }
    }

    private func stopAutoLayout() {
        autoLayoutTimer?.invalidate()
        autoLayoutTimer = nil
        lastSignature = ""
        lastScreenByWindow = [:]
    }

    private func relayoutAllScreensIfNeeded(force: Bool = false, animated: Bool = false) {
        guard isEnabled, ax.isTrusted(), !isApplyingLayout else { return }
        guard !interactionPause.shouldSuppressLayout else { return }
        let signature = currentLayoutSignature()
        if !force {
            guard signature != lastSignature else { return }
        }
        lastSignature = signature
        relayoutAllScreens(animated: animated)
    }

    private func currentLayoutSignature() -> String {
        store.syncScreens()
        reconcileMovedWindows()
        return NSScreen.screens
            .map { screen in
                let windows = discovery.windows(on: screen, excludingPID: ownPID)
                return "\(screen.localizedName):\(windows.map(\.windowID).sorted())"
            }
            .joined(separator: "|")
    }

    /// 窗口拖到另一块屏后，从旧 workspace 的 order 中移除，并挂到新屏。
    private func reconcileMovedWindows() {
        var currentByWindow: [UInt32: String] = [:]
        for screen in NSScreen.screens {
            let name = screen.localizedName
            for window in discovery.windows(on: screen, excludingPID: ownPID) {
                currentByWindow[window.windowID] = name
            }
        }

        for screen in NSScreen.screens {
            var workspace = store.workspace(for: screen)
            let onScreen = Set(
                discovery.windows(on: screen, excludingPID: ownPID).map(\.windowID)
            )
            workspace.windowOrder = workspace.windowOrder.filter { onScreen.contains($0) }
            store.update(workspace)
        }

        for (windowID, screenName) in currentByWindow {
            if let previous = lastScreenByWindow[windowID], previous != screenName {
                guard let screen = NSScreen.screens.first(where: { $0.localizedName == screenName }) else { continue }
                var workspace = store.workspace(for: screen)
                workspace.windowOrder.removeAll { $0 == windowID }
                workspace.windowOrder.insert(windowID, at: 0)
                store.update(workspace)
            }
        }

        lastScreenByWindow = currentByWindow
    }

    private func relayoutAllScreens(animated: Bool) {
        guard isEnabled, !isApplyingLayout else { return }
        guard ax.isTrusted() else {
            _ = ensureAccessibilityPermission()
            return
        }

        isApplyingLayout = true
        defer { isApplyingLayout = false }

        store.syncScreens()
        reconcileMovedWindows()

        var hadError = false
        var allPlacements: [WindowPlacement] = []
        let startingFrames = discovery.cocoaFramesByID(excludingPID: ownPID)

        for screen in NSScreen.screens {
            let discovered = discovery.windows(on: screen, excludingPID: ownPID)
            var workspace = store.workspace(for: screen)

            if discovered.isEmpty {
                workspace.root = .empty
                workspace.windowOrder = []
                workspace.focusedWindowID = nil
                store.update(workspace)
                continue
            }

            let windows = engine.stabilize(discovered: discovered, previousOrder: workspace.windowOrder)
            engine.applyAutoLayout(workspace: &workspace, windows: windows)
            allPlacements.append(contentsOf: workspace.placements())
            store.update(workspace)
        }

        guard !allPlacements.isEmpty else { return }

        do {
            try ax.apply(placements: allPlacements, startingFrames: startingFrames, animated: animated)
        } catch {
            hadError = true
        }

        if hadError, !ax.isTrusted() {
            ensureAccessibilityPermission()
        }
    }

    @discardableResult
    private func ensureAccessibilityPermission() -> Bool {
        if ax.isTrusted() { return true }

        ax.requestTrust(prompt: true)

        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "需要辅助功能权限"
        alert.informativeText = """
        已尝试打开「系统设置 → 隐私与安全性 → 辅助功能」。

        请打开开关，并在列表中允许本程序：
        \(ax.trustedAppPath)

        若列表中没有，请点「+」手动添加以上路径。授权后再次点击菜单栏图标启用。
        """
        alert.alertStyle = .informational
        alert.addButton(withTitle: "打开系统设置")
        alert.addButton(withTitle: "知道了")
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            ax.openAccessibilitySettings()
        }
        return false
    }

    private func refreshUI() {
        statusItem?.button?.image = MenuBarIcon.make(enabled: isEnabled)
        toggleItem?.title = isEnabled ? "停用" : "启用"
    }
}
