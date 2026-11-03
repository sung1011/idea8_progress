import AppKit
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
