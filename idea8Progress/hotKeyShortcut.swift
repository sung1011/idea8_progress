import AppKit
import Carbon

/// 用户选的全局快捷键。修饰键只保留 ⌃ ⌥ ⇧ ⌘，避免把设备相关的标志写进存档。
struct HotKeyShortcut: Equatable {
    var keyCode: UInt16
    /// `NSEvent.ModifierFlags` 里 command / option / control / shift 的 rawValue。
    var modifiers: UInt

    /// 默认建议：⌃⌥⌘P（Control-Option-Command-P）。keyCode 0x23 是 ANSI P。
    static let `default` = HotKeyShortcut(
        keyCode: 0x23,
        modifierFlags: [.control, .option, .command]
    )

    init(keyCode: UInt16, modifierFlags: NSEvent.ModifierFlags) {
        self.keyCode = keyCode
        self.modifiers = modifierFlags.intersection(Self.recordedModifiers).rawValue
    }

    var modifierFlags: NSEvent.ModifierFlags {
        NSEvent.ModifierFlags(rawValue: modifiers).intersection(Self.recordedModifiers)
    }

    var hasModifier: Bool {
        !modifierFlags.isEmpty
    }

    var display: String {
        var text = ""
        let flags = modifierFlags
        if flags.contains(.control) { text.append("⌃") }
        if flags.contains(.option) { text.append("⌥") }
        if flags.contains(.shift) { text.append("⇧") }
        if flags.contains(.command) { text.append("⌘") }
        text.append(Self.keySymbol(for: keyCode))
        return text
    }

    var encoded: String {
        "\(keyCode),\(modifiers)"
    }

    init?(encoded: String) {
        let parts = encoded.split(separator: ",")
        guard parts.count == 2,
              let keyCode = UInt16(parts[0]),
              let rawModifiers = UInt(parts[1]),
              keyCode <= 255 else {
            return nil
        }
        let flags = NSEvent.ModifierFlags(rawValue: rawModifiers).intersection(Self.recordedModifiers)
        guard !flags.isEmpty else { return nil }
        self.init(keyCode: keyCode, modifierFlags: flags)
    }

    static func keySymbol(for keyCode: UInt16) -> String {
        if let named = namedKeys[keyCode] {
            return named
        }
        return "键\(keyCode)"
    }

    static let recordedModifiers: NSEvent.ModifierFlags = [.command, .option, .control, .shift]

    /// 这些按键本身是修饰键，录制时忽略，等用户按下真正的主键。
    static let modifierKeyCodes: Set<UInt16> = [54, 55, 56, 57, 58, 59, 60, 61, 62, 63]

    private static let namedKeys: [UInt16: String] = [
        0x00: "A", 0x0B: "B", 0x08: "C", 0x02: "D", 0x0E: "E", 0x03: "F",
        0x05: "G", 0x04: "H", 0x22: "I", 0x26: "J", 0x28: "K", 0x25: "L",
        0x2E: "M", 0x2D: "N", 0x1F: "O", 0x23: "P", 0x0C: "Q", 0x0F: "R",
        0x01: "S", 0x11: "T", 0x20: "U", 0x09: "V", 0x0D: "W", 0x07: "X",
        0x10: "Y", 0x06: "Z",
        0x12: "1", 0x13: "2", 0x14: "3", 0x15: "4", 0x17: "5",
        0x16: "6", 0x1A: "7", 0x1C: "8", 0x19: "9", 0x1D: "0",
        0x1B: "-", 0x18: "=", 0x21: "[", 0x1E: "]", 0x27: "'",
        0x29: ";", 0x2A: "\\", 0x2B: ",", 0x2F: ".", 0x2C: "/", 0x32: "`",
        0x24: "↩", 0x30: "⇥", 0x31: "空格", 0x33: "⌫", 0x35: "⎋", 0x75: "⌦",
        0x73: "Home", 0x77: "End", 0x74: "PgUp", 0x79: "PgDn",
        0x7B: "←", 0x7C: "→", 0x7D: "↓", 0x7E: "↑",
        0x7A: "F1", 0x78: "F2", 0x63: "F3", 0x76: "F4", 0x60: "F5", 0x61: "F6",
        0x62: "F7", 0x64: "F8", 0x65: "F9", 0x6D: "F10", 0x67: "F11", 0x6F: "F12"
    ]
}

extension HotKeyShortcut {
    /// Carbon `RegisterEventHotKey` 用的修饰键。
    var carbonModifierFlags: UInt32 {
        var carbon: UInt32 = 0
        let flags = modifierFlags
        if flags.contains(.command) { carbon |= UInt32(cmdKey) }
        if flags.contains(.shift) { carbon |= UInt32(shiftKey) }
        if flags.contains(.option) { carbon |= UInt32(optionKey) }
        if flags.contains(.control) { carbon |= UInt32(controlKey) }
        return carbon
    }
}

/// 和月薪存档分开。键不存在表示还没设置过，用默认建议；空字符串表示用户清除了。
enum HotKeyStore {
    static let storageKey = "com.sung1011.idea8progress.globalHotKey"

    static func load(defaults: UserDefaults = .standard) -> HotKeyShortcut? {
        guard defaults.object(forKey: storageKey) != nil else {
            return .default
        }
        guard let text = defaults.string(forKey: storageKey), !text.isEmpty else {
            return nil
        }
        return HotKeyShortcut(encoded: text)
    }

    static func save(_ shortcut: HotKeyShortcut?, defaults: UserDefaults) {
        if let shortcut {
            defaults.set(shortcut.encoded, forKey: storageKey)
        } else {
            defaults.set("", forKey: storageKey)
        }
    }
}
