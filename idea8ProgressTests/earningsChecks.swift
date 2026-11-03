import Foundation
#if !LINUX_ALL_IN_ONE
@testable import idea8Progress
#endif

struct CheckFailure: Error, CustomStringConvertible {
    var description: String
    init(_ description: String) { self.description = description }
}

/// 不依赖 XCTest 的规则检查，Xcode 测试和本机脚本都可以跑同一套。
enum EarningsChecks {
    static func run() throws {
        let runner = Runner()
        let checks: [(String, () throws -> Void)] = [
            ("默认排班是 8.5 小时", runner.defaultScheduleIsEightAndAHalfHours),
            ("午休从上班窗口扣除", runner.lunchIsRemovedFromPaidWindows),
            ("边界时刻是否带薪", runner.paidInstantBoundaries),
            ("计时关闭不产生收入", runner.timerOffDoesNotEarn),
            ("带薪时段内计时按秒累计", runner.timerOnInsidePaidWindowEarns),
            ("午休开着计时器也不计", runner.lunchDoesNotEarn),
            ("跨午休只计两边", runner.segmentAcrossLunchCountsBothSides),
            ("班次外不计", runner.outsideWorkWindowDoesNotEarn),
            ("非工作日不计", runner.nonWorkdayDoesNotEarn),
            ("已过工作日按满勤而不是实际计时", runner.pastWeekdayUsesFullDayNotActualTimer),
            ("今天不重复算满勤", runner.todayIsNotCountedAsFullDay),
            ("月初还没有已过工作日", runner.firstWorkdayHasNoPastCredit),
            ("月末满勤加今天刚好等于月薪", runner.fullMonthMatchesSalary),
            ("月薪按本月工作日和净工时折算", runner.monthlyProrationMatchesHour),
            ("改月薪会改速度", runner.changingMonthlySalaryChangesEarnRate),
            ("没有工作日或净工时为 0 时不崩溃", runner.zeroScheduleDoesNotCrash),
            ("只勾选周一会改变分母", runner.mondayOnlyChangesProration),
            ("跨天只把今天的带薪部分算进今日", runner.overnightSegmentCountsOnlyToday),
            ("计时状态可以保存再读出", runner.stateStoreRoundTrip),
            ("旧存档里的时薪不再覆盖月薪", runner.legacyHourlyArchiveKeepsMonthlySalary),
            ("损坏的存档回退到默认值", runner.corruptStoreFallsBack),
            ("金额输入解析", runner.moneyParsing)
        ]

        var failures: [String] = []
        for (name, check) in checks {
            do {
                try check()
            } catch {
                failures.append("\(name): \(error)")
            }
        }
        if !failures.isEmpty {
            throw CheckFailure(failures.joined(separator: "\n"))
        }
    }
}

private struct Runner {
    let calendar: Calendar

