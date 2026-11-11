import Carbon.HIToolbox
import Foundation

final class HotkeyService: @unchecked Sendable {
    var onRelayout: (() -> Void)?
    var onPromoteFirst: (() -> Void)?
    var onMoveUp: (() -> Void)?
    var onMoveDown: (() -> Void)?

    private var eventHandler: EventHandlerRef?
    private var hotKeyRefs: [EventHotKeyRef] = []
    private let relayoutHotKeyID: UInt32 = 1
    private let promoteFirstHotKeyID: UInt32 = 2
    private let moveUpHotKeyID: UInt32 = 3
    private let moveDownHotKeyID: UInt32 = 4

    func start() {
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

        registerHotKey(
            id: relayoutHotKeyID,
            keyCode: UInt32(kVK_ANSI_R),
            modifiers: UInt32(controlKey | shiftKey)
        )
        registerHotKey(
            id: promoteFirstHotKeyID,
            keyCode: UInt32(kVK_Return),
            modifiers: UInt32(controlKey | shiftKey)
        )
        registerHotKey(
            id: moveUpHotKeyID,
            keyCode: UInt32(kVK_ANSI_I),
            modifiers: UInt32(controlKey | shiftKey)
        )
        registerHotKey(
            id: moveDownHotKeyID,
            keyCode: UInt32(kVK_ANSI_J),
            modifiers: UInt32(controlKey | shiftKey)
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
        case relayoutHotKeyID:
            onRelayout?()
        case promoteFirstHotKeyID:
            onPromoteFirst?()
        case moveUpHotKeyID:
            onMoveUp?()
        case moveDownHotKeyID:
            onMoveDown?()
        default:
            break
        }
    }
}
