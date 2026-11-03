import SwiftUI

/// 月薪和排班。从主面板的「设置」进入，不放在主界面上。
struct SettingsPanel: View {
    @ObservedObject var model: EarningsModel
    var onDone: () -> Void

    @State private var monthlyText: String

    init(model: EarningsModel, onDone: @escaping () -> Void) {
        self.model = model
        self.onDone = onDone
        _monthlyText = State(initialValue: MoneyFormat.editable(model.settings.monthlySalary))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("设置")
                    .font(.headline)
                Spacer()
                Button("完成", action: onDone)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("月薪（元）")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField("月薪（元）", text: monthlyBinding)
                    .textFieldStyle(.roundedBorder)
                    .monospacedDigit()
            }

            Text(rateCaption)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

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
        .padding(14)
        .frame(width: 360)
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

    private var rateCaption: String {
        let rate = MoneyFormat.perHour(model.snapshot.contractedHourlyRate)
        let days = model.snapshot.workdayCountInMonth
        let hours = MoneyFormat.hours(model.snapshot.scheduledNetSeconds)
        return "按本月 \(days) 个工作日、每日 \(hours) 小时折算，时薪 \(rate)"
    }

    private var netCaption: String {
        let schedule = model.settings.schedule
        if schedule.netPaidSeconds <= 0 {
            return "当前排班净工时为 0。请让下班晚于上班，且午休不要盖住整个班次。"
        }
        return "每日净带薪 \(MoneyFormat.hours(schedule.netPaidSeconds)) 小时（上班窗口扣除午休）"
    }
}

struct SettingsPanelPreview: PreviewProvider {
    static var previews: some View {
        SettingsPanel(
            model: EarningsModel(
                defaults: UserDefaults(suiteName: "idea8Progress.preview.settings") ?? .standard,
                startTicker: false
            ),
            onDone: {}
        )
    }
}
