import AppKit
import XCTest
@testable import idea8Progress

final class HotKeyStoreTests: XCTestCase {
    private var suiteName = ""
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "idea8Progress.tests.hotkey.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        super.tearDown()
    }

    func testDefaultSuggestionIsControlOptionCommandP() {
        let shortcut = HotKeyShortcut.default
        XCTAssertEqual(shortcut.keyCode, 0x23)
        XCTAssertTrue(shortcut.modifierFlags.contains(.control))
        XCTAssertTrue(shortcut.modifierFlags.contains(.option))
        XCTAssertTrue(shortcut.modifierFlags.contains(.command))
        XCTAssertFalse(shortcut.modifierFlags.contains(.shift))
        XCTAssertEqual(shortcut.display, "⌃⌥⌘P")
        XCTAssertEqual(shortcut.carbonModifierFlags, UInt32((1 << 12) | (1 << 11) | (1 << 8)))
        XCTAssertEqual(HotKeyShortcut(encoded: shortcut.encoded), shortcut)
    }

    func testMissingKeyUsesDefaultWithoutWriting() {
        XCTAssertNil(defaults.object(forKey: HotKeyStore.storageKey))
        XCTAssertEqual(HotKeyStore.load(defaults: defaults), .default)
        XCTAssertNil(defaults.object(forKey: HotKeyStore.storageKey))
    }

    func testClearStaysClear() {
        HotKeyStore.save(.default, defaults: defaults)
        HotKeyStore.save(nil, defaults: defaults)
        XCTAssertNil(HotKeyStore.load(defaults: defaults))
        XCTAssertEqual(defaults.string(forKey: HotKeyStore.storageKey), "")
    }

    func testCustomRoundTrip() {
        let custom = HotKeyShortcut(keyCode: 0x00, modifierFlags: [.command, .shift])
        XCTAssertEqual(custom.display, "⇧⌘A")
        HotKeyStore.save(custom, defaults: defaults)
        XCTAssertEqual(HotKeyStore.load(defaults: defaults), custom)
    }

    func testRejectsEmptyModifiersAndGarbage() {
        XCTAssertNil(HotKeyShortcut(encoded: "35,0"))
        XCTAssertNil(HotKeyShortcut(encoded: "nope"))
        XCTAssertNil(HotKeyShortcut(encoded: "999,1835008"))
        defaults.set("nope", forKey: HotKeyStore.storageKey)
        XCTAssertNil(HotKeyStore.load(defaults: defaults))
    }

    func testEncodedModifiersIgnoreCapsLock() {
        let dirty = "\(HotKeyShortcut.default.keyCode),\(HotKeyShortcut.default.modifiers | NSEvent.ModifierFlags.capsLock.rawValue)"
        XCTAssertEqual(HotKeyShortcut(encoded: dirty), .default)
    }
}
