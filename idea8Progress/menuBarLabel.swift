import SwiftUI

/// 菜单栏状态项。不用 `Label(title, systemImage:)`：MenuBarExtra 经常只画图标、把标题丢掉。
struct MenuBarLabel: View {
    @ObservedObject var model: EarningsModel

    var body: some View {
        let symbolName = model.snapshot.isEarningNow ? "yensign.circle.fill" : "yensign.circle"
        if model.settings.showMenuBarEarnings {
            HStack(spacing: 2) {
                Image(systemName: symbolName)
                Text(MoneyFormat.menuBar(model.snapshot.todayEarned))
                    .lineLimit(1)
            }
            .fixedSize(horizontal: true, vertical: false)
        } else {
            Image(systemName: symbolName)
                .accessibilityLabel("上班鼓励器")
        }
    }
}
