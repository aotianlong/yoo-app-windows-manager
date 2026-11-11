import AppKit
import YooWindowsManagerCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let store = WorkspaceStore()
    private let engine = LayoutEngine()
    private let discovery = WindowDiscovery()
    private let ax = AccessibilityWindowController()

    private var statusItem: NSStatusItem?
    private var toggleItem: NSMenuItem?
    private var autoLayoutTimer: Timer?
    private var lastSignature = ""

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
            relayoutAllScreens()
            return
        }
        isEnabled = false
    }

    @objc private func workspaceDidChange() {
        guard isEnabled else { return }
        relayoutAllScreens()
    }

    private func startAutoLayout() {
        stopAutoLayout()
        autoLayoutTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.relayoutAllScreensIfNeeded()
            }
        }
    }

    private func stopAutoLayout() {
        autoLayoutTimer?.invalidate()
        autoLayoutTimer = nil
        lastSignature = ""
    }

    private func relayoutAllScreensIfNeeded() {
        guard isEnabled, ax.isTrusted() else { return }
        let signature = currentLayoutSignature()
        guard signature != lastSignature else { return }
        lastSignature = signature
        relayoutAllScreens()
    }

    private func currentLayoutSignature() -> String {
        store.syncScreens()
        return NSScreen.screens
            .map { screen in
                let windows = discovery.windows(on: screen, excludingPID: ownPID)
                return "\(screen.localizedName):\(windows.map(\.windowID).sorted())"
            }
            .joined(separator: "|")
    }

    private func relayoutAllScreens() {
        guard isEnabled else { return }
        guard ax.isTrusted() else {
            _ = ensureAccessibilityPermission()
            return
        }

        store.syncScreens()
        var hadError = false

        for screen in NSScreen.screens {
            let windows = discovery.windows(on: screen, excludingPID: ownPID)
            guard !windows.isEmpty else { continue }

            var workspace = store.workspace(for: screen)
            engine.applyAutoLayout(workspace: &workspace, windows: windows)
            let placements = workspace.placements()

            do {
                try ax.apply(placements: placements)
                store.update(workspace)
            } catch {
                hadError = true
            }
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
