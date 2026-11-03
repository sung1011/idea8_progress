import AppKit
import SwiftUI

/// 读到菜单栏浮层所在的窗口。固定时立刻把它藏起来，避免和浮动面板叠两块。
struct PanelWindowReader: NSViewRepresentable {
    var onResolve: (NSWindow) -> Bool

    func makeNSView(context: Context) -> PanelWindowAnchor {
        let view = PanelWindowAnchor()
        view.onResolve = onResolve
        return view
    }

    func updateNSView(_ nsView: PanelWindowAnchor, context: Context) {
        nsView.onResolve = onResolve
    }
}

final class PanelWindowAnchor: NSView {
    var onResolve: ((NSWindow) -> Bool)?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard let window else { return }
        if onResolve?(window) == true {
            window.alphaValue = 0
            window.ignoresMouseEvents = true
        }
    }
}

/// 设置页展开时高度会变。布局完再量一次，让浮动窗口跟着内容走。
final class FittingHostController: NSHostingController<MenuBarPanel> {
    var onLayout: (() -> Void)?
    private var applying = false

    override func viewDidLayout() {
        super.viewDidLayout()
        guard !applying else { return }
        applying = true
        onLayout?()
        applying = false
    }

    func performMeasurement(_ body: () -> Void) {
        applying = true
        body()
        applying = false
    }
}

final class PinnedPanel: NSPanel {
    static let panelIdentifier = NSUserInterfaceItemIdentifier("com.sung1011.idea8progress.pinnedPanel")

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func becomeKey() {
        super.becomeKey()
        guard !NSApp.isActive else { return }
        if #available(macOS 14.0, *) {
            NSApp.activate()
        } else {
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}

/// MenuBarExtra 的窗口样式没有公开接口可以关掉「点外面就收起」。
/// 固定时改用自己的 NSPanel：不随应用失活隐藏，点到别的窗口也不关闭。
final class PanelPinController: NSObject, ObservableObject, NSWindowDelegate {
    static weak var shared: PanelPinController?

    @Published private(set) var isPinned: Bool

    private let defaults: UserDefaults
    private var model: EarningsModel?
    private var panel: PinnedPanel?
    private var host: FittingHostController?
    private var heightObservation: NSKeyValueObservation?
    private weak var menuBarWindow: NSWindow?
    private var didRestore = false
    private var concealScheduled = false
    private var measureScheduled = false
    private var adjustingFrame = false

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.isPinned = PanelPinStore.loadPinned(defaults: defaults)
        super.init()
        if defaults === UserDefaults.standard, Self.shared == nil {
            Self.shared = self
        }
    }

    func bind(_ model: EarningsModel) {
        if self.model == nil {
            self.model = model
        }
        restoreIfNeeded()
    }

    func restoreIfNeeded() {
        guard !didRestore, model != nil else { return }
        didRestore = true
        guard isPinned else { return }
        DispatchQueue.main.async { [weak self] in
            self?.presentPinnedPanel(anchor: nil, reposition: true, focus: false)
        }
    }

    /// 返回 true 表示这是菜单栏浮层，而且当前处于固定状态，调用方应立刻把它藏起来。
    func consumeWindow(_ window: NSWindow) -> Bool {
        if window.identifier == PinnedPanel.panelIdentifier || window === panel {
            return false
        }
        menuBarWindow = window
        guard isPinned else { return false }
        guard !concealScheduled else { return false }
        concealScheduled = true
        DispatchQueue.main.async { [weak self, weak window] in
            guard let self else { return }
            self.concealScheduled = false
            guard let window else { return }
            guard self.isPinned else {
                window.alphaValue = 1
                window.ignoresMouseEvents = false
                return
            }
            let alreadyVisible = self.panel?.isVisible == true
            self.presentPinnedPanel(anchor: nil, reposition: !alreadyVisible, focus: true)
            self.dismissMenuBarWindow(window)
        }
        return true
    }

    func togglePinned() {
        if isPinned {
            if let panel {
                panel.close()
            } else {
                setPinned(false)
            }
        } else {
            pin()
        }
    }

