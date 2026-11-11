import AppKit
import YooWindowsManagerCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private static let didOpenAccessibilitySettingsKey = "accessibility.didOpenSettingsAutomatically"

    private enum WindowOrderChange {
        case first
        case up
        case down
    }

    private let store = WorkspaceStore()
    private let engine = LayoutEngine()
    private let discovery = WindowDiscovery()
    private let ax = AccessibilityWindowController()
    private let interactionPause = InteractionPauseMonitor()
    private let hotkeys = HotkeyService()
    private let dragFeedback = DragFeedbackOverlayController()
    private let settings = AppSettings()
    private lazy var settingsWindow = SettingsWindowController(settings: settings)

    private var statusItem: NSStatusItem?
    private var accessibilityMenuItem: NSMenuItem?
    private var autoLayoutTimer: Timer?
    private var lastAccessibilityTrusted = false
    private var lastSignature = ""
    private var lastScreenByWindow: [UInt32: String] = [:]
    private var screenAssignmentAtDragStart = ""
    private var draggedWindowID: UInt32?
    private var draggedScreenName: String?
    private var draggedWindowInitialFrame: CGRect?
    private var draggedRootAtStart: LayoutNode?
    private var draggedExpectedFrameAtStart: CGRect?
    private var dragStartPoint: CGPoint?
    private var isResizingManagedWindow = false
    private var isApplyingLayout = false

    private var ownPID: pid_t { ProcessInfo.processInfo.processIdentifier }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        configureApplicationIcon()
        lastAccessibilityTrusted = ax.isTrusted()
        setupStatusItem()
        settings.onChange = { [weak self] change in
            self?.settingsDidChange(change)
        }
        startAutoLayout()
        hotkeys.onRelayout = { [weak self] in
            Task { @MainActor in
                self?.relayoutNow()
            }
        }
        hotkeys.onPromoteFirst = { [weak self] in
            Task { @MainActor in
                self?.reorderFocusedWindow(.first)
            }
        }
        hotkeys.onMoveUp = { [weak self] in
            Task { @MainActor in
                self?.reorderFocusedWindow(.up)
            }
        }
        hotkeys.onMoveDown = { [weak self] in
            Task { @MainActor in
                self?.reorderFocusedWindow(.down)
            }
        }
        hotkeys.start(shortcuts: settings.shortcuts)
        if !lastAccessibilityTrusted,
           !UserDefaults.standard.bool(forKey: Self.didOpenAccessibilitySettingsKey)
        {
            DispatchQueue.main.async { [weak self] in
                self?.openAccessibilitySettings()
            }
        }
        interactionPause.start()
        interactionPause.onDragBegan = { [weak self] startPoint in
            self?.handleDragBegan(startPoint: startPoint)
        }
        interactionPause.onDragChanged = { [weak self] currentPoint in
            self?.handleDragChanged(currentPoint: currentPoint)
        }
        interactionPause.onDragEndedImmediately = { [weak self] in
            self?.dragFeedback.hide()
        }
        interactionPause.onInteractionEnded = { [weak self] dropPoint in
            self?.handleInteractionEnded(dropPoint: dropPoint)
        }
        if ProcessInfo.processInfo.arguments.contains("--about") {
            DispatchQueue.main.async { [weak self] in
                self?.showAbout()
            }
        } else if ProcessInfo.processInfo.arguments.contains("--settings") {
            DispatchQueue.main.async { [weak self] in
                self?.openSettings()
            }
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
        button.image = MenuBarIcon.make(enabled: true)

        let menu = NSMenu()
        menu.delegate = self
        let relayoutItem = NSMenuItem(title: "重新布局", action: #selector(relayoutNow), keyEquivalent: "r")
        relayoutItem.keyEquivalentModifierMask = [.control, .shift]
        relayoutItem.target = self
        menu.addItem(relayoutItem)
        let settingsItem = NSMenuItem(title: "设置…", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.keyEquivalentModifierMask = [.command]
        settingsItem.target = self
        menu.addItem(settingsItem)
        let aboutItem = NSMenuItem(
            title: "关于 Yoo Windows Manager",
            action: #selector(showAbout),
            keyEquivalent: ""
        )
        aboutItem.target = self
        menu.addItem(aboutItem)
        menu.addItem(.separator())

        let accessibilityItem = NSMenuItem(
            title: "",
            action: #selector(requestAccessibilityPermission),
            keyEquivalent: ""
        )
        accessibilityItem.target = self
        menu.addItem(accessibilityItem)
        accessibilityMenuItem = accessibilityItem
        updateAccessibilityMenuItem()

        menu.addItem(.separator())
        let quitItem = NSMenuItem(title: "退出", action: #selector(quitApplication), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
        statusItem?.menu = menu
    }

    private func configureApplicationIcon() {
        guard let iconURL = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
              let icon = NSImage(contentsOf: iconURL)
        else { return }
        NSApp.applicationIconImage = icon
    }

    @objc private func relayoutNow() {
        guard ensureAccessibilityPermission() else { return }
        relayoutAllScreensIfNeeded(force: true, animated: settings.animateRelayout)
    }

    @objc private func openSettings() {
        settingsWindow.show()
    }

    @objc private func showAbout() {
        NSApp.activate(ignoringOtherApps: true)
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        let credits = """
        严格二分窗口管理器

        支持多显示器、窗口间距、实时缩放联动、拖动交换和可配置全局快捷键。

        安装位置：\(Bundle.main.bundlePath)
        """
        NSApp.orderFrontStandardAboutPanel(options: [
            .applicationName: "Yoo Windows Manager",
            .applicationVersion: version,
            .version: "版本 \(version)（\(build)）",
            .credits: NSAttributedString(string: credits),
        ])
    }

    private func reorderFocusedWindow(_ change: WindowOrderChange) {
        guard ensureAccessibilityPermission() else { return }
        guard let focused = discovery.frontmostWindow(excludingPID: ownPID) else { return }
        guard let screen = NSScreen.screens.first(where: { screen in
            discovery.windows(on: screen, excludingPID: ownPID)
                .contains { $0.windowID == focused.windowID }
        }) else { return }

        let discovered = discovery.windows(on: screen, excludingPID: ownPID)
        var workspace = store.workspace(for: screen)
        var ordered = engine.stabilize(discovered: discovered, previousOrder: workspace.windowOrder)
        guard let index = ordered.firstIndex(where: { $0.windowID == focused.windowID }) else { return }

        switch change {
        case .first:
            let window = ordered.remove(at: index)
            ordered.insert(window, at: 0)
        case .up:
            guard index > 0 else { return }
            ordered.swapAt(index, index - 1)
        case .down:
            guard index + 1 < ordered.count else { return }
            ordered.swapAt(index, index + 1)
        }

        workspace.windowOrder = ordered.map(\.windowID)
        store.update(workspace)
        relayoutAllScreensIfNeeded(force: true, animated: settings.animateRelayout)
    }

    @objc private func requestAccessibilityPermission() {
        guard !ax.isTrusted() else { return }
        openAccessibilitySettings()
    }

    func menuWillOpen(_ menu: NSMenu) {
        updateAccessibilityMenuItem()
    }

    @objc private func quitApplication() {
        NSApp.terminate(nil)
    }

    @objc private func workspaceDidChange() {
        relayoutAllScreensIfNeeded(animated: false)
    }

    private func handleDragBegan(startPoint: CGPoint) {
        screenAssignmentAtDragStart = screenAssignmentSignature()
        draggedWindowID = nil
        draggedScreenName = nil
        draggedWindowInitialFrame = nil
        draggedRootAtStart = nil
        draggedExpectedFrameAtStart = nil
        dragStartPoint = startPoint
        isResizingManagedWindow = false

        guard let window = discovery.frontmostWindow(excludingPID: ownPID) else { return }
        guard let screen = NSScreen.screens.first(where: { screen in
            discovery.windows(on: screen, excludingPID: ownPID)
                .contains { $0.windowID == window.windowID }
        }) else { return }

        draggedWindowID = window.windowID
        draggedScreenName = screen.localizedName
        draggedWindowInitialFrame = discovery.cocoaFrame(
            for: window.windowID,
            excludingPID: ownPID
        )
        let workspace = store.workspace(for: screen)
        draggedRootAtStart = workspace.root
        draggedExpectedFrameAtStart = workspace.root
            .resolvedPlacements(in: workspace.usableFrame)
            .first(where: { $0.window.windowID == window.windowID })?
            .frame
    }

    private func handleDragChanged(currentPoint: CGPoint) {
        guard let draggedWindowID,
              let draggedScreenName,
              let initialFrame = draggedWindowInitialFrame,
              let currentFrame = discovery.cocoaFrame(for: draggedWindowID, excludingPID: ownPID),
              let screen = NSScreen.screens.first(where: { $0.localizedName == draggedScreenName })
        else {
            dragFeedback.hide()
            return
        }

        if windowSizeChanged(from: initialFrame, to: currentFrame) {
            dragFeedback.hide()
            handleResizeChanged(
                windowID: draggedWindowID,
                screen: screen,
                initialFrame: initialFrame,
                currentFrame: currentFrame
            )
            return
        }

        guard let movedDistance = windowDragDistance(from: initialFrame, to: currentFrame),
              movedDistance > 1,
              let startPoint = dragStartPoint
        else {
            dragFeedback.hide()
            return
        }

        let workspace = store.workspace(for: screen)
        let rawPlacements = workspace.root.resolvedPlacements(in: workspace.usableFrame)
        let visiblePlacements = placements(for: workspace)
        guard let sourceFrame = visiblePlacements
            .first(where: { $0.window.windowID == draggedWindowID })?
            .frame
        else {
            dragFeedback.hide()
            return
        }

        let dragDistance = hypot(currentPoint.x - startPoint.x, currentPoint.y - startPoint.y)
        let targetID = rawPlacements
            .first(where: { $0.window.windowID != draggedWindowID && $0.frame.contains(currentPoint) })?
            .window.windowID

        guard settings.showDragFeedback else {
            dragFeedback.hide()
            return
        }

        if dragDistance >= settings.swapDistance,
           let targetID,
           let targetFrame = visiblePlacements.first(where: { $0.window.windowID == targetID })?.frame
        {
            dragFeedback.show(frame: targetFrame, state: .swap)
        } else {
            dragFeedback.show(frame: sourceFrame, state: .restore)
        }
    }

    private func handleResizeChanged(
        windowID: UInt32,
        screen: NSScreen,
        initialFrame: CGRect,
        currentFrame: CGRect
    ) {
        guard let rootAtStart = draggedRootAtStart,
              let expectedFrame = draggedExpectedFrameAtStart
        else { return }

        let projectedFrame = CGRect(
            x: expectedFrame.minX + currentFrame.minX - initialFrame.minX,
            y: expectedFrame.minY + currentFrame.minY - initialFrame.minY,
            width: expectedFrame.width + currentFrame.width - initialFrame.width,
            height: expectedFrame.height + currentFrame.height - initialFrame.height
        )

        var workspace = store.workspace(for: screen)
        workspace.root = rootAtStart.adjustingSplitRatios(
            for: windowID,
            expectedFrame: expectedFrame,
            projectedFrame: projectedFrame,
            in: workspace.usableFrame
        )
        store.update(workspace)
        isResizingManagedWindow = true
        applyWorkspace(workspace, excludingWindowID: windowID, animated: false)
    }

    private func handleInteractionEnded(dropPoint: CGPoint) {
        defer {
            draggedWindowID = nil
            draggedScreenName = nil
            draggedWindowInitialFrame = nil
            draggedRootAtStart = nil
            draggedExpectedFrameAtStart = nil
            dragStartPoint = nil
            isResizingManagedWindow = false
        }

        if isResizingManagedWindow {
            guard let draggedScreenName,
                  let screen = NSScreen.screens.first(where: { $0.localizedName == draggedScreenName })
            else { return }
            applyWorkspace(store.workspace(for: screen), animated: false)
            return
        }

        let assignmentNow = screenAssignmentSignature()
        let crossDisplay = assignmentNow != screenAssignmentAtDragStart
        if crossDisplay {
            relayoutAllScreensIfNeeded(force: true, animated: settings.animateRelayout)
            return
        }

        guard let draggedWindowID,
              let draggedScreenName,
              let initialFrame = draggedWindowInitialFrame,
              let finalFrame = discovery.cocoaFrame(for: draggedWindowID, excludingPID: ownPID),
              let dragDistance = windowDragDistance(from: initialFrame, to: finalFrame),
              dragDistance > 1,
              let startPoint = dragStartPoint,
              let screen = NSScreen.screens.first(where: { $0.localizedName == draggedScreenName })
        else { return }

        let pointerDistance = hypot(dropPoint.x - startPoint.x, dropPoint.y - startPoint.y)
        if pointerDistance >= settings.swapDistance {
            swapDraggedWindow(draggedWindowID, on: screen, at: dropPoint)
        }

        // 没达到交换阈值或没有命中其他槽位时，按原顺序恢复窗口位置。
        relayoutAllScreensIfNeeded(force: true, animated: settings.animateRelayout)
    }

    private func windowDragDistance(from initialFrame: CGRect, to finalFrame: CGRect) -> CGFloat? {
        guard !windowSizeChanged(from: initialFrame, to: finalFrame) else { return nil }
        return hypot(
            finalFrame.origin.x - initialFrame.origin.x,
            finalFrame.origin.y - initialFrame.origin.y
        )
    }

    private func windowSizeChanged(from initialFrame: CGRect, to currentFrame: CGRect) -> Bool {
        abs(currentFrame.width - initialFrame.width) > 2
            || abs(currentFrame.height - initialFrame.height) > 2
    }

    private func applyWorkspace(
        _ workspace: LayoutWorkspace,
        excludingWindowID: UInt32? = nil,
        animated: Bool
    ) {
        guard ax.isTrusted(), !isApplyingLayout else { return }
        let placements = placements(for: workspace).filter { placement in
            placement.window.windowID != excludingWindowID
        }
        guard !placements.isEmpty else { return }

        isApplyingLayout = true
        defer { isApplyingLayout = false }
        let startingFrames = discovery.cocoaFramesByID(excludingPID: ownPID)
        try? ax.apply(placements: placements, startingFrames: startingFrames, animated: animated)
    }

    /// 鼠标松开在哪个原始二分槽位，就与该槽位里的窗口交换顺序。
    @discardableResult
    private func swapDraggedWindow(_ draggedWindowID: UInt32, on screen: NSScreen, at dropPoint: CGPoint) -> Bool {
        guard screen.frame.contains(dropPoint) else { return false }

        let discovered = discovery.windows(on: screen, excludingPID: ownPID)
        var workspace = store.workspace(for: screen)
        var ordered = engine.stabilize(discovered: discovered, previousOrder: workspace.windowOrder)
        guard let draggedIndex = ordered.firstIndex(where: { $0.windowID == draggedWindowID }) else {
            return false
        }

        // 使用未 inset 的槽位命中测试，窗口之间的可配置间距也归属于相邻槽位。
        guard let targetID = workspace.root
            .resolvedPlacements(in: workspace.usableFrame)
            .first(where: { $0.window.windowID != draggedWindowID && $0.frame.contains(dropPoint) })?
            .window.windowID,
              let targetIndex = ordered.firstIndex(where: { $0.windowID == targetID })
        else { return false }

        ordered.swapAt(draggedIndex, targetIndex)
        workspace.windowOrder = ordered.map(\.windowID)
        store.update(workspace)
        return true
    }

    private func startAutoLayout() {
        stopAutoLayout()
        if !settings.layoutOnLaunch {
            lastSignature = windowSetSignature()
        }
        autoLayoutTimer = Timer.scheduledTimer(withTimeInterval: settings.autoLayoutInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.autoLayoutTick()
            }
        }
    }

    private func autoLayoutTick() {
        let isTrusted = ax.isTrusted()
        if isTrusted != lastAccessibilityTrusted {
            lastAccessibilityTrusted = isTrusted
            updateAccessibilityMenuItem()
            if isTrusted {
                lastSignature = ""
                relayoutAllScreensIfNeeded(force: true, animated: settings.animateRelayout)
                return
            }
        }
        relayoutAllScreensIfNeeded(animated: false)
    }

    private func stopAutoLayout() {
        autoLayoutTimer?.invalidate()
        autoLayoutTimer = nil
        lastSignature = ""
        lastScreenByWindow = [:]
        screenAssignmentAtDragStart = ""
        draggedWindowID = nil
        draggedScreenName = nil
        draggedWindowInitialFrame = nil
        draggedRootAtStart = nil
        draggedExpectedFrameAtStart = nil
        dragStartPoint = nil
        isResizingManagedWindow = false
    }

    private func settingsDidChange(_ change: SettingsChange) {
        switch change {
        case .layout:
            applyAllCurrentWorkspaces()
        case .timer:
            startAutoLayout()
        case .hotkeys:
            hotkeys.reload(shortcuts: settings.shortcuts)
        case .behavior:
            if !settings.showDragFeedback {
                dragFeedback.hide()
            }
        }
    }

    private func placements(for workspace: LayoutWorkspace) -> [WindowPlacement] {
        workspace.placements(windowGap: settings.windowGap, edgeGap: settings.edgeGap)
    }

    private func applyAllCurrentWorkspaces() {
        guard ax.isTrusted(), !isApplyingLayout else { return }
        let allPlacements = NSScreen.screens.flatMap { screen in
            placements(for: store.workspace(for: screen))
        }
        guard !allPlacements.isEmpty else { return }

        isApplyingLayout = true
        defer { isApplyingLayout = false }
        let startingFrames = discovery.cocoaFramesByID(excludingPID: ownPID)
        try? ax.apply(placements: allPlacements, startingFrames: startingFrames, animated: false)
    }

    private func relayoutAllScreensIfNeeded(force: Bool = false, animated: Bool = false) {
        guard ax.isTrusted(), !isApplyingLayout else { return }
        guard !interactionPause.shouldSuppressLayout else { return }
        let signature = windowSetSignature()
        if !force {
            guard signature != lastSignature else { return }
        }
        lastSignature = signature
        relayoutAllScreens(animated: animated)
    }

    private func windowSetSignature() -> String {
        store.syncScreens()
        return NSScreen.screens
            .map { screen in
                let windows = discovery.windows(on: screen, excludingPID: ownPID)
                return "\(screen.localizedName):\(windows.map(\.windowID).sorted())"
            }
            .joined(separator: "|")
    }

    private func screenAssignmentSignature() -> String {
        var pairs: [String] = []
        for screen in NSScreen.screens {
            for window in discovery.windows(on: screen, excludingPID: ownPID) {
                pairs.append("\(window.windowID)@\(screen.localizedName)")
            }
        }
        return pairs.sorted().joined(separator: ",")
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
                if settings.movedWindowFirst {
                    workspace.windowOrder.insert(windowID, at: 0)
                } else {
                    workspace.windowOrder.append(windowID)
                }
                store.update(workspace)
            }
        }

        lastScreenByWindow = currentByWindow
    }

    private func relayoutAllScreens(animated: Bool) {
        guard !isApplyingLayout else { return }
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
            allPlacements.append(contentsOf: placements(for: workspace))
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
        if ax.isTrusted() {
            lastAccessibilityTrusted = true
            updateAccessibilityMenuItem()
            return true
        }
        openAccessibilitySettings()
        return false
    }

    private func openAccessibilitySettings() {
        UserDefaults.standard.set(true, forKey: Self.didOpenAccessibilitySettingsKey)
        ax.openAccessibilitySettings()
        updateAccessibilityMenuItem()
    }

    private func updateAccessibilityMenuItem() {
        let trusted = ax.isTrusted()
        accessibilityMenuItem?.title = trusted
            ? "辅助功能权限：已授权"
            : "辅助功能权限：未授权…"
        accessibilityMenuItem?.isEnabled = !trusted
    }

}
