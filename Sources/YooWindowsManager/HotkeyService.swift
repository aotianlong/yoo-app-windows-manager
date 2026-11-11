import Carbon.HIToolbox
import Foundation
import YooWindowsManagerCore

final class HotkeyService: @unchecked Sendable {
    var onCommand: ((LayoutCommand) -> Void)?

    private var eventHandler: EventHandlerRef?
    private var hotKeyRefs: [EventHotKeyRef] = []
    private var commandTable: [UInt32: LayoutCommand] = [:]

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

        registerHotKey(id: 1, keyCode: UInt32(kVK_LeftArrow), modifiers: controlOption, command: .splitLeft)
        registerHotKey(id: 2, keyCode: UInt32(kVK_RightArrow), modifiers: controlOption, command: .splitRight)
        registerHotKey(id: 3, keyCode: UInt32(kVK_UpArrow), modifiers: controlOption, command: .splitTop)
        registerHotKey(id: 4, keyCode: UInt32(kVK_DownArrow), modifiers: controlOption, command: .splitBottom)
        registerHotKey(id: 5, keyCode: UInt32(kVK_ANSI_B), modifiers: controlOption, command: .balance)
        registerHotKey(id: 6, keyCode: UInt32(kVK_ANSI_R), modifiers: controlOption, command: .reset)
    }

    deinit {
        for ref in hotKeyRefs {
            UnregisterEventHotKey(ref)
        }
        if let eventHandler {
            RemoveEventHandler(eventHandler)
        }
    }

    private let controlOption = UInt32(controlKey | optionKey)

    private func registerHotKey(id: UInt32, keyCode: UInt32, modifiers: UInt32, command: LayoutCommand) {
        var hotKeyRef: EventHotKeyRef?
        var hotKeyID = EventHotKeyID(signature: OSType(0x594F4F57), id: id)
        RegisterEventHotKey(keyCode, modifiers, hotKeyID, GetApplicationEventTarget(), 0, &hotKeyRef)
        if let hotKeyRef {
            hotKeyRefs.append(hotKeyRef)
        }
        commandTable[id] = command
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
        guard let command = commandTable[hotKeyID.id] else { return }
        onCommand?(command)
    }
}
