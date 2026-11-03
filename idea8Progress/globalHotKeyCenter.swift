import AppKit
import ApplicationServices
import Carbon
import Combine
import ObjectiveC

/// SwiftUI 的 MenuBarExtra 不把 NSStatusItem 交出来。在它创建之前换掉
/// `statusItem(withLength:)`，就能拿到按钮并 `performClick`，用来打开或收起菜单栏面板。
enum MenuBarStatusItemCapture {
    private(set) static var item: NSStatusItem?
    private static var didInstall = false
    private static let statusItemSelector = #selector(NSStatusBar.statusItem(withLength:))

    static func install() {
        guard !didInstall else { return }
        guard
            let original = class_getInstanceMethod(NSStatusBar.self, statusItemSelector),
            let swizzled = class_getInstanceMethod(
                NSStatusBar.self,
                #selector(NSStatusBar.idea8_statusItem(withLength:))
            )
        else { return }
        didInstall = true
        method_exchangeImplementations(original, swizzled)
    }

    static func remember(_ item: NSStatusItem) {
        self.item = item
    }

    /// 点菜单栏图标。MenuBarExtra 的窗口样式会因此打开或收起。
    @discardableResult
    static func click() -> Bool {
        guard let button = item?.button ?? findButton() else { return false }
        if #available(macOS 14.0, *) {
            NSApp.activate()
        } else {
            NSApp.activate(ignoringOtherApps: true)
        }
        button.performClick(nil)
        return true
    }

    private static func findButton() -> NSStatusBarButton? {
        for candidate in statusItems() {
            if let button = candidate.button {
                item = candidate
                return button
            }
        }
        for window in NSApp.windows {
            if let button = findButton(in: window.contentView) {
                return button
            }
        }
        return nil
    }

    private static func findButton(in view: NSView?) -> NSStatusBarButton? {
        guard let view else { return nil }
        if let button = view as? NSStatusBarButton { return button }
        for subview in view.subviews {
            if let found = findButton(in: subview) { return found }
        }
        return nil
    }

    private static func statusItems() -> [NSStatusItem] {
        let names = ["_statusItems", "statusItems"]
        for name in names {
            guard let ivar = class_getInstanceVariable(NSStatusBar.self, name) else { continue }
            if let encoding = ivar_getTypeEncoding(ivar) {
                let text = String(cString: encoding)
                guard text.hasPrefix("@") else { continue }
            }
            guard let raw = object_getIvar(NSStatusBar.system, ivar) else { continue }
            let items = asStatusItems(raw)
            if !items.isEmpty { return items }
        }
        let mirror = Mirror(reflecting: NSStatusBar.system)
        for child in mirror.children {
            let items = asStatusItems(child.value)
            if !items.isEmpty { return items }
        }
        return []
    }

    private static func asStatusItems(_ raw: Any) -> [NSStatusItem] {
        if let items = raw as? [NSStatusItem] { return items }
        guard let array = raw as? NSArray else { return [] }
        return array.compactMap { $0 as? NSStatusItem }
    }
}

extension NSStatusBar {
    /// `dynamic` 让自调用走 Objective-C。对调之后，这次调用进入原来的 `statusItem(withLength:)`。
    @objc dynamic func idea8_statusItem(withLength length: CGFloat) -> NSStatusItem {
        let created = idea8_statusItem(withLength: length)
        MenuBarStatusItemCapture.remember(created)
        return created
    }
}

/// 注册全局快捷键，并在按下时打开或收起面板。
/// 优先用系统热键（不需要辅助功能）。注册失败时改听键盘，这时才需要辅助功能权限。
final class GlobalHotKeyCenter: ObservableObject {
    static let shared = GlobalHotKeyCenter()

    @Published private(set) var shortcut: HotKeyShortcut?
    @Published private(set) var isRecording = false
    @Published private(set) var registrationError: String?
    @Published private(set) var statusNote: String?
    @Published private(set) var needsAccessibility = false

    private let defaults: UserDefaults
    private var didStart = false
    private var acceptRecordingEvents = false
    private var handlerRef: EventHandlerRef?
    private var hotKeyRef: EventHotKeyRef?
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var recordingMonitor: Any?
    private var permissionTimer: Timer?
    private var lastToggle = Date.distantPast