    init() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 8 * 3600)!
        calendar.locale = Locale(identifier: "zh_CN")
        self.calendar = calendar
    }

    func defaultScheduleIsEightAndAHalfHours() throws {
        let schedule = WorkSchedule.default
        try expectEqual(schedule.workdays, Set([2, 3, 4, 5, 6]), "默认工作日应为周一到周五")
        try expectEqual(schedule.workStartMinutes, 10 * 60, "上班 10:00")
        try expectEqual(schedule.workEndMinutes, 20 * 60 + 30, "下班 20:30")
        try expectEqual(schedule.lunchStartMinutes, 12 * 60, "午休开始 12:00")
        try expectEqual(schedule.lunchEndMinutes, 14 * 60, "午休结束 14:00")
        try expectEqual(schedule.netPaidMinutes, 510, "10.5 小时减去 2 小时午休")
        try expectEqual(schedule.netPaidSeconds, 8.5 * 3600, "净秒数")

        let day = try makeDate(2026, 11, 3, 0, 0)
        try expectEqual(calendar.component(.weekday, from: day), 3, "2026-11-03 应为周二")
        let windows = schedule.paidWindows(on: day, calendar: calendar)
        try expectEqual(windows.count, 2, "上午一段、下午一段")
        try expectEqual(windows[0].duration, 2 * 3600, "10:00–12:00")
        try expectEqual(windows[1].duration, 6.5 * 3600, "14:00–20:30")
        try expectEqual(windows[0].duration + windows[1].duration, schedule.netPaidSeconds, "窗口之和等于净工时")
        try expectEqual(EarningsCalculator.workdayCount(inMonthOf: day, schedule: schedule, calendar: calendar), 21, "2026-11 有 21 个工作日")
    }

    func lunchIsRemovedFromPaidWindows() throws {
        var shorterLunch = WorkSchedule.default
        shorterLunch.lunchEndMinutes = 13 * 60
        try expectEqual(shorterLunch.netPaidMinutes, 570, "午休 1 小时则净工时 9.5 小时")

        var lunchOutside = WorkSchedule.default
        lunchOutside.lunchStartMinutes = 21 * 60
        lunchOutside.lunchEndMinutes = 22 * 60
        try expectEqual(lunchOutside.netPaidMinutes, 630, "午休在班次外则不扣")

        var partial = WorkSchedule.default
        partial.lunchStartMinutes = 20 * 60
        partial.lunchEndMinutes = 21 * 60
        try expectEqual(partial.netPaidMinutes, 600, "只扣与班次重叠的 30 分钟")

        var covered = WorkSchedule.default
        covered.lunchStartMinutes = 9 * 60
        covered.lunchEndMinutes = 21 * 60
        try expectEqual(covered.netPaidMinutes, 0, "午休盖住整个班次")

        var reversed = WorkSchedule.default
        reversed.workStartMinutes = 20 * 60
        reversed.workEndMinutes = 10 * 60
        try expectEqual(reversed.netPaidSeconds, 0, "下班不晚于上班")
    }

    func paidInstantBoundaries() throws {
        let schedule = WorkSchedule.default
        let checks: [(Int, Int, Bool)] = [
            (9, 59, false),
            (10, 0, true),
            (11, 59, true),
            (12, 0, false),
            (13, 59, false),
            (14, 0, true),
            (20, 29, true),
            (20, 30, false)
        ]
        for (hour, minute, expected) in checks {
            let now = try makeDate(2026, 11, 3, hour, minute)
            let actual = EarningsCalculator.isInstantPaid(now: now, schedule: schedule, calendar: calendar)
            try expectEqual(actual, expected, "\(hour):\(minute) 带薪应为 \(expected)")
        }
        let sunday = try makeDate(2026, 11, 1, 11, 0)
        try expectEqual(
            EarningsCalculator.isInstantPaid(now: sunday, schedule: schedule, calendar: calendar),
            false,
            "周日中午也不算带薪"
        )
    }

    func timerOffDoesNotEarn() throws {
        let start = try makeDate(2026, 11, 3, 10, 0)
        let later = try makeDate(2026, 11, 3, 11, 30)
        let idle = snapshot(now: later, settings: monthly(17_850), timer: .idle())
        try expectDecimal(idle.todayEarned, 0, "没开过计时")
        try expectDecimal(idle.earnRatePerHour, 0, "速度为 0")
        try expectEqual(idle.timerRunning, false, "未计时")

        var timer = TimerState.idle()
        timer.start(now: start)
        timer.stop(now: try makeDate(2026, 11, 3, 11, 0))
        let frozen = snapshot(now: later, settings: monthly(17_850), timer: timer)
        try expectEqual(frozen.workedSeconds, 3600, "停止后不再增加")
        try expectDecimal(frozen.todayEarned, 100, "停在 1 小时的收入")
        try expectDecimal(frozen.earnRatePerHour, 0, "停止后速度为 0")
        try expectEqual(frozen.isEarningNow, false, "不再入账")
    }

    func timerOnInsidePaidWindowEarns() throws {
        var timer = TimerState.idle()
        let start = try makeDate(2026, 11, 3, 10, 0)
        timer.start(now: start)
        let now = try makeDate(2026, 11, 3, 11, 0)
        let snap = snapshot(now: now, settings: monthly(17_850), timer: timer)
        try expectEqual(snap.workedSeconds, 3600, "工作 1 小时")
        try expectDecimal(snap.todayEarned, 100, "折算时薪 100，工作 1 小时")
        try expectDecimal(snap.earnRatePerHour, 100, "正在入账")
        try expectEqual(snap.isEarningNow, true, "处于带薪时段")
        try expectEqual(abs(snap.progress - (3600 / (8.5 * 3600))) < 0.0000001, true, "进度约为 1/8.5")
    }

    func lunchDoesNotEarn() throws {
        var timer = TimerState.idle()
        timer.start(now: try makeDate(2026, 11, 3, 12, 0))
        let snap = snapshot(now: try makeDate(2026, 11, 3, 13, 0), settings: monthly(17_850), timer: timer)
        try expectEqual(snap.workedSeconds, 0, "午休整小时")
        try expectDecimal(snap.todayEarned, 0, "午休没有收入")
        try expectEqual(snap.timerRunning, true, "计时器仍开着")
        try expectEqual(snap.isEarningNow, false, "当前不入账")
        try expectDecimal(snap.earnRatePerHour, 0, "速度为 0")
    }

    func segmentAcrossLunchCountsBothSides() throws {
        var timer = TimerState.idle()
        timer.start(now: try makeDate(2026, 11, 3, 11, 30))
        timer.stop(now: try makeDate(2026, 11, 3, 14, 30))
        let snap = snapshot(now: try makeDate(2026, 11, 3, 14, 30), settings: monthly(17_850), timer: timer)
        try expectEqual(snap.workedSeconds, 3600, "11:30–12:00 加 14:00–14:30")
        try expectDecimal(snap.todayEarned, 100, "只计 1 小时")
    }

    func outsideWorkWindowDoesNotEarn() throws {
        var evening = TimerState.idle()
        evening.start(now: try makeDate(2026, 11, 3, 21, 0))
        let afterHours = snapshot(now: try makeDate(2026, 11, 3, 22, 0), settings: monthly(17_850), timer: evening)
        try expectEqual(afterHours.workedSeconds, 0, "21:00 之后")
        try expectDecimal(afterHours.earnRatePerHour, 0, "班次外速度为 0")

        var morning = TimerState.idle()
        morning.start(now: try makeDate(2026, 11, 3, 9, 0))
        let partial = snapshot(now: try makeDate(2026, 11, 3, 10, 30), settings: monthly(17_850), timer: morning)
        try expectEqual(partial.workedSeconds, 1800, "9:00–10:30 只计 10:00 之后")
        try expectDecimal(partial.todayEarned, 50, "半小时")
    }

    func nonWorkdayDoesNotEarn() throws {
        var timer = TimerState.idle()
        timer.start(now: try makeDate(2026, 11, 1, 10, 0))
        let snap = snapshot(now: try makeDate(2026, 11, 1, 12, 0), settings: monthly(17_850), timer: timer)
        try expectEqual(calendar.component(.weekday, from: snap.now), 1, "11-01 是周日")
        try expectEqual(snap.workedSeconds, 0, "未勾选的周日")
        try expectEqual(snap.pastWorkdayCount, 0, "月初周日之前没有工作日")
        try expectDecimal(snap.monthEarned, 0, "本月还没开始累计")
    }

    func pastWeekdayUsesFullDayNotActualTimer() throws {
        var timer = TimerState.idle()
        timer.start(now: try makeDate(2026, 11, 2, 10, 0))
        timer.stop(now: try makeDate(2026, 11, 2, 11, 0))
        let snap = snapshot(now: try makeDate(2026, 11, 3, 15, 0), settings: monthly(17_850), timer: timer)
        try expectEqual(snap.pastWorkdayCount, 1, "11-02 周一已过")
        try expectEqual(snap.workedSeconds, 0, "昨天的计时不算进今天")
        try expectDecimal(snap.todayEarned, 0, "今天没计时")
        try expectDecimal(snap.fullDayEarnings, 850, "100 × 8.5")
        try expectDecimal(snap.monthEarned, 850, "满勤 850，而不是实际的 100")
    }

    func todayIsNotCountedAsFullDay() throws {
        var timer = TimerState.idle()
        timer.start(now: try makeDate(2026, 11, 3, 10, 0))
        let snap = snapshot(now: try makeDate(2026, 11, 3, 11, 0), settings: monthly(17_850), timer: timer)
        try expectEqual(snap.pastWorkdayCount, 1, "今天周二不算已过")
        try expectDecimal(snap.todayEarned, 100, "今天只计 1 小时")
        try expectDecimal(snap.monthEarned, 950, "850 + 100，不能把今天再加一整份")
        try expectEqual(snap.workdayCountInMonth, 21, "分母仍是全月")
    }

    func firstWorkdayHasNoPastCredit() throws {
        var timer = TimerState.idle()
        timer.start(now: try makeDate(2026, 11, 2, 10, 0))
        let snap = snapshot(now: try makeDate(2026, 11, 2, 11, 0), settings: monthly(17_850), timer: timer)
        try expectEqual(snap.pastWorkdayCount, 0, "周一是本月第一个工作日")
        try expectDecimal(snap.monthEarned, 100, "只有今天")
    }

    func fullMonthMatchesSalary() throws {
        var timer = TimerState.idle()
        timer.start(now: try makeDate(2026, 11, 30, 10, 0))
        timer.stop(now: try makeDate(2026, 11, 30, 20, 30))
        let settings = monthly(17_850)
        let snap = snapshot(now: try makeDate(2026, 11, 30, 20, 30), settings: settings, timer: timer)
        try expectEqual(snap.pastWorkdayCount, 20, "30 日之前有 20 个工作日")
        try expectEqual(snap.workedSeconds, 8.5 * 3600, "今天满勤")
        try expectDecimal(snap.monthEarned, 17_850, "20 个满勤日 + 今天 = 月薪")
    }

    func monthlyProrationMatchesHour() throws {
        var timer = TimerState.idle()
        timer.start(now: try makeDate(2026, 11, 3, 10, 0))
        let now = try makeDate(2026, 11, 3, 11, 0)
        let snap = snapshot(now: now, settings: monthly(17_850), timer: timer)
        try expectDecimal(snap.contractedHourlyRate, 100, "17850 / (21 × 8.5) = 100")
        try expectDecimal(snap.todayEarned, 100, "工作 1 小时")
        try expectDecimal(snap.monthEarned, 950, "满勤 850 + 今天 100")
        try expectDecimal(snap.fullDayEarnings, 850, "日满勤")
        try expectDecimal(snap.earnRatePerHour, 100, "计时中的速度等于折算时薪")
    }

    func changingMonthlySalaryChangesEarnRate() throws {
        var timer = TimerState.idle()
        timer.start(now: try makeDate(2026, 11, 3, 10, 0))
        let now = try makeDate(2026, 11, 3, 11, 0)
        let low = snapshot(now: now, settings: monthly(17_850), timer: timer)
        let high = snapshot(now: now, settings: monthly(35_700), timer: timer)
        try expectDecimal(low.earnRatePerHour, 100, "17850 的速度")
        try expectDecimal(high.earnRatePerHour, 200, "月薪加倍，速度加倍")
        try expectDecimal(high.todayEarned, 200, "同一小时的收入加倍")
        try expectDecimal(high.contractedHourlyRate, 200, "折算时薪跟着月薪走")
    }

    func zeroScheduleDoesNotCrash() throws {
        var noDays = WorkSchedule.default
        noDays.workdays = []
        var settings = monthly(17_850)
        settings.schedule = noDays
        let empty = snapshot(now: try makeDate(2026, 11, 3, 11, 0), settings: settings, timer: .idle())
        try expectEqual(empty.workdayCountInMonth, 0, "没有工作日")
        try expectDecimal(empty.contractedHourlyRate, 0, "无法摊销")
        try expectDecimal(empty.monthEarned, 0, "没有收入")
        try expectEqual(empty.progress, 0, "进度为 0")

        var zeroNet = WorkSchedule.default
        zeroNet.workStartMinutes = 10 * 60
        zeroNet.workEndMinutes = 10 * 60
        settings.schedule = zeroNet
        let flat = snapshot(now: try makeDate(2026, 11, 3, 11, 0), settings: settings, timer: .idle())
        try expectEqual(flat.scheduledNetSeconds, 0, "净工时为 0")
        try expectDecimal(flat.contractedHourlyRate, 0, "不除以 0")
        try expectDecimal(flat.monthEarned, 0, "没有收入")
    }

    func mondayOnlyChangesProration() throws {
        var schedule = WorkSchedule.default
        schedule.workdays = [2]
        var settings = monthly(17_850)
        settings.schedule = schedule
        let snap = snapshot(now: try makeDate(2026, 11, 3, 11, 0), settings: settings, timer: .idle())
        try expectEqual(snap.workdayCountInMonth, 5, "2026-11 的周一")
        try expectEqual(snap.pastWorkdayCount, 1, "11-02 是周一")
        try expectDecimal(snap.contractedHourlyRate, 420, "17850 / (5 × 8.5)")
        try expectDecimal(snap.fullDayEarnings, 3570, "日满勤")
        try expectDecimal(snap.monthEarned, 3570, "只补已经过去的那个周一")
    }

    func overnightSegmentCountsOnlyToday() throws {
        var timer = TimerState.idle()
        timer.start(now: try makeDate(2026, 11, 2, 20, 0))
        let morning = snapshot(now: try makeDate(2026, 11, 3, 9, 0), settings: monthly(17_850), timer: timer)
        try expectEqual(morning.workedSeconds, 0, "今天还没到 10:00")
        try expectDecimal(morning.monthEarned, 850, "昨天按满勤")
        try expectEqual(morning.isEarningNow, false, "9:00 不入账")

        let later = snapshot(now: try makeDate(2026, 11, 3, 11, 0), settings: monthly(17_850), timer: timer)
        try expectEqual(later.workedSeconds, 3600, "今天 10:00–11:00")
        try expectDecimal(later.todayEarned, 100, "不把昨晚 20:00–20:30 再加进今天")
        try expectDecimal(later.monthEarned, 950, "满勤 850 + 今天 100")

        let today = calendar.startOfDay(for: later.now)
        timer.prune(keepingFrom: today)
        try expectEqual(timer.segments.count, 1, "跨天的开启区间要保留")
        try expectEqual(timer.isRunning, true, "还在计时")
    }

    func stateStoreRoundTrip() throws {
        let suite = "idea8Progress.tests.\(UUID().uuidString)"
        let defaults = try makeDefaults(suite)
        defer { defaults.removePersistentDomain(forName: suite) }

        var settings = AppSettings.default
        settings.monthlySalary = Decimal(string: "12345.67")!
        var schedule = settings.schedule
        schedule.workdays.insert(9)
        schedule.workdays.remove(2)
        settings.schedule = schedule

        var timer = TimerState.idle()
        timer.start(now: try makeDate(2026, 11, 3, 10, 0))
        timer.stop(now: try makeDate(2026, 11, 3, 11, 0))
        timer.start(now: try makeDate(2026, 11, 3, 14, 0))

        StateStore.save(PersistedState(settings: settings, timer: timer), defaults: defaults)
        let loaded = StateStore.load(defaults: defaults)
        try expectDecimal(loaded.settings.monthlySalary, Decimal(string: "12345.67")!, "月薪按十进制往返")
        try expectEqual(loaded.settings.schedule.workdays.contains(9), false, "非法星期被丢掉")
        try expectEqual(loaded.settings.schedule.workdays.contains(2), false, "取消的周一还在")
        try expectEqual(loaded.timer.isRunning, true, "后一段仍在计时")
        try expectEqual(loaded.timer.segments.count, 2, "两段都在")

        settings.monthlySalary = -20
        StateStore.save(PersistedState(settings: settings, timer: timer), defaults: defaults)
        let sanitized = StateStore.load(defaults: defaults)
        try expectDecimal(sanitized.settings.monthlySalary, 0, "负数月薪被清掉")
    }

    func legacyHourlyArchiveKeepsMonthlySalary() throws {
        let suite = "idea8Progress.tests.\(UUID().uuidString)"
        let defaults = try makeDefaults(suite)
        defer { defaults.removePersistentDomain(forName: suite) }

        let json = """
        {"settings":{"payMode":"hourly","hourlyRate":"80","monthlySalary":"17850","schedule":{"workdays":[2,3,4,5,6],"workStartMinutes":600,"workEndMinutes":1230,"lunchStartMinutes":720,"lunchEndMinutes":840}},"timer":{"segments":[]}}
        """
        defaults.set(Data(json.utf8), forKey: StateStore.storageKey)
        let loaded = StateStore.load(defaults: defaults)
        try expectDecimal(loaded.settings.monthlySalary, 17_850, "仍读取月薪")
        try expectEqual(loaded.settings.schedule, WorkSchedule.default, "排班还在")
        let snap = snapshot(now: try makeDate(2026, 11, 3, 15, 0), settings: loaded.settings, timer: .idle())
        try expectDecimal(snap.contractedHourlyRate, 100, "忽略旧时薪，按月薪折算")
        try expectDecimal(snap.fullDayEarnings, 850, "日满勤按月薪")
    }

    func corruptStoreFallsBack() throws {
        let suite = "idea8Progress.tests.\(UUID().uuidString)"
        let defaults = try makeDefaults(suite)
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(Data("not-json".utf8), forKey: StateStore.storageKey)
        let loaded = StateStore.load(defaults: defaults)
        try expectEqual(loaded.settings, AppSettings.default, "坏数据回到默认设置")
        try expectEqual(loaded.timer.segments.isEmpty, true, "没有残留计时")
    }

    func moneyParsing() throws {
        try expectDecimal(MoneyFormat.parse("15000") ?? -1, 15_000, "整数")
        try expectDecimal(MoneyFormat.parse("¥1,500.50") ?? -1, Decimal(string: "1500.50")!, "货币符号和逗号")
        try expectDecimal(MoneyFormat.parse("1，234") ?? -1, 1234, "中文逗号")
        try expectDecimal(MoneyFormat.parse("  ") ?? -1, 0, "空白视为 0")
        try expectEqual(MoneyFormat.parse("abc") == nil, true, "无法解析")
        try expectEqual(MoneyFormat.currency(850), "¥850.00", "面板金额")
        try expectEqual(MoneyFormat.menuBar(Decimal(string: "12.5")!), "¥12.50", "菜单栏金额")
        try expectEqual(MoneyFormat.duration(3661), "1:01:01", "时分秒")
        try expectEqual(MoneyFormat.hours(8.5 * 3600), "8.5", "净工时展示")
    }

    private func monthly(_ salary: Decimal) -> AppSettings {
        var settings = AppSettings.default
        settings.monthlySalary = salary
        return settings
    }

    private func snapshot(now: Date, settings: AppSettings, timer: TimerState) -> EarningsSnapshot {
        EarningsCalculator.snapshot(
            EarningsInput(now: now, calendar: calendar, settings: settings, timer: timer)
        )
    }

    private func makeDate(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int) throws -> Date {
        var components = DateComponents()
        components.calendar = calendar
        components.timeZone = calendar.timeZone
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = minute
        components.second = 0
        guard let date = calendar.date(from: components) else {
            throw CheckFailure("无法生成日期 \(year)-\(month)-\(day) \(hour):\(minute)")
        }
        return date
    }

    private func makeDefaults(_ suite: String) throws -> UserDefaults {
        guard let defaults = UserDefaults(suiteName: suite) else {
            throw CheckFailure("无法创建 UserDefaults \(suite)")
        }
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    private func expectEqual<T: Equatable>(_ actual: T, _ expected: T, _ message: String) throws {
        if actual != expected {
            throw CheckFailure("\(message)。期望 \(expected)，实际 \(actual)")
        }
    }

    private func expectDecimal(_ actual: Decimal, _ expected: Decimal, _ message: String) throws {
        let delta = actual - expected
        let absolute = delta < 0 ? -delta : delta
        if absolute > Decimal(string: "0.000001")! {
            throw CheckFailure("\(message)。期望 \(expected)，实际 \(actual)")
        }
    }
}
