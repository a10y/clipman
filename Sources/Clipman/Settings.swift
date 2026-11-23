import AppKit
import Carbon.HIToolbox

/// A global keyboard shortcut in Carbon terms (what RegisterEventHotKey wants).
struct HotKeyCombo: Codable, Equatable {
    var keyCode: UInt32
    var carbonModifiers: UInt32
    /// Human-readable key name, e.g. "X" or "Space".
    var keyName: String

    static let `default` = HotKeyCombo(
        keyCode: UInt32(kVK_ANSI_X),
        carbonModifiers: UInt32(controlKey | cmdKey),
        keyName: "X"
    )

    var displayString: String {
        var s = ""
        if carbonModifiers & UInt32(controlKey) != 0 { s += "⌃" }
        if carbonModifiers & UInt32(optionKey) != 0 { s += "⌥" }
        if carbonModifiers & UInt32(shiftKey) != 0 { s += "⇧" }
        if carbonModifiers & UInt32(cmdKey) != 0 { s += "⌘" }
        return s + keyName
    }

    var cocoaModifiers: NSEvent.ModifierFlags {
        var flags: NSEvent.ModifierFlags = []
        if carbonModifiers & UInt32(controlKey) != 0 { flags.insert(.control) }
        if carbonModifiers & UInt32(optionKey) != 0 { flags.insert(.option) }
        if carbonModifiers & UInt32(shiftKey) != 0 { flags.insert(.shift) }
        if carbonModifiers & UInt32(cmdKey) != 0 { flags.insert(.command) }
        return flags
    }

    /// Build from a key-down event; returns nil unless a "real" modifier is held.
    init?(event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        var mods: UInt32 = 0
        if flags.contains(.control) { mods |= UInt32(controlKey) }
        if flags.contains(.option) { mods |= UInt32(optionKey) }
        if flags.contains(.shift) { mods |= UInt32(shiftKey) }
        if flags.contains(.command) { mods |= UInt32(cmdKey) }
        guard mods & UInt32(controlKey | optionKey | cmdKey) != 0 else { return nil }
        self.keyCode = UInt32(event.keyCode)
        self.carbonModifiers = mods
        self.keyName = Self.name(for: Int(event.keyCode)) ?? (event.charactersIgnoringModifiers ?? "?").uppercased()
    }

    init(keyCode: UInt32, carbonModifiers: UInt32, keyName: String) {
        self.keyCode = keyCode
        self.carbonModifiers = carbonModifiers
        self.keyName = keyName
    }

    private static func name(for keyCode: Int) -> String? {
        switch keyCode {
        case kVK_Space: return "Space"
        case kVK_Return: return "↩"
        case kVK_Tab: return "⇥"
        case kVK_Delete: return "⌫"
        case kVK_ForwardDelete: return "⌦"
        case kVK_Escape: return "⎋"
        case kVK_LeftArrow: return "←"
        case kVK_RightArrow: return "→"
        case kVK_UpArrow: return "↑"
        case kVK_DownArrow: return "↓"
        case kVK_Home: return "↖"
        case kVK_End: return "↘"
        case kVK_PageUp: return "⇞"
        case kVK_PageDown: return "⇟"
        case kVK_F1: return "F1"
        case kVK_F2: return "F2"
        case kVK_F3: return "F3"
        case kVK_F4: return "F4"
        case kVK_F5: return "F5"
        case kVK_F6: return "F6"
        case kVK_F7: return "F7"
        case kVK_F8: return "F8"
        case kVK_F9: return "F9"
        case kVK_F10: return "F10"
        case kVK_F11: return "F11"
        case kVK_F12: return "F12"
        default: return nil
        }
    }
}

/// User preferences, persisted in UserDefaults.
@MainActor
final class Settings: ObservableObject {
    static let shared = Settings()

    private let defaults: UserDefaults

    @Published var retentionDays: Int {
        didSet { defaults.set(retentionDays, forKey: Keys.retentionDays) }
    }
    @Published var maxStorageMiB: Int {
        didSet { defaults.set(maxStorageMiB, forKey: Keys.maxStorageMiB) }
    }
    @Published var menuItemCount: Int {
        didSet { defaults.set(menuItemCount, forKey: Keys.menuItemCount) }
    }
    @Published var hotKey: HotKeyCombo {
        didSet {
            if let data = try? JSONEncoder().encode(hotKey) {
                defaults.set(data, forKey: Keys.hotKey)
            }
        }
    }

    var maxAge: TimeInterval { TimeInterval(retentionDays) * 24 * 60 * 60 }
    var maxBytes: Int { maxStorageMiB * 1024 * 1024 }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: [
            Keys.retentionDays: 3,
            Keys.maxStorageMiB: 100,
            Keys.menuItemCount: 15,
        ])
        retentionDays = defaults.integer(forKey: Keys.retentionDays)
        maxStorageMiB = defaults.integer(forKey: Keys.maxStorageMiB)
        menuItemCount = defaults.integer(forKey: Keys.menuItemCount)
        hotKey = defaults.data(forKey: Keys.hotKey)
            .flatMap { try? JSONDecoder().decode(HotKeyCombo.self, from: $0) } ?? .default
    }

    private enum Keys {
        static let retentionDays = "retentionDays"
        static let maxStorageMiB = "maxStorageMiB"
        static let menuItemCount = "menuItemCount"
        static let hotKey = "hotKey"
    }
}
