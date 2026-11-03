import Foundation

/// 计算器的全部输入。不读时钟、不读 UserDefaults，方便单测注入任意时刻。
struct EarningsInput {
    var now: Date
    var calendar: Calendar
    var settings: AppSettings
    var timer: TimerState
}

/// 面板上四个指标所需的快照。
struct EarningsSnapshot: Equatable {
    var now: Date
    var todayEarned: Decimal
    /// 此刻真正在往上跳的速度。计时关闭，或不在带薪时段时为 0。
    var earnRatePerHour: Decimal
    /// 当前计薪方式折算后的时薪，与计时开关无关。
    var contractedHourlyRate: Decimal
    /// 今天「计时开启 ∩ 带薪窗口」的秒数。
    var workedSeconds: TimeInterval
    /// 一个满勤日的净带薪秒数。默认 8.5 小时。
    var scheduledNetSeconds: TimeInterval
    var fullDayEarnings: Decimal
    var monthEarned: Decimal
    /// 本月今天之前、按排班应出勤的天数。这些天按满勤计入，不看当天有没有开过计时器。
    var pastWorkdayCount: Int
    /// 本月全部应出勤天数，用来把月薪摊成日薪/时薪。含今天和尚未到来的工作日。
    var workdayCountInMonth: Int
    var timerRunning: Bool
    var isEarningNow: Bool

    var progress: Double {
        guard scheduledNetSeconds > 0 else { return 0 }
        return workedSeconds / scheduledNetSeconds
    }
}

enum EarningsCalculator {
    static func snapshot(_ input: EarningsInput) -> EarningsSnapshot {
        let settings = input.settings.sanitized()
        let schedule = settings.schedule
        let calendar = input.calendar
        let now = input.now
        let netSeconds = schedule.netPaidSeconds
        let workdayCount = workdayCount(inMonthOf: now, schedule: schedule, calendar: calendar)
        let pastCount = pastWorkdayCount(before: now, schedule: schedule, calendar: calendar)
        let hourly = effectiveHourlyRate(
            payMode: settings.payMode,
            monthlySalary: settings.monthlySalary,
            hourlyRate: settings.hourlyRate,
            workdayCount: workdayCount,
            netSeconds: netSeconds
        )
        let worked = workedPaidSeconds(
            now: now,
            timer: input.timer,
            schedule: schedule,
            calendar: calendar
        )
        let fullDay = earnings(seconds: netSeconds, hourlyRate: hourly)
        let today = earnings(seconds: worked, hourlyRate: hourly)
        let month = fullDay * Decimal(pastCount) + today
        let earningNow = input.timer.isRunning && isInstantPaid(now: now, schedule: schedule, calendar: calendar)

        return EarningsSnapshot(
            now: now,
            todayEarned: today,
            earnRatePerHour: earningNow ? hourly : 0,
            contractedHourlyRate: hourly,
            workedSeconds: worked,
            scheduledNetSeconds: netSeconds,
            fullDayEarnings: fullDay,
            monthEarned: month,
            pastWorkdayCount: pastCount,
            workdayCountInMonth: workdayCount,
            timerRunning: input.timer.isRunning,
            isEarningNow: earningNow
        )
    }

    /// 月薪模式：月薪 / (本月工作日数 × 每日净工时)。时薪模式：直接用填写的时薪。
    static func effectiveHourlyRate(
        payMode: PayMode,
        monthlySalary: Decimal,
        hourlyRate: Decimal,
        workdayCount: Int,
        netSeconds: TimeInterval
    ) -> Decimal {
        switch payMode {
        case .hourly:
            guard hourlyRate > 0 else { return 0 }
            return hourlyRate
        case .monthly:
            guard monthlySalary > 0, workdayCount > 0, netSeconds > 0 else { return 0 }
            let hours = Decimal(netSeconds) / Decimal(3600)
            return monthlySalary / (Decimal(workdayCount) * hours)
        }
    }

    static func earnings(seconds: TimeInterval, hourlyRate: Decimal) -> Decimal {
        let safeSeconds = max(0, seconds)
        guard safeSeconds > 0, hourlyRate > 0 else { return 0 }
        return hourlyRate * Decimal(safeSeconds) / Decimal(3600)
    }

    static func isInstantPaid(now: Date, schedule: WorkSchedule, calendar: Calendar) -> Bool {
        schedule.paidWindows(on: now, calendar: calendar).contains { window in
            now >= window.start && now < window.end
        }
    }

    /// 把计时区间裁到「今天」再与带薪窗口求交。昨天的区间如果还开着，只计今天午夜之后的带薪部分。
    static func workedPaidSeconds(
        now: Date,
        timer: TimerState,
        schedule: WorkSchedule,
        calendar: Calendar
    ) -> TimeInterval {
        let today = calendar.startOfDay(for: now)
        var total: TimeInterval = 0
        for segment in timer.segments {
            let segmentEnd = min(segment.end ?? now, now)
            let from = max(segment.start, today)
            guard segmentEnd > from else { continue }
            total += paidSeconds(from: from, to: segmentEnd, schedule: schedule, calendar: calendar)
        }
        return max(0, total)
    }

    static func paidSeconds(
        from start: Date,
        to end: Date,
        schedule: WorkSchedule,
        calendar: Calendar
    ) -> TimeInterval {
        guard end > start else { return 0 }
        var total: TimeInterval = 0
        forEachDay(from: calendar.startOfDay(for: start), until: end, calendar: calendar) { day in
            for window in schedule.paidWindows(on: day, calendar: calendar) {
                let lower = max(window.start, start)
                let upper = min(window.end, end)
                if upper > lower {
                    total += upper.timeIntervalSince(lower)
                }
            }
        }
        return total
    }

    static func workdayCount(inMonthOf date: Date, schedule: WorkSchedule, calendar: Calendar) -> Int {
        guard let interval = calendar.dateInterval(of: .month, for: date) else { return 0 }
        var count = 0
        forEachDay(from: interval.start, until: interval.end, calendar: calendar) { day in
            if schedule.isWorkday(day, calendar: calendar) {
                count += 1
            }
        }
        return count
    }

    /// 本月内、严格早于今天的工作日数量。今天即使是工作日也不算满勤，只算计时累计。
    static func pastWorkdayCount(before date: Date, schedule: WorkSchedule, calendar: Calendar) -> Int {
        let today = calendar.startOfDay(for: date)
        guard let interval = calendar.dateInterval(of: .month, for: date) else { return 0 }
        guard today > interval.start else { return 0 }
        var count = 0
        forEachDay(from: interval.start, until: today, calendar: calendar) { day in
            if schedule.isWorkday(day, calendar: calendar) {
                count += 1
            }
        }
        return count
    }

    private static func forEachDay(
        from start: Date,
        until end: Date,
        calendar: Calendar,
        body: (Date) -> Void
    ) {
        var day = start
        var safety = 0
        while day < end && safety < 400 {
            body(day)
            guard let next = calendar.date(byAdding: .day, value: 1, to: day), next > day else { break }
            day = next
            safety += 1
        }
    }
}
