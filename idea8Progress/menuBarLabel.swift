import SwiftUI

struct MenuBarLabel: View {
    var snapshot: EarningsSnapshot
    var showEarnings: Bool

    var body: some View {
        if showEarnings {
            Label(MoneyFormat.menuBar(snapshot.todayEarned), systemImage: symbolName)
        } else {
            Image(systemName: symbolName)
                .accessibilityLabel("上班鼓励器")
        }
    }

    private var symbolName: String {
        snapshot.isEarningNow ? "yensign.circle.fill" : "yensign.circle"
    }
}
