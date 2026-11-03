import SwiftUI

struct MenuBarLabel: View {
    var snapshot: EarningsSnapshot

    var body: some View {
        Label(
            MoneyFormat.menuBar(snapshot.todayEarned),
            systemImage: snapshot.isEarningNow ? "play.circle.fill" : "pause.circle"
        )
    }
}
