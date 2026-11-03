import SwiftUI

@main
struct Idea8ProgressApp: App {
    @NSApplicationDelegateAdaptor(AppLaunch.self) private var appLaunch
    @StateObject private var model = EarningsModel()
    @StateObject private var pins = PanelPinController()

    var body: some Scene {
        let _ = MenuBarStatusItemCapture.install()
        let _ = pins.bind(model)
        let _ = appLaunch
        MenuBarExtra {
            MenuBarPanel(model: model, pins: pins)
        } label: {
            MenuBarLabel(
                snapshot: model.snapshot,
                showEarnings: model.settings.showMenuBarEarnings
            )
                .onAppear { pins.bind(model) }
        }
        .menuBarExtraStyle(.window)
    }
}

/// 只有 UserDefaults 里已经记下固定时，启动后才打开浮动窗口。没写过这个键则不弹出。
final class AppLaunch: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        MenuBarStatusItemCapture.install()
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil {
            GlobalHotKeyCenter.shared.start()
        }
        DispatchQueue.main.async {
            PanelPinController.shared?.restoreIfNeeded()
        }
    }
}
