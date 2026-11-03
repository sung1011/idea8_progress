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
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 12)
            hairline
            hero
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 18)
            hairline
            speedRow
                .padding(.horizontal, 20)
                .padding(.vertical, 14)
            hairline
            progressSection
                .padding(.horizontal, 20)
                .padding(.top, 14)
                .padding(.bottom, 16)
            hairline
            monthSection
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 4)
            footer
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .padding(.bottom, 16)
        }
        .frame(width: 336)
    }

    private var header: some View {
        HStack(alignment: .center) {
            Text("上班鼓励器")
                .font(.system(size: 13))
                .foregroundStyle(.primary)
            Spacer(minLength: 8)
            Text(MoneyFormat.clock(model.snapshot.now))
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("今日已赚")
                .font(.system(size: 15))
                .foregroundStyle(.primary)
            Text(MoneyFormat.currency(model.snapshot.todayEarned))
                .font(.system(size: 40, weight: .heavy))
                .foregroundStyle(.primary)
                .monospacedDigit()
                .tracking(-0.6)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var speedRow: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("速度")
                .font(.system(size: 15))
                .foregroundStyle(.primary)
            Spacer(minLength: 12)
            VStack(alignment: .trailing, spacing: 2) {
                Text("\(MoneyFormat.currency(model.snapshot.earnRatePerHour))/时")
                    .font(.system(size: 15))
                    .foregroundStyle(.primary)
                    .monospacedDigit()
                Text("带薪时段")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var progressSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("工时进度")
                .font(.system(size: 15))
                .foregroundStyle(.primary)
            HStack(spacing: 12) {
                ThinProgressBar(value: model.snapshot.progress)
                Text(progressText)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
            }
        }
    }

    private var monthSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("本月累计")
                .font(.system(size: 15))
                .foregroundStyle(.primary)
            Text(MoneyFormat.currency(model.snapshot.monthEarned))
                .font(.system(size: 26, weight: .bold))
                .foregroundStyle(.primary)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text("已过 \(model.snapshot.pastWorkdayCount) 个完整工作日")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var footer: some View {
        HStack {
            Button("设置") {
                showingSettings = true
            }
            .buttonStyle(.plain)
            .foregroundStyle(.primary)
            Spacer()
            Button("退出") {
                NSApplication.shared.terminate(nil)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.primary)
        }
        .font(.system(size: 15))
    }

    private var hairline: some View {
        Divider()
            .padding(.horizontal, 20)
    }

    private var progressText: String {
        let worked = MoneyFormat.hours(model.snapshot.workedSeconds)
        let scheduled = MoneyFormat.hours(model.snapshot.scheduledNetSeconds)
        return "\(worked) / \(scheduled) 小时"
    }

    private func activateApp() {
        if #available(macOS 14.0, *) {
            NSApp.activate()
        } else {
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}

private struct ThinProgressBar: View {
    var value: Double

    var body: some View {
        let fraction = min(max(value.isFinite ? value : 0, 0), 1)
        Capsule()
            .fill(Color.primary.opacity(0.12))
            .frame(maxWidth: .infinity)
            .frame(height: 6)
            .overlay(alignment: .leading) {
                GeometryReader { geo in
                    Capsule()
                        .fill(Color.blue)
                        .frame(width: geo.size.width * fraction)
                }
            }
            .accessibilityHidden(true)
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
