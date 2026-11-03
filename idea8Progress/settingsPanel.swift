import AppKit
import SwiftUI

/// 月薪和排班。从主面板的「设置」进入，不放在主界面上。
struct SettingsPanel: View {
    @ObservedObject var model: EarningsModel
    var onDone: () -> Void

    @State private var monthlyText: String
    @State private var expandedTime: TimeEditor? = nil

    init(model: EarningsModel, onDone: @escaping () -> Void) {
        self.model = model
        self.onDone = onDone
        _monthlyText = State(initialValue: MoneyFormat.editable(model.settings.monthlySalary))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 6)

            VStack(alignment: .leading, spacing: 22) {
                salaryField
                weekdaySection
                scheduleSection
            }
            .padding(.horizontal, 20)
            .padding(.top, 18)
            .padding(.bottom, 22)
        }
        .frame(width: 336)
    }

    private var header: some View {
        ZStack {
            Text("设置")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.primary)
            HStack {
                Button(action: onDone) {
                    HStack(spacing: 2) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 13, weight: .semibold))
                        Text("返回")
                            .font(.system(size: 15))
                    }
                    .foregroundStyle(.primary)
                }
                .buttonStyle(.plain)
                Spacer()
                Button("完成", action: onDone)
                    .buttonStyle(.plain)
                    .font(.system(size: 15))
                    .foregroundStyle(Color.blue)
            }
        }
    }

    private var salaryField: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("月薪（元）")
                .font(.system(size: 15))
                .foregroundStyle(.primary)
            TextField("0", text: monthlyBinding)
                .textFieldStyle(.plain)
                .font(.system(size: 22))
                .monospacedDigit()
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color(nsColor: .textBackgroundColor))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.16), lineWidth: 1)
                )
        }
    }

    private var weekdaySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("工作日")
                .font(.system(size: 15))
                .foregroundStyle(.primary)
            HStack(spacing: 6) {
                ForEach(WorkSchedule.displayWeekdays, id: \.self) { weekday in
                    weekdayChip(weekday)
                }
            }
        }
    }

    private var scheduleSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            scheduleRow(title: "上班", editor: .workStart) {
                Text(timeText(model.settings.schedule.workStartMinutes))
                    .foregroundStyle(Color.blue)
            } editorContent: {
                timeStepper(workStartBinding)
            }
            Divider()
            scheduleRow(title: "下班", editor: .workEnd) {
                Text(timeText(model.settings.schedule.workEndMinutes))
                    .foregroundStyle(Color.blue)
            } editorContent: {
                timeStepper(workEndBinding)
            }
            Divider()
            scheduleRow(title: "午休", editor: .lunch) {
                HStack(spacing: 4) {
                    Text(timeText(model.settings.schedule.lunchStartMinutes))
                    Text("至")
                    Text(timeText(model.settings.schedule.lunchEndMinutes))
                }
                .foregroundStyle(Color.blue)
            } editorContent: {
                VStack(alignment: .leading, spacing: 8) {
                    labeledStepper("开始", lunchStartBinding)
                    labeledStepper("结束", lunchEndBinding)
                }
            }
            Divider()
            netCaptionView
                .padding(.top, 16)
        }
    }

    private var netCaptionView: some View {
        let schedule = model.settings.schedule
        let hours = MoneyFormat.hours(schedule.netPaidSeconds)
        return Group {
            if schedule.netPaidSeconds > 0 {
                HStack(spacing: 0) {
                    Text("每日净带薪 ")
                        .foregroundStyle(.primary)
                    Text(hours)
                        .foregroundStyle(Color.blue)
                        .monospacedDigit()
                    Text(" 小时")
                        .foregroundStyle(.primary)
                }
                .font(.system(size: 15))
            } else {
                Text("当前排班净工时为 0。请让下班晚于上班，且午休不要盖住整个班次。")
                    .font(.system(size: 13))
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func weekdayChip(_ weekday: Int) -> some View {
        let selected = model.settings.schedule.workdays.contains(weekday)
        return Button {
            model.toggleWeekday(weekday)
        } label: {
            Text(WorkSchedule.shortSymbol(for: weekday))
                .font(.system(size: 14, weight: selected ? .semibold : .regular))
                .foregroundStyle(selected ? Color.blue : Color.secondary)
                .frame(maxWidth: .infinity)
                .frame(height: 34)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(selected ? Color.blue.opacity(0.16) : Color.clear)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(selected ? Color.clear : Color.primary.opacity(0.16), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func scheduleRow<Value: View, Editor: View>(
        title: String,
        editor: TimeEditor,
        @ViewBuilder value: () -> Value,
        @ViewBuilder editorContent: () -> Editor
    ) -> some View {
        let open = expandedTime == editor
        return VStack(alignment: .leading, spacing: 0) {
            Button {
                expandedTime = open ? nil : editor
            } label: {
                HStack(spacing: 8) {
                    Text(title)
                        .font(.system(size: 15))
                        .foregroundStyle(.primary)
                    Spacer(minLength: 8)
                    value()
                        .font(.system(size: 15, weight: .medium))
                        .monospacedDigit()
                        .lineLimit(1)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.primary.opacity(0.28))
                        .rotationEffect(.degrees(open ? 90 : 0))
                }
                .padding(.vertical, 13)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if open {
                editorContent()
                    .padding(.bottom, 10)
            }
        }
    }

    private func timeStepper(_ selection: Binding<Date>) -> some View {
        DatePicker("", selection: selection, displayedComponents: .hourAndMinute)
            .labelsHidden()
            .datePickerStyle(.stepperField)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func labeledStepper(_ title: String, _ selection: Binding<Date>) -> some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .frame(width: 36, alignment: .leading)
            timeStepper(selection)
        }
    }

    private func timeText(_ minutes: Int) -> String {
        let value = WorkSchedule.clampMinutes(minutes)
        return String(format: "%d:%02d", value / 60, value % 60)
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

    private enum TimeEditor: Hashable {
        case workStart
        case workEnd
        case lunch
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