    /// 'i8HK'
    private static let signature: OSType = 0x6938484B

    private init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        shortcut = HotKeyStore.load(defaults: defaults)
    }

    func start() {
        guard !didStart else { return }
        didStart = true
        shortcut = HotKeyStore.load(defaults: defaults)
        registerCurrent()
    }

    func beginRecording() {
        guard !isRecording else { return }
        isRecording = true
        acceptRecordingEvents = true
        registrationError = nil
        statusNote = nil
        needsAccessibility = false
        tearDownActiveHotKey()
        removeRecordingMonitor()
        recordingMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.acceptRecordingEvents else { return event }
            return self.consumeRecording(event)
        }
    }

    func cancelRecording() {
        guard isRecording else { return }
        acceptRecordingEvents = false
        isRecording = false
        removeRecordingMonitor()
        registrationError = nil
        registerCurrent()
    }

    func clear() {
        acceptRecordingEvents = false
        isRecording = false
        removeRecordingMonitor()
        shortcut = nil
        HotKeyStore.save(nil, defaults: defaults)
        registerCurrent()
    }

    func useDefault() {
        apply(.default)
    }

    func refreshPermission() {
        guard needsAccessibility else { return }
        guard AXIsProcessTrusted() else { return }
        needsAccessibility = false
        registerCurrent()
    }

    func openAccessibilitySettings() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let options = [key: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)

        let modern = "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_Accessibility"
        let legacy = "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        let primary: String
        if #available(macOS 14.0, *) {
            primary = modern
        } else {
            primary = legacy
        }
        if let url = URL(string: primary), NSWorkspace.shared.open(url) {
            return
        }
        if primary != legacy, let url = URL(string: legacy) {
            NSWorkspace.shared.open(url)
        }
    }

    func handlePressed() {
        if !Thread.isMainThread {
            DispatchQueue.main.async { [weak self] in
                self?.handlePressed()
            }
            return
        }
        guard !isRecording, !acceptRecordingEvents else { return }
        let now = Date()
        guard now.timeIntervalSince(lastToggle) > 0.25 else { return }
        lastToggle = now
        if let pins = PanelPinController.shared {
            pins.toggleFromHotKey()
        } else {
            MenuBarStatusItemCapture.click()
        }
    }

    private func apply(_ shortcut: HotKeyShortcut) {
        acceptRecordingEvents = false
        isRecording = false
        removeRecordingMonitor()
        self.shortcut = shortcut
        HotKeyStore.save(shortcut, defaults: defaults)
        registerCurrent()
    }

    private func consumeRecording(_ event: NSEvent) -> NSEvent? {
        if event.isARepeat { return nil }
        if HotKeyShortcut.modifierKeyCodes.contains(event.keyCode) { return nil }
        if event.keyCode == 53 {
            acceptRecordingEvents = false
            DispatchQueue.main.async { [weak self] in
                self?.cancelRecording()
            }
            return nil
        }
        let recorded = HotKeyShortcut(keyCode: event.keyCode, modifierFlags: event.modifierFlags)
        guard recorded.hasModifier else {
            DispatchQueue.main.async { [weak self] in
                guard let self, self.isRecording else { return }
                self.registrationError = "请至少带上 ⌃、⌥、⇧、⌘ 里的一个。"
            }
            return nil
        }
        acceptRecordingEvents = false
        DispatchQueue.main.async { [weak self] in
            self?.apply(recorded)
        }
        return nil
    }

    private var shouldRegister: Bool {
        let env = ProcessInfo.processInfo.environment
        if env["XCTestConfigurationFilePath"] != nil { return false }
        if env["XCODE_RUNNING_FOR_PREVIEWS"] == "1" { return false }
        return true
    }

    private func registerCurrent() {
        tearDownActiveHotKey()
        registrationError = nil
        statusNote = nil
        needsAccessibility = false
        guard shouldRegister, let shortcut else { return }
        installHandlerIfNeeded()
        guard handlerRef != nil else {
            beginAccessibilityFallback(for: shortcut, carbonFailed: true)
            return
        }
        let status = registerCarbon(shortcut)
        if status == noErr {
            return
        }
        if status == OSStatus(eventHotKeyExistsErr) {
            registrationError = "这个组合键已被其它应用占用，换一个试试。"
            return
        }
        beginAccessibilityFallback(for: shortcut, carbonFailed: true)
    }

    private func beginAccessibilityFallback(for shortcut: HotKeyShortcut, carbonFailed: Bool) {
        installActionMonitors(for: shortcut)
        if AXIsProcessTrusted() {
            needsAccessibility = false
            if carbonFailed {
                statusNote = "系统热键没能注册，已改用辅助功能监听这个快捷键。"
            }
            return
        }
        needsAccessibility = true
        statusNote = nil
        watchPermission()
    }

    private func tearDownActiveHotKey() {
        unregisterCarbon()
        removeActionMonitors()
        invalidatePermissionTimer()
    }

    private func installHandlerIfNeeded() {
        guard handlerRef == nil else { return }
        var spec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let userData = Unmanaged.passUnretained(self).toOpaque()
        let status = InstallEventHandler(
            GetEventDispatcherTarget(),
            idea8HotKeyCarbonHandler,
            1,
            &spec,
            userData,
            &handlerRef
        )
        if status != noErr {
            handlerRef = nil
        }
    }

    private func registerCarbon(_ shortcut: HotKeyShortcut) -> OSStatus {
        unregisterCarbon()
        var ref: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: Self.signature, id: 1)
        let status = RegisterEventHotKey(
            UInt32(shortcut.keyCode),
            shortcut.carbonModifierFlags,
            hotKeyID,
            GetEventDispatcherTarget(),
            0,
            &ref
        )
        if status == noErr {
            hotKeyRef = ref
        } else if let ref {
            UnregisterEventHotKey(ref)
        }
        return status
    }

    private func unregisterCarbon() {
        guard let hotKeyRef else { return }
        UnregisterEventHotKey(hotKeyRef)
        self.hotKeyRef = nil
    }

    private func installActionMonitors(for shortcut: HotKeyShortcut) {
        removeActionMonitors()
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.matches(event, shortcut: shortcut) else { return event }
            self.handlePressed()
            return nil
        }
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.matches(event, shortcut: shortcut) else { return }
            self.handlePressed()
        }
    }

    private func matches(_ event: NSEvent, shortcut: HotKeyShortcut) -> Bool {
        guard !event.isARepeat, event.keyCode == shortcut.keyCode else { return false }
        let flags = event.modifierFlags.intersection(HotKeyShortcut.recordedModifiers)
        return flags == shortcut.modifierFlags
    }

    private func removeActionMonitors() {
        if let globalMonitor {
            NSEvent.removeMonitor(globalMonitor)
            self.globalMonitor = nil
        }
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
            self.localMonitor = nil
        }
    }

    private func removeRecordingMonitor() {
        guard let monitor = recordingMonitor else { return }
        recordingMonitor = nil
        DispatchQueue.main.async {
            NSEvent.removeMonitor(monitor)
        }
    }

    private func watchPermission() {
        guard permissionTimer == nil else { return }
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] timer in
            guard let self else {
                timer.invalidate()
                return
            }
            guard self.needsAccessibility else {
                timer.invalidate()
                self.permissionTimer = nil
                return
            }
            guard AXIsProcessTrusted() else { return }
            self.needsAccessibility = false
            timer.invalidate()
            self.permissionTimer = nil
            self.registerCurrent()
        }
    }

    private func invalidatePermissionTimer() {
        permissionTimer?.invalidate()
        permissionTimer = nil
    }
}

private func idea8HotKeyCarbonHandler(
    _ nextHandler: EventHandlerCallRef?,
    _ event: EventRef?,
    _ userData: UnsafeMutableRawPointer?
) -> OSStatus {
    guard let userData else { return noErr }
    let center = Unmanaged<GlobalHotKeyCenter>.fromOpaque(userData).takeUnretainedValue()
    DispatchQueue.main.async {
        center.handlePressed()
    }
    return noErr
}
