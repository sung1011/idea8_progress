import AppKit
import SwiftUI

struct MenuBarPanel: View {
    @ObservedObject var model: EarningsModel

    @State private var monthlyText = ""
    @State private var hourlyText = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            metrics
            Divider()
            settings
            Divider()
            footer
        }
        .padding(14)
        .frame(width: 360)
        .onAppear {
            monthlyText = MoneyFormat.editable(model.settings.monthlySalary)
            hourlyText = MoneyFormat.editable(model.settings.hourlyRate)
            activateApp()
        }
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

    private var settings: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("设置")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            Picker("计薪方式", selection: payModeBinding) {
                ForEach(PayMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            HStack(alignment: .top, spacing: 8) {
                amountField(title: "月薪（元）", text: monthlyBinding)
                amountField(title: "时薪（元/小时）", text: hourlyBinding)
            }

            Text("工作日")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack(spacing: 6) {
                ForEach(WorkSchedule.displayWeekdays, id: \.self) { weekday in
                    weekdayButton(weekday)
                }
            }

            HStack(spacing: 8) {
                Text("上班")
                    .frame(width: 32, alignment: .leading)
                timePicker(workStartBinding)
                Text("下班")
                    .frame(width: 32, alignment: .leading)
                timePicker(workEndBinding)
            }
            .font(.callout)

            HStack(spacing: 8) {
                Text("午休")
                    .frame(width: 32, alignment: .leading)
                timePicker(lunchStartBinding)
                Text("至")
                    .frame(width: 32, alignment: .center)
                timePicker(lunchEndBinding)
            }
            .font(.callout)

            Text(netCaption)
                .font(.caption)
                .foregroundStyle(model.settings.schedule.netPaidSeconds > 0 ? Color.secondary : Color.red)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("计时关闭时不累计。午休、非上班时段、未勾选的星期也不计入。已过工作日按满勤补进本月。")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Button(model.timer.isRunning ? "停止计时" : "开始计时") {
                    model.toggleTimer()
                }
                .buttonStyle(.borderedProminent)
                .tint(model.timer.isRunning ? Color.red : Color.green)

                Spacer()

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

    private func amountField(title: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            TextField(title, text: text)
                .textFieldStyle(.roundedBorder)
                .monospacedDigit()
        }
    }

    private func timePicker(_ selection: Binding<Date>) -> some View {
        DatePicker("", selection: selection, displayedComponents: .hourAndMinute)
            .labelsHidden()
            .controlSize(.small)
            .frame(maxWidth: 108)
    }

    private func weekdayButton(_ weekday: Int) -> some View {
        let selected = model.settings.schedule.workdays.contains(weekday)
        return Button(WorkSchedule.shortSymbol(for: weekday)) {
            model.toggleWeekday(weekday)
        }
        .buttonStyle(.borderedProminent)
        .tint(selected ? Color.accentColor : Color.secondary.opacity(0.45))
        .frame(maxWidth: .infinity)
    }

    private var payModeBinding: Binding<PayMode> {
        Binding(
            get: { model.settings.payMode },
            set: { model.setPayMode($0) }
        )
    }

    private var monthlyBinding: Binding<String> {
        Binding(
            get: { monthlyText },
            set: { newValue in
                monthlyText = newValue
                if let value = MoneyFormat.parse(newValue) {
                    model.setMonthlySalary(value)
                }
            }
        )
    }

    private var hourlyBinding: Binding<String> {
        Binding(
            get: { hourlyText },
            set: { newValue in
                hourlyText = newValue
                if let value = MoneyFormat.parse(newValue) {
                    model.setHourlyRate(value)
                }
            }
        )
    }

    private var workStartBinding: Binding<Date> {
        minutesBinding(\.workStartMinutes)
    }

    private var workEndBinding: Binding<Date> {
        minutesBinding(\.workEndMinutes)
    }

    private var lunchStartBinding: Binding<Date> {
        minutesBinding(\.lunchStartMinutes)
    }

    private var lunchEndBinding: Binding<Date> {
        minutesBinding(\.lunchEndMinutes)
    }

    private func minutesBinding(_ keyPath: WritableKeyPath<WorkSchedule, Int>) -> Binding<Date> {
        Binding(
            get: {
                WorkSchedule.date(minutes: model.settings.schedule[keyPath: keyPath], calendar: model.calendar)
            },
            set: { newDate in
                var schedule = model.settings.schedule
                schedule[keyPath: keyPath] = WorkSchedule.minutes(from: newDate, calendar: model.calendar)
                model.setSchedule(schedule)
            }
        )
    }

    private var statusText: String {
        if !model.snapshot.timerRunning {
            return "未计时"
        }
        if model.snapshot.isEarningNow {
            return "计时中"
        }
        return "计时中 · 当前不计入收入"
    }

    private var statusColor: Color {
        if model.snapshot.isEarningNow { return .green }
        if model.snapshot.timerRunning { return .orange }
        return .secondary
    }

    private var rateCaption: String {
        let rate = MoneyFormat.perHour(model.snapshot.contractedHourlyRate)
        switch model.settings.payMode {
        case .monthly:
            let days = model.snapshot.workdayCountInMonth
            let hours = MoneyFormat.hours(model.snapshot.scheduledNetSeconds)
            return "月薪按本月 \(days) 个工作日、每日 \(hours) 小时折算，时薪 \(rate)"
        case .hourly:
            return "时薪模式，开启且处于带薪时段时按 \(rate) 累计"
        }
    }

    private var netCaption: String {
        let schedule = model.settings.schedule
        if schedule.netPaidSeconds <= 0 {
            return "当前排班净工时为 0。请让下班晚于上班，且午休不要盖住整个班次。"
        }
        return "每日净带薪 \(MoneyFormat.hours(schedule.netPaidSeconds)) 小时（上班窗口扣除午休）"
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
