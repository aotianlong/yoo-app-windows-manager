import AppKit
import YooWindowsManagerCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let store = WorkspaceStore()
    private let engine = LayoutEngine()
    private let discovery = WindowDiscovery()
    private let ax = AccessibilityWindowController()
    private let hotkeys = HotkeyService()

    private var statusItem: NSStatusItem?
    private var ownPID: pid_t { ProcessInfo.processInfo.processIdentifier }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        setupStatusItem()
        hotkeys.onCommand = { [weak self] command in
            Task { @MainActor in
                self?.handle(command: command)
            }
        }
        hotkeys.start()
        ax.requestTrust()
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem?.button?.title = "⊞"
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "左半屏 (⌃⌥←)", action: #selector(cmdLeft), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "右半屏 (⌃⌥→)", action: #selector(cmdRight), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "上半屏 (⌃⌥↑)", action: #selector(cmdTop), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "下半屏 (⌃⌥↓)", action: #selector(cmdBottom), keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "平衡分割", action: #selector(cmdBalance), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "重置当前屏", action: #selector(cmdReset), keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "申请辅助功能权限", action: #selector(cmdTrust), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "退出", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem?.menu = menu
    }

    @objc private func cmdLeft() { handle(command: .splitLeft) }
    @objc private func cmdRight() { handle(command: .splitRight) }
    @objc private func cmdTop() { handle(command: .splitTop) }
    @objc private func cmdBottom() { handle(command: .splitBottom) }
    @objc private func cmdBalance() { handle(command: .balance) }
    @objc private func cmdReset() { handle(command: .reset) }
    @objc private func cmdTrust() { ax.requestTrust() }

    private func handle(command: LayoutCommand) {
        store.syncScreens()
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        guard let focused = discovery.frontmostWindow(excludingPID: ownPID) else {
            presentAlert("未找到可管理的前台窗口")
            return
        }

        var workspace = store.workspace(for: screen)
        engine.apply(command: command, workspace: &workspace, focused: focused)

        let placements = workspace.placements()
        do {
            try ax.apply(placements: placements)
            try ax.focus(window: focused)
            store.update(workspace)
        } catch {
            presentAlert(error.localizedDescription)
        }
    }

    private func presentAlert(_ message: String) {
        let alert = NSAlert()
        alert.messageText = "Yoo Windows Manager"
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.runModal()
    }
}
