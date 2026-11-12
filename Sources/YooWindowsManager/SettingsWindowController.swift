import AppKit
import Carbon.HIToolbox

@MainActor
final class SettingsWindowController: NSWindowController {
    private let settings: AppSettings

    private let launchAtLoginCheckbox = NSButton(
        checkboxWithTitle: L10n.text("settings.launch_at_login"), target: nil, action: nil
    )
    private let layoutOnLaunchCheckbox = NSButton(
        checkboxWithTitle: L10n.text("settings.layout_on_launch"), target: nil, action: nil
    )
    private let movedWindowFirstCheckbox = NSButton(
        checkboxWithTitle: L10n.text("settings.moved_window_first"), target: nil, action: nil
    )
    private let animationCheckbox = NSButton(
        checkboxWithTitle: L10n.text("settings.animate_relayout"), target: nil, action: nil
    )
    private let feedbackCheckbox = NSButton(
        checkboxWithTitle: L10n.text("settings.show_drag_feedback"), target: nil, action: nil
    )

    private let windowGapSlider = NSSlider(value: 10, minValue: 0, maxValue: 40, target: nil, action: nil)
    private let edgeGapSlider = NSSlider(value: 5, minValue: 0, maxValue: 40, target: nil, action: nil)
    private let swapDistanceSlider = NSSlider(value: 80, minValue: 20, maxValue: 300, target: nil, action: nil)
    private let intervalSlider = NSSlider(value: 1.5, minValue: 0.5, maxValue: 5, target: nil, action: nil)
    private let windowGapValue = NSTextField(labelWithString: "")
    private let edgeGapValue = NSTextField(labelWithString: "")
    private let swapDistanceValue = NSTextField(labelWithString: "")
    private let intervalValue = NSTextField(labelWithString: "")
    private var shortcutButtons: [HotkeyAction: ShortcutRecorderButton] = [:]

