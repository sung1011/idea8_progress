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
            MenuBarLabel(snapshot: model.snapshot)
                .onAppear { pins.bind(model) }
        }
        .menuBarExtraStyle(.window)
    }
}

/// 上次退出时如果面板是固定的，启动后直接打开浮动窗口。
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
