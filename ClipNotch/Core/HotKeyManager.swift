import Carbon.HIToolbox

@MainActor
final class HotKeyManager {
    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?

    var onHotKey: (() -> Void)?

    private static var sharedInstance: HotKeyManager?

    func register() {
        HotKeyManager.sharedInstance = self

        var hotKeyID = EventHotKeyID()
        hotKeyID.signature = OSType(0x434C4950) // "CLIP"
        hotKeyID.id = 1

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let handler: EventHandlerUPP = { _, event, _ -> OSStatus in
            guard let manager = HotKeyManager.sharedInstance else { return noErr }
            DispatchQueue.main.async {
                manager.onHotKey?()
            }
            return noErr
        }

        InstallEventHandler(
            GetApplicationEventTarget(),
            handler,
            1,
            &eventType,
            nil,
            &handlerRef
        )

        // kVK_ANSI_J = 0x26, cmdKey = 0x0100
        RegisterEventHotKey(
            UInt32(kVK_ANSI_J),
            UInt32(cmdKey),
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
    }

    func unregister() {
        if let ref = hotKeyRef {
            UnregisterEventHotKey(ref)
            hotKeyRef = nil
        }
        if let ref = handlerRef {
            RemoveEventHandler(ref)
            handlerRef = nil
        }
        HotKeyManager.sharedInstance = nil
    }
}
