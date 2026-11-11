import Carbon.HIToolbox
import Foundation

final class HotkeyService: @unchecked Sendable {
    var onRelayout: (() -> Void)?
    var onPromoteFirst: (() -> Void)?
    var onMoveUp: (() -> Void)?
    var onMoveDown: (() -> Void)?

    private var eventHandler: EventHandlerRef?
    private var hotKeyRefs: [EventHotKeyRef] = []
    func start(shortcuts: [HotkeyAction: GlobalShortcut]) {
        if eventHandler == nil {
            installEventHandler()
        }
        reload(shortcuts: shortcuts)
    }

    func reload(shortcuts: [HotkeyAction: GlobalShortcut]) {
        for ref in hotKeyRefs {
            UnregisterEventHotKey(ref)
        }
        hotKeyRefs.removeAll()

        for action in HotkeyAction.allCases {
            guard let shortcut = shortcuts[action], shortcut.isEnabled else { continue }
            registerHotKey(id: action.rawValue, keyCode: shortcut.keyCode, modifiers: shortcut.modifiers)
        }
    }

    private func installEventHandler() {
        guard eventHandler == nil else { return }

        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let selfPointer = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, userData -> OSStatus in
                guard let userData, let event else { return OSStatus(eventNotHandledErr) }
                let service = Unmanaged<HotkeyService>.fromOpaque(userData).takeUnretainedValue()
                service.handle(event: event)
                return noErr
            },
            1,
            &eventType,
            selfPointer,
            &eventHandler
        )
    }

    deinit {
        for ref in hotKeyRefs {
            UnregisterEventHotKey(ref)
        }
        if let eventHandler {
            RemoveEventHandler(eventHandler)
        }
    }

    private func registerHotKey(id: UInt32, keyCode: UInt32, modifiers: UInt32) {
        var hotKeyRef: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: OSType(0x594F4F57), id: id)
        RegisterEventHotKey(keyCode, modifiers, hotKeyID, GetApplicationEventTarget(), 0, &hotKeyRef)
        if let hotKeyRef {
            hotKeyRefs.append(hotKeyRef)
        }
    }

    private func handle(event: EventRef) {
        var hotKeyID = EventHotKeyID()
        let status = GetEventParameter(
            event,
            EventParamName(kEventParamDirectObject),
            EventParamType(typeEventHotKeyID),
            nil,
            MemoryLayout<EventHotKeyID>.size,
            nil,
            &hotKeyID
        )
        guard status == noErr else { return }
        switch hotKeyID.id {
        case HotkeyAction.relayout.rawValue:
            onRelayout?()
        case HotkeyAction.promoteFirst.rawValue:
            onPromoteFirst?()
        case HotkeyAction.moveUp.rawValue:
            onMoveUp?()
        case HotkeyAction.moveDown.rawValue:
            onMoveDown?()
        default:
            break
        }
    }
}
