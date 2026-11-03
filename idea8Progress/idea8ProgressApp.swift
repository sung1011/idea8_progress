import SwiftUI

@main
struct Idea8ProgressApp: App {
    @StateObject private var model = EarningsModel()

    var body: some Scene {
        MenuBarExtra {
            MenuBarPanel(model: model)
        } label: {
            MenuBarLabel(snapshot: model.snapshot)
        }
        .menuBarExtraStyle(.window)
    }
}
