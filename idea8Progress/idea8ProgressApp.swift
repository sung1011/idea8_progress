import SwiftUI

@main
struct Idea8ProgressApp: App {
    @NSApplicationDelegateAdaptor(AppLaunch.self) private var appLaunch
    @StateObject private var model = EarningsModel()
    @StateObject private var pins = PanelPinController()

    var body: some Scene {
        // 在 Scene 里直接读 Published。MenuBarExtra 的 label 才会在开关和金额变化时立刻重画。
        let showsMenuBarEarnings = model.settings.showMenuBarEarnings
        let menuBarEarning = model.snapshot.isEarningNow
        let _ = model.snapshot.todayEarned
        let _ = MenuBarStatusItemCapture.install()
        let _ = pins.bind(model)
        let _ = appLaunch
        MenuBarExtra {
            MenuBarPanel(model: model, pins: pins)
        } label: {
            MenuBarLabel(model: model)
                .id(showsMenuBarEarnings ? "earnings-\(menuBarEarning)" : "icon-\(menuBarEarning)")
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
