import Carbon.HIToolbox
import Foundation

/// Registers a single system-wide hotkey via Carbon's RegisterEventHotKey.
/// Unlike an NSEvent global monitor, this needs no Accessibility permission
/// and swallows the keystroke so it doesn't reach the frontmost app.
@MainActor
final class HotKeyCenter {
    static let shared = HotKeyCenter()

    var onTrigger: (() -> Void)?

    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?

    @discardableResult
    func register(_ combo: HotKeyCombo) -> Bool {
        unregister()
        installHandlerIfNeeded()
        let id = EventHotKeyID(signature: OSType(0x434C_504D), id: 1) // 'CLPM'
        let status = RegisterEventHotKey(
            combo.keyCode, combo.carbonModifiers, id,
            GetApplicationEventTarget(), 0, &hotKeyRef
        )
        if status != noErr {
            NSLog("Clipman: failed to register hotkey \(combo.displayString) (status \(status))")
            hotKeyRef = nil
            return false
        }
        return true
    }

    func unregister() {
        if let ref = hotKeyRef {
            UnregisterEventHotKey(ref)
            hotKeyRef = nil
        }
    }

    private func installHandlerIfNeeded() {
        guard handlerRef == nil else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
            DispatchQueue.main.async {
                MainActor.assumeIsolated { HotKeyCenter.shared.onTrigger?() }
            }
            return noErr
        }, 1, &spec, nil, &handlerRef)
    }
}