    init(settings: AppSettings) {
        self.settings = settings
        super.init(window: nil)
        window = makeWindow()
        refreshControls()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show() {
        refreshControls()
        NSApp.activate(ignoringOtherApps: true)
        window?.center()
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 700, height: 520),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = L10n.text("settings.window_title")
        window.isReleasedWhenClosed = false

        let tabs = NSTabView()
        tabs.translatesAutoresizingMaskIntoConstraints = false
        tabs.addTabViewItem(tabItem(label: L10n.text("settings.tab.general"), view: makeGeneralView()))
        tabs.addTabViewItem(tabItem(label: L10n.text("settings.tab.layout"), view: makeLayoutView()))
        tabs.addTabViewItem(tabItem(label: L10n.text("settings.tab.hotkeys"), view: makeHotkeysView()))

        let resetButton = NSButton(
            title: L10n.text("settings.reset_defaults"),
            target: self,
            action: #selector(resetDefaults)
        )
        resetButton.bezelStyle = .rounded
        resetButton.translatesAutoresizingMaskIntoConstraints = false

        let content = NSView()
        content.addSubview(tabs)
        content.addSubview(resetButton)
        window.contentView = content
        NSLayoutConstraint.activate([
            tabs.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 18),
            tabs.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -18),
            tabs.topAnchor.constraint(equalTo: content.topAnchor, constant: 18),
            tabs.bottomAnchor.constraint(equalTo: resetButton.topAnchor, constant: -12),
            resetButton.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -22),
            resetButton.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -18),
        ])
        return window
    }

    private func makeGeneralView() -> NSView {
        configureCheckbox(launchAtLoginCheckbox)
        configureCheckbox(layoutOnLaunchCheckbox)
        configureCheckbox(movedWindowFirstCheckbox)

        let note = NSTextField(wrappingLabelWithString: L10n.text("settings.accessibility_note"))
        note.textColor = .secondaryLabelColor
        let stack = verticalStack([
            sectionTitle(L10n.text("settings.section.startup")),
            launchAtLoginCheckbox,
            layoutOnLaunchCheckbox,
            note,
            sectionTitle(L10n.text("settings.section.cross_display")),
            movedWindowFirstCheckbox,
        ])
        return padded(stack)
    }

    private func makeLayoutView() -> NSView {
        configureCheckbox(animationCheckbox)
        configureCheckbox(feedbackCheckbox)
        configureSlider(windowGapSlider)
        configureSlider(edgeGapSlider)
        configureSlider(swapDistanceSlider)
        configureSlider(intervalSlider)

        let stack = verticalStack([
            sectionTitle(L10n.text("settings.section.spacing")),
            sliderRow(title: L10n.text("settings.window_gap"), slider: windowGapSlider, value: windowGapValue),
            sliderRow(title: L10n.text("settings.edge_gap"), slider: edgeGapSlider, value: edgeGapValue),
            sectionTitle(L10n.text("settings.section.interaction")),
            sliderRow(
                title: L10n.text("settings.swap_distance"),
                slider: swapDistanceSlider,
                value: swapDistanceValue
            ),
            feedbackCheckbox,
            animationCheckbox,
            sectionTitle(L10n.text("settings.section.auto_detection")),
            sliderRow(
                title: L10n.text("settings.auto_layout_interval"),
                slider: intervalSlider,
                value: intervalValue
            ),
        ])
        return padded(stack)
    }

    private func makeHotkeysView() -> NSView {
        let stack = verticalStack([sectionTitle(L10n.text("settings.section.global_hotkeys"))])
        for action in HotkeyAction.allCases {
            let button = ShortcutRecorderButton(shortcut: settings.shortcut(for: action))
            button.onRecord = { [weak self, weak button] shortcut in
                guard let self else { return false }
                if shortcut.isEnabled,
                   let conflict = HotkeyAction.allCases.first(where: {
                       $0 != action && self.settings.shortcut(for: $0) == shortcut
                   })
                {
                    self.showAlert(
                        title: L10n.text("settings.hotkey_conflict_title"),
                        message: L10n.format("settings.hotkey_conflict_format", conflict.title)
                    )
                    button?.setShortcut(self.settings.shortcut(for: action))
                    return false
                }
                self.settings.setShortcut(shortcut, for: action)
                return true
            }
            shortcutButtons[action] = button

            let label = NSTextField(labelWithString: action.title)
            label.setContentHuggingPriority(.defaultLow, for: .horizontal)
            button.widthAnchor.constraint(equalToConstant: 160).isActive = true
            let row = NSStackView(views: [label, button])
            row.orientation = .horizontal
            row.alignment = .centerY
            row.distribution = .fill
            row.spacing = 16
            stack.addArrangedSubview(row)
        }

        let help = NSTextField(wrappingLabelWithString: L10n.text("settings.hotkey_help"))
        help.textColor = .secondaryLabelColor
        stack.addArrangedSubview(help)
        return padded(stack)
    }

    private func configureCheckbox(_ checkbox: NSButton) {
        checkbox.target = self
        checkbox.action = #selector(checkboxChanged(_:))
    }

    private func configureSlider(_ slider: NSSlider) {
        slider.target = self
        slider.action = #selector(sliderChanged(_:))
        slider.isContinuous = true
    }

    @objc private func checkboxChanged(_ sender: NSButton) {
        let enabled = sender.state == .on
        switch sender {
        case launchAtLoginCheckbox:
            do {
                try settings.setLaunchAtLogin(enabled)
            } catch {
                sender.state = settings.launchAtLogin ? .on : .off
                showAlert(title: L10n.text("settings.launch_at_login_error"), message: error.localizedDescription)
            }
        case layoutOnLaunchCheckbox:
            settings.layoutOnLaunch = enabled
        case movedWindowFirstCheckbox:
            settings.movedWindowFirst = enabled
        case animationCheckbox:
            settings.animateRelayout = enabled
        case feedbackCheckbox:
            settings.showDragFeedback = enabled
        default:
            break
        }
    }

    @objc private func sliderChanged(_ sender: NSSlider) {
        switch sender {
        case windowGapSlider:
            settings.windowGap = CGFloat(sender.doubleValue.rounded())
        case edgeGapSlider:
            settings.edgeGap = CGFloat(sender.doubleValue.rounded())
        case swapDistanceSlider:
            settings.swapDistance = CGFloat(sender.doubleValue.rounded())
        case intervalSlider:
            settings.autoLayoutInterval = (sender.doubleValue * 10).rounded() / 10
        default:
            break
        }
        refreshValueLabels()
    }

    @objc private func resetDefaults() {
        do {
            try settings.resetToDefaults()
            refreshControls()
        } catch {
            showAlert(title: L10n.text("settings.reset_error"), message: error.localizedDescription)
        }
    }

    private func refreshControls() {
        launchAtLoginCheckbox.state = settings.launchAtLogin ? .on : .off
        layoutOnLaunchCheckbox.state = settings.layoutOnLaunch ? .on : .off
        movedWindowFirstCheckbox.state = settings.movedWindowFirst ? .on : .off
        animationCheckbox.state = settings.animateRelayout ? .on : .off
        feedbackCheckbox.state = settings.showDragFeedback ? .on : .off
        windowGapSlider.doubleValue = Double(settings.windowGap)
        edgeGapSlider.doubleValue = Double(settings.edgeGap)
        swapDistanceSlider.doubleValue = Double(settings.swapDistance)
        intervalSlider.doubleValue = settings.autoLayoutInterval
        for (action, button) in shortcutButtons {
            button.setShortcut(settings.shortcut(for: action))
        }
        refreshValueLabels()
    }

    private func refreshValueLabels() {
        windowGapValue.stringValue = "\(Int(settings.windowGap)) pt"
        edgeGapValue.stringValue = "\(Int(settings.edgeGap)) pt"
        swapDistanceValue.stringValue = "\(Int(settings.swapDistance)) pt"
        intervalValue.stringValue = L10n.format("settings.seconds_format", settings.autoLayoutInterval)
    }

    private func tabItem(label: String, view: NSView) -> NSTabViewItem {
        let item = NSTabViewItem(identifier: label)
        item.label = label
        item.view = view
        return item
    }

    private func sectionTitle(_ title: String) -> NSTextField {
        let label = NSTextField(labelWithString: title)
        label.font = .systemFont(ofSize: 13, weight: .semibold)
        return label
    }

    private func verticalStack(_ views: [NSView]) -> NSStackView {
        let stack = NSStackView(views: views)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        return stack
    }

    private func sliderRow(title: String, slider: NSSlider, value: NSTextField) -> NSView {
        let label = NSTextField(labelWithString: title)
        label.widthAnchor.constraint(equalToConstant: 200).isActive = true
        value.alignment = .right
        value.widthAnchor.constraint(equalToConstant: 64).isActive = true
        slider.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let row = NSStackView(views: [label, slider, value])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 12
        row.widthAnchor.constraint(equalToConstant: 600).isActive = true
        return row
    }

    private func padded(_ view: NSView) -> NSView {
        let container = NSView()
        view.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(view)
        NSLayoutConstraint.activate([
            view.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 18),
            view.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor, constant: -18),
            view.topAnchor.constraint(equalTo: container.topAnchor, constant: 20),
        ])
        return container
    }

    private func showAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.runModal()
    }
}

