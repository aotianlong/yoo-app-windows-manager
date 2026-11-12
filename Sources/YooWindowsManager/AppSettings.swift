import AppKit
import Carbon.HIToolbox
import ServiceManagement

enum SettingsChange {
    case layout
    case timer
    case hotkeys
    case behavior
}

enum HotkeyAction: UInt32, CaseIterable, Hashable {
    case relayout = 1
    case promoteFirst = 2
    case moveUp = 3
    case moveDown = 4

    var title: String {
        switch self {
        case .relayout: L10n.text("hotkey.relayout")
        case .promoteFirst: L10n.text("hotkey.promote_first")
        case .moveUp: L10n.text("hotkey.move_up")
        case .moveDown: L10n.text("hotkey.move_down")
        }
    }

    var defaultsPrefix: String { "hotkey.\(rawValue)" }

    var defaultShortcut: GlobalShortcut {
        switch self {
        case .relayout:
            GlobalShortcut(keyCode: UInt32(kVK_ANSI_R), modifiers: UInt32(controlKey | shiftKey))
        case .promoteFirst:
            GlobalShortcut(keyCode: UInt32(kVK_Return), modifiers: UInt32(controlKey | shiftKey))
        case .moveUp:
            GlobalShortcut(keyCode: UInt32(kVK_ANSI_I), modifiers: UInt32(controlKey | shiftKey))
        case .moveDown:
            GlobalShortcut(keyCode: UInt32(kVK_ANSI_J), modifiers: UInt32(controlKey | shiftKey))
        }
    }
}

struct GlobalShortcut: Equatable {
    var keyCode: UInt32
    var modifiers: UInt32
    var isEnabled = true

    var displayName: String {
        guard isEnabled else { return L10n.text("hotkey.not_set") }
        var value = ""
        if modifiers & UInt32(controlKey) != 0 { value += "⌃" }
        if modifiers & UInt32(optionKey) != 0 { value += "⌥" }
        if modifiers & UInt32(shiftKey) != 0 { value += "⇧" }
        if modifiers & UInt32(cmdKey) != 0 { value += "⌘" }
        return value + Self.keyName(keyCode)
    }

    static func from(event: NSEvent) -> GlobalShortcut? {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        var modifiers: UInt32 = 0
        if flags.contains(.control) { modifiers |= UInt32(controlKey) }
        if flags.contains(.option) { modifiers |= UInt32(optionKey) }
        if flags.contains(.shift) { modifiers |= UInt32(shiftKey) }
        if flags.contains(.command) { modifiers |= UInt32(cmdKey) }
        guard modifiers != 0 else { return nil }
        return GlobalShortcut(keyCode: UInt32(event.keyCode), modifiers: modifiers)
    }

    private static func keyName(_ keyCode: UInt32) -> String {
        let names: [UInt32: String] = [
            UInt32(kVK_Return): "↩",
            UInt32(kVK_Tab): "⇥",
            UInt32(kVK_Space): "Space",
            UInt32(kVK_Delete): "⌫",
            UInt32(kVK_ForwardDelete): "⌦",
            UInt32(kVK_Escape): "⎋",
            UInt32(kVK_LeftArrow): "←",
            UInt32(kVK_RightArrow): "→",
            UInt32(kVK_UpArrow): "↑",
            UInt32(kVK_DownArrow): "↓",
            UInt32(kVK_Home): "Home",
            UInt32(kVK_End): "End",
            UInt32(kVK_PageUp): "Page Up",
            UInt32(kVK_PageDown): "Page Down",
        ]
        if let name = names[keyCode] { return name }

        let letterCodes: [UInt32: String] = [
            UInt32(kVK_ANSI_A): "A", UInt32(kVK_ANSI_B): "B", UInt32(kVK_ANSI_C): "C",
            UInt32(kVK_ANSI_D): "D", UInt32(kVK_ANSI_E): "E", UInt32(kVK_ANSI_F): "F",
            UInt32(kVK_ANSI_G): "G", UInt32(kVK_ANSI_H): "H", UInt32(kVK_ANSI_I): "I",
            UInt32(kVK_ANSI_J): "J", UInt32(kVK_ANSI_K): "K", UInt32(kVK_ANSI_L): "L",
            UInt32(kVK_ANSI_M): "M", UInt32(kVK_ANSI_N): "N", UInt32(kVK_ANSI_O): "O",
            UInt32(kVK_ANSI_P): "P", UInt32(kVK_ANSI_Q): "Q", UInt32(kVK_ANSI_R): "R",
            UInt32(kVK_ANSI_S): "S", UInt32(kVK_ANSI_T): "T", UInt32(kVK_ANSI_U): "U",
            UInt32(kVK_ANSI_V): "V", UInt32(kVK_ANSI_W): "W", UInt32(kVK_ANSI_X): "X",
            UInt32(kVK_ANSI_Y): "Y", UInt32(kVK_ANSI_Z): "Z",
            UInt32(kVK_ANSI_0): "0", UInt32(kVK_ANSI_1): "1", UInt32(kVK_ANSI_2): "2",
            UInt32(kVK_ANSI_3): "3", UInt32(kVK_ANSI_4): "4", UInt32(kVK_ANSI_5): "5",
            UInt32(kVK_ANSI_6): "6", UInt32(kVK_ANSI_7): "7", UInt32(kVK_ANSI_8): "8",
            UInt32(kVK_ANSI_9): "9",
        ]
        return letterCodes[keyCode] ?? L10n.format("hotkey.unknown_key_format", keyCode)
    }
}