    /// 全局快捷键。没固定时点菜单栏图标来打开或收起；固定时显示浮动窗口，再按一次先收起，固定状态保留。
    func toggleFromHotKey() {
        if isPinned {
            togglePinnedVisibility()
            return
        }
        if MenuBarStatusItemCapture.click() {
            return
        }
        if let window = visibleMenuBarWindow() {
            dismissMenuBarWindow(window)
        }
    }

    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow, window === panel else { return }
        saveFrame(of: window)
        heightObservation = nil
        host = nil
        panel = nil
        if isPinned {
            setPinned(false)
        }
    }

    func windowDidMove(_ notification: Notification) {
        guard !adjustingFrame, let window = notification.object as? NSWindow, window === panel else { return }
        saveFrame(of: window)
    }

    private func togglePinnedVisibility() {
        if let panel, panel.isVisible, panel.isKeyWindow, NSApp.isActive {
            panel.orderOut(nil)
            return
        }
        let reposition = panel?.isVisible != true
        presentPinnedPanel(anchor: nil, reposition: reposition, focus: true)
    }

    private func visibleMenuBarWindow() -> NSWindow? {
        guard let menuBarWindow, menuBarWindow !== panel else { return nil }
        if menuBarWindow.identifier == PinnedPanel.panelIdentifier { return nil }
        guard menuBarWindow.isVisible, menuBarWindow.alphaValue > 0.05 else { return nil }
        return menuBarWindow
    }

    private func pin() {
        guard model != nil else { return }
        let menuWindow = anchorWindow()
        let anchor = menuWindow?.frame
        menuWindow?.alphaValue = 0
        menuWindow?.ignoresMouseEvents = true
        setPinned(true)
        presentPinnedPanel(anchor: anchor, reposition: true, focus: true)
        if let menuWindow {
            dismissMenuBarWindow(menuWindow)
        }
    }

    private func setPinned(_ pinned: Bool) {
        isPinned = pinned
        PanelPinStore.savePinned(pinned, defaults: defaults)
    }

    private func anchorWindow() -> NSWindow? {
        guard let menuBarWindow, menuBarWindow !== panel else { return nil }
        if menuBarWindow.identifier == PinnedPanel.panelIdentifier { return nil }
        return menuBarWindow
    }

    private func presentPinnedPanel(anchor: NSRect?, reposition: Bool, focus: Bool) {
        guard let model else { return }
        let panel = ensurePanel(model: model)
        if reposition || !panel.isVisible {
            place(panel, anchor: anchor)
        }
        measureAndApply()
        if focus {
            panel.makeKeyAndOrderFront(nil)
        } else {
            panel.orderFrontRegardless()
        }
        panel.hidesOnDeactivate = false
        panel.standardWindowButton(.closeButton)?.toolTip = "关闭并取消固定"
        DispatchQueue.main.async { [weak self] in
            self?.measureAndApply()
        }
    }

    private func ensurePanel(model: EarningsModel) -> PinnedPanel {
        if let panel { return panel }
        let panel = PinnedPanel(
            contentRect: NSRect(x: 0, y: 0, width: 336, height: 480),
            styleMask: [.titled, .closable, .utilityWindow, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.identifier = PinnedPanel.panelIdentifier
        panel.title = "上班鼓励器"
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovable = true
        panel.isMovableByWindowBackground = true
        panel.isReleasedWhenClosed = false
        panel.isFloatingPanel = false
        panel.becomesKeyOnlyIfNeeded = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false
        panel.backgroundColor = .windowBackgroundColor
        panel.delegate = self

        let host = FittingHostController(rootView: MenuBarPanel(model: model, pins: self))
        host.sizingOptions = [.preferredContentSize]
        host.onLayout = { [weak self] in
            self?.scheduleMeasure()
        }
        self.panel = panel
        self.host = host
        panel.contentViewController = host
        heightObservation = host.observe(\.preferredContentSize, options: [.new]) { [weak self] host, _ in
            let height = host.preferredContentSize.height
            DispatchQueue.main.async {
                self?.applyContentHeight(height)
            }
        }
        return panel
    }

    private func scheduleMeasure() {
        guard panel != nil, !measureScheduled else { return }
        measureScheduled = true
        DispatchQueue.main.async { [weak self] in
            self?.measureScheduled = false
            self?.measureAndApply()
        }
    }

    private func measureAndApply() {
        guard let host else { return }
        host.view.layoutSubtreeIfNeeded()
        let preferred = host.preferredContentSize.height
        let fitted = host.sizeThatFits(in: CGSize(width: 336, height: 10_000)).height
        let height = preferred >= 120 && preferred <= 1600 ? preferred : fitted
        applyContentHeight(height)
    }

    private func applyContentHeight(_ height: CGFloat) {
        guard let panel, height >= 120, height <= 1600 else { return }
        let contentHeight = panel.contentRect(forFrameRect: panel.frame).height
        guard abs(contentHeight - height) > 1 else { return }
        var frame = panel.frame
        let delta = height - contentHeight
        frame.size.height += delta
        frame.origin.y -= delta
        if let screen = screen(for: frame) ?? NSScreen.main ?? NSScreen.screens.first {
            frame = clamped(frame, in: screen.visibleFrame)
        }
        let clampedContent = panel.contentRect(forFrameRect: frame).height
        guard abs(clampedContent - contentHeight) > 1 else { return }
        adjustingFrame = true
        host?.performMeasurement {
            panel.setFrame(frame, display: true)
        }
        adjustingFrame = false
        saveFrame(of: panel)
    }

    private func place(_ panel: NSPanel, anchor: NSRect?) {
        let saved = PanelPinStore.loadFrame(defaults: defaults)?.rect
        let probe = anchor ?? saved
        let screen = screen(for: probe) ?? NSScreen.main ?? NSScreen.screens.first
        guard let screen else { return }
        let visible = screen.visibleFrame
        var frame = panel.frame
        if let anchor {
            frame.origin = NSPoint(x: anchor.minX, y: anchor.maxY - frame.height)
        } else if let saved, screen.frame.intersects(saved) {
            frame.origin = saved.origin
        } else {
            frame.origin = NSPoint(
                x: visible.maxX - frame.width - 12,
                y: visible.maxY - frame.height - 12
            )
        }
        frame = clamped(frame, in: visible)
        adjustingFrame = true
        panel.setFrame(frame, display: true)
        adjustingFrame = false
        saveFrame(of: panel)
    }

    private func dismissMenuBarWindow(_ window: NSWindow) {
        guard window !== panel, window.identifier != PinnedPanel.panelIdentifier else { return }
        window.ignoresMouseEvents = true
        window.alphaValue = 0
        window.resignKey()
        DispatchQueue.main.async { [weak window] in
            guard let window else { return }
            if window.isVisible {
                window.orderOut(nil)
            }
            window.alphaValue = 1
            window.ignoresMouseEvents = false
        }
    }

    private func saveFrame(of window: NSWindow) {
        let frame = window.frame
        guard frame.width >= 200, frame.height >= 80 else { return }
        PanelPinStore.saveFrame(StoredPanelFrame(frame), defaults: defaults)
    }

    private func screen(for rect: NSRect?) -> NSScreen? {
        guard let rect, rect.width > 1, rect.height > 1 else { return nil }
        let center = NSPoint(x: rect.midX, y: rect.midY)
        return NSScreen.screens.first { $0.frame.contains(center) }
    }

    private func clamped(_ frame: NSRect, in visible: NSRect) -> NSRect {
        var frame = frame
        if frame.width > visible.width { frame.size.width = visible.width }
        if frame.height > visible.height { frame.size.height = visible.height }
        let maxX = max(visible.minX, visible.maxX - frame.width)
        let maxY = max(visible.minY, visible.maxY - frame.height)
        frame.origin.x = min(max(frame.origin.x, visible.minX), maxX)
        frame.origin.y = min(max(frame.origin.y, visible.minY), maxY)
        return frame
    }

}