@MainActor
private final class ShortcutRecorderButton: NSButton {
    var onRecord: ((GlobalShortcut) -> Bool)?
    private var shortcut: GlobalShortcut
    private var monitor: Any?

    init(shortcut: GlobalShortcut) {
        self.shortcut = shortcut
        super.init(frame: .zero)
        bezelStyle = .rounded
        target = self
        action = #selector(beginRecording)
        setShortcut(shortcut)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func setShortcut(_ shortcut: GlobalShortcut) {
        self.shortcut = shortcut
        title = shortcut.displayName
    }

    @objc private func beginRecording() {
        stopRecording()
        title = L10n.text("settings.press_shortcut")
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            if event.keyCode == UInt16(kVK_Escape) {
                self.stopRecording()
                self.title = self.shortcut.displayName
                return nil
            }
            if event.keyCode == UInt16(kVK_Delete) || event.keyCode == UInt16(kVK_ForwardDelete) {
                var disabled = self.shortcut
                disabled.isEnabled = false
                if self.onRecord?(disabled) != false { self.setShortcut(disabled) }
                self.stopRecording()
                return nil
            }
            guard let recorded = GlobalShortcut.from(event: event) else {
                NSSound.beep()
                return nil
            }
            if self.onRecord?(recorded) != false { self.setShortcut(recorded) }
            self.stopRecording()
            return nil
        }
    }

    private func stopRecording() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }
}