@MainActor
final class AppSettings {
    private enum Key {
        static let windowGap = "layout.windowGap"
        static let edgeGap = "layout.edgeGap"
        static let swapDistance = "interaction.swapDistance"
        static let showDragFeedback = "interaction.showDragFeedback"
        static let animateRelayout = "layout.animateRelayout"
        static let autoLayoutInterval = "layout.autoLayoutInterval"
        static let movedWindowFirst = "behavior.movedWindowFirst"
        static let layoutOnLaunch = "behavior.layoutOnLaunch"
        static let launchAtLogin = "general.launchAtLogin"
    }

    var onChange: ((SettingsChange) -> Void)?
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        var registered: [String: Any] = [
            Key.windowGap: 10.0,
            Key.edgeGap: 5.0,
            Key.swapDistance: 80.0,
            Key.showDragFeedback: true,
            Key.animateRelayout: true,
            Key.autoLayoutInterval: 1.5,
            Key.movedWindowFirst: true,
            Key.layoutOnLaunch: true,
            Key.launchAtLogin: false,
        ]
        for action in HotkeyAction.allCases {
            let shortcut = action.defaultShortcut
            registered["\(action.defaultsPrefix).keyCode"] = Int(shortcut.keyCode)
            registered["\(action.defaultsPrefix).modifiers"] = Int(shortcut.modifiers)
            registered["\(action.defaultsPrefix).enabled"] = true
        }
        defaults.register(defaults: registered)
    }

    var windowGap: CGFloat {
        get { CGFloat(defaults.double(forKey: Key.windowGap)) }
        set { set(Double(newValue.clamped(to: 0 ... 40)), for: Key.windowGap, change: .layout) }
    }

    var edgeGap: CGFloat {
        get { CGFloat(defaults.double(forKey: Key.edgeGap)) }
        set { set(Double(newValue.clamped(to: 0 ... 40)), for: Key.edgeGap, change: .layout) }
    }

    var swapDistance: CGFloat {
        get { CGFloat(defaults.double(forKey: Key.swapDistance)) }
        set { set(Double(newValue.clamped(to: 20 ... 300)), for: Key.swapDistance, change: .behavior) }
    }

    var showDragFeedback: Bool {
        get { defaults.bool(forKey: Key.showDragFeedback) }
        set { set(newValue, for: Key.showDragFeedback, change: .behavior) }
    }

    var animateRelayout: Bool {
        get { defaults.bool(forKey: Key.animateRelayout) }
        set { set(newValue, for: Key.animateRelayout, change: .behavior) }
    }

    var autoLayoutInterval: TimeInterval {
        get { defaults.double(forKey: Key.autoLayoutInterval) }
        set { set(newValue.clamped(to: 0.5 ... 5), for: Key.autoLayoutInterval, change: .timer) }
    }

    var movedWindowFirst: Bool {
        get { defaults.bool(forKey: Key.movedWindowFirst) }
        set { set(newValue, for: Key.movedWindowFirst, change: .behavior) }
    }

    var layoutOnLaunch: Bool {
        get { defaults.bool(forKey: Key.layoutOnLaunch) }
        set { set(newValue, for: Key.layoutOnLaunch, change: .behavior) }
    }

    var launchAtLogin: Bool { defaults.bool(forKey: Key.launchAtLogin) }

    func setLaunchAtLogin(_ enabled: Bool) throws {
        if enabled {
            if SMAppService.mainApp.status != .enabled {
                try SMAppService.mainApp.register()
            }
        } else if SMAppService.mainApp.status == .enabled {
            try SMAppService.mainApp.unregister()
        }
        set(enabled, for: Key.launchAtLogin, change: .behavior)
    }

    func shortcut(for action: HotkeyAction) -> GlobalShortcut {
        GlobalShortcut(
            keyCode: UInt32(defaults.integer(forKey: "\(action.defaultsPrefix).keyCode")),
            modifiers: UInt32(defaults.integer(forKey: "\(action.defaultsPrefix).modifiers")),
            isEnabled: defaults.bool(forKey: "\(action.defaultsPrefix).enabled")
        )
    }

    var shortcuts: [HotkeyAction: GlobalShortcut] {
        Dictionary(uniqueKeysWithValues: HotkeyAction.allCases.map { ($0, shortcut(for: $0)) })
    }

    func setShortcut(_ shortcut: GlobalShortcut, for action: HotkeyAction) {
        defaults.set(Int(shortcut.keyCode), forKey: "\(action.defaultsPrefix).keyCode")
        defaults.set(Int(shortcut.modifiers), forKey: "\(action.defaultsPrefix).modifiers")
        defaults.set(shortcut.isEnabled, forKey: "\(action.defaultsPrefix).enabled")
        onChange?(.hotkeys)
    }

    func resetToDefaults() throws {
        windowGap = 10
        edgeGap = 5
        swapDistance = 80
        showDragFeedback = true
        animateRelayout = true
        autoLayoutInterval = 1.5
        movedWindowFirst = true
        layoutOnLaunch = true
        try setLaunchAtLogin(false)
        for action in HotkeyAction.allCases {
            setShortcut(action.defaultShortcut, for: action)
        }
    }

    private func set(_ value: Any, for key: String, change: SettingsChange) {
        defaults.set(value, forKey: key)
        onChange?(change)
    }
}

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
