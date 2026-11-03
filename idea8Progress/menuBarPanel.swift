import AppKit
import SwiftUI

struct MenuBarPanel: View {
    @ObservedObject var model: EarningsModel

    @State private var showingSettings = false

    var body: some View {
        Group {
            if showingSettings {
                SettingsPanel(model: model) {
                    showingSettings = false
                }
            } else {
                dashboard
            }
        }
        .onAppear(perform: activateApp)
    }

    private var dashboard: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            metrics
            Divider()
            footer
        }
        .padding(14)
        .frame(width: 360)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text("上班鼓励器")
                    .font(.headline)
                Text(statusText)
                    .font(.caption)
                    .foregroundStyle(statusColor)
            }
            Spacer()
            Text(MoneyFormat.clock(model.snapshot.now))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
    }

    private var metrics: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                metricTitle("今日已赚")
                Text(MoneyFormat.currency(model.snapshot.todayEarned))
                    .font(.system(size: 28, weight: .semibold, design: .rounded))
                    .monospacedDigit()
            }

            VStack(alignment: .leading, spacing: 2) {
                metricTitle("速度")
                Text(MoneyFormat.perHour(model.snapshot.earnRatePerHour))
                    .font(.title3.weight(.semibold))
                    .monospacedDigit()
                Text(rateCaption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    metricTitle("工时进度")
                    Spacer()
                    Text(MoneyFormat.percent(model.snapshot.progress))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                ProgressView(value: min(max(model.snapshot.progress, 0), 1))
                Text("\(MoneyFormat.duration(model.snapshot.workedSeconds)) / \(MoneyFormat.hours(model.snapshot.scheduledNetSeconds)) 小时")
                    .font(.subheadline.monospacedDigit())
            }

            VStack(alignment: .leading, spacing: 2) {
                metricTitle("本月累计")
                Text(MoneyFormat.currency(model.snapshot.monthEarned))
                    .font(.title3.weight(.semibold))
                    .monospacedDigit()
                Text("含已过工作日满勤 \(model.snapshot.pastWorkdayCount) 天，每日 \(MoneyFormat.currency(model.snapshot.fullDayEarnings))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("按排班自动累计：从上班到现在，扣除午休。非上班时段和未勾选的星期不计入。已过工作日按满勤补进本月。")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Spacer()

                Button("设置") {
                    showingSettings = true
                }

                Button("退出") {
                    NSApplication.shared.terminate(nil)
                }
            }
        }
    }

    private func metricTitle(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
    }

    private var statusText: String {
        model.snapshot.isEarningNow ? "正在入账" : "当前不计入收入"
    }

    private var statusColor: Color {
        model.snapshot.isEarningNow ? .green : .secondary
    }

    private var rateCaption: String {
        let rate = MoneyFormat.perHour(model.snapshot.contractedHourlyRate)
        let days = model.snapshot.workdayCountInMonth
        let hours = MoneyFormat.hours(model.snapshot.scheduledNetSeconds)
        return "月薪按本月 \(days) 个工作日、每日 \(hours) 小时折算，时薪 \(rate)"
    }

    private func activateApp() {
        if #available(macOS 14.0, *) {
            NSApp.activate()
        } else {
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}

struct MenuBarPanelPreview: PreviewProvider {
    static var previews: some View {
        MenuBarPanel(
            model: EarningsModel(
                defaults: UserDefaults(suiteName: "idea8Progress.preview") ?? .standard,
                startTicker: false
            )
        )
    }
}
