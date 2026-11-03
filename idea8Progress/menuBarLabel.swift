import SwiftUI

struct MenuBarLabel: View {
    var snapshot: EarningsSnapshot

    var body: some View {
        Label(
            MoneyFormat.menuBar(snapshot.todayEarned),
            systemImage: snapshot.timerRunning ? "play.circle.fill" : "pause.circle"
        )
    }
}
