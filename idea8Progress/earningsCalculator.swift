import Foundation

/// 计算器的全部输入。不读时钟、不读 UserDefaults，方便单测注入任意时刻。
struct EarningsInput {
    var now: Date
    var calendar: Calendar
    var settings: AppSettings
}

/// 面板上四个指标所需的快照。
struct EarningsSnapshot: Equatable {
    var now: Date
    var todayEarned: Decimal
    /// 此刻真正在往上跳的速度。不在带薪时段时为 0。
    var earnRatePerHour: Decimal
    /// 月薪按本月工作日和每日净工时折算出的时薪。
    var contractedHourlyRate: Decimal
    /// 今天从带薪窗口开始到此刻、已经走过的带薪秒数。不含午休、班次外和非工作日。
    var workedSeconds: TimeInterval
    /// 一个满勤日的净带薪秒数。默认 8.5 小时。
    var scheduledNetSeconds: TimeInterval
    var fullDayEarnings: Decimal
    var monthEarned: Decimal
    /// 本月今天之前、按排班应出勤的天数。这些天按满勤计入。
    var pastWorkdayCount: Int
    /// 本月全部应出勤天数，用来把月薪摊成日薪/时薪。含今天和尚未到来的工作日。
    var workdayCountInMonth: Int
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
        let ratePerHour = effectiveHourlyRate(
            monthlySalary: settings.monthlySalary,
            workdayCount: workdayCount,
            netSeconds: netSeconds
        )
        let worked = elapsedPaidSeconds(now: now, schedule: schedule, calendar: calendar)
        let fullDay = earnings(seconds: netSeconds, ratePerHour: ratePerHour)
        let today = earnings(seconds: worked, ratePerHour: ratePerHour)
        let month = fullDay * Decimal(pastCount) + today
        let earningNow = isInstantPaid(now: now, schedule: schedule, calendar: calendar)

        return EarningsSnapshot(
            now: now,
            todayEarned: today,
            earnRatePerHour: earningNow ? ratePerHour : 0,
            contractedHourlyRate: ratePerHour,
            workedSeconds: worked,
            scheduledNetSeconds: netSeconds,
            fullDayEarnings: fullDay,
            monthEarned: month,
            pastWorkdayCount: pastCount,
            workdayCountInMonth: workdayCount,
            isEarningNow: earningNow
        )
    }

    /// 月薪 ÷（本月工作日数 × 每日净工时）。工作日或净工时为 0 时返回 0，避免除零。
    static func effectiveHourlyRate(
        monthlySalary: Decimal,
        workdayCount: Int,
        netSeconds: TimeInterval
    ) -> Decimal {
        guard monthlySalary > 0, workdayCount > 0, netSeconds > 0 else { return 0 }
        let hours = Decimal(netSeconds) / Decimal(3600)
        return monthlySalary / (Decimal(workdayCount) * hours)
    }

    static func earnings(seconds: TimeInterval, ratePerHour: Decimal) -> Decimal {
        let safeSeconds = max(0, seconds)
        guard safeSeconds > 0, ratePerHour > 0 else { return 0 }
        return ratePerHour * Decimal(safeSeconds) / Decimal(3600)
    }

    static func isInstantPaid(now: Date, schedule: WorkSchedule, calendar: Calendar) -> Bool {
        schedule.paidWindows(on: now, calendar: calendar).contains { window in
            now >= window.start && now < window.end
        }
    }

    /// 今天已经发生的带薪秒数：从当天零点到 `now`，与带薪窗口求交。
    /// 上班前为 0，午休只保留上午那段，下班后停在满勤，非工作日为 0。
    static func elapsedPaidSeconds(
        now: Date,
        schedule: WorkSchedule,
        calendar: Calendar
    ) -> TimeInterval {
        let today = calendar.startOfDay(for: now)
        return paidSeconds(from: today, to: now, schedule: schedule, calendar: calendar)
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

    /// 本月内、严格早于今天的工作日数量。今天即使是工作日也不算满勤，只算到此刻已经走过的带薪时间。
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
