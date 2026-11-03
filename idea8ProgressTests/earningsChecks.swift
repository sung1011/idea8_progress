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
            ("上班时刻开始入账但还没有秒数", runner.workStartBeginsEarningWithZeroElapsed),
            ("带薪时段内按秒自动累计", runner.elapsedInsidePaidWindowEarns),
            ("午休不增加收入", runner.lunchDoesNotEarn),
            ("跨午休只计两边", runner.elapsedAcrossLunchCountsBothSides),
            ("班次外不计", runner.outsideWorkWindowDoesNotEarn),
            ("非工作日不计", runner.nonWorkdayDoesNotEarn),
            ("已过工作日按满勤", runner.pastWeekdayUsesFullDay),
            ("今天不重复算满勤", runner.todayIsNotCountedAsFullDay),
            ("月初还没有已过工作日", runner.firstWorkdayHasNoPastCredit),
            ("3 号且前两天都上班则补两个满勤日", runner.thirdOfMonthCreditsTwoFullWorkdaysPlusToday),
            ("月末满勤加今天刚好等于月薪", runner.fullMonthMatchesSalary),
            ("月薪按本月工作日和净工时折算", runner.monthlyProrationMatchesHour),
            ("改月薪会改速度", runner.changingMonthlySalaryChangesEarnRate),
            ("年薪先除以 12 再按自然月计算", runner.annualSalaryDividesIntoTheSameMonth),
            ("月薪模式不看年薪", runner.monthlyModeIgnoresAnnualSalary),
            ("月薪和年薪以及模式会一起保存", runner.salaryAmountsAndModePersist),
            ("认不出的薪资模式仍按月薪", runner.unknownSalaryModeStaysMonthly),
            ("没有工作日或净工时为 0 时不崩溃", runner.zeroScheduleDoesNotCrash),
            ("只勾选周一会改变分母", runner.mondayOnlyChangesProration),
            ("今天从上班重新计，不把昨天尾段算进来", runner.todayStartsAtScheduledWindow),
            ("设置可以保存再读出", runner.stateStoreRoundTrip),
            ("固定状态单独保存", runner.panelPinPreferenceRoundTrip),
            ("旧存档里的计时和时薪不再参与计算", runner.legacyArchiveDropsTimerAndHourlyRate),
            ("损坏的存档回退到默认值", runner.corruptStoreFallsBack),
            ("退休日按自然日计算", runner.retirementCountdownUsesCalendarDays),
            ("退休日期可以保存再读出", runner.retirementDateRoundTrip),
            ("坏的退休日字段不丢掉月薪", runner.malformedRetirementDateDoesNotWipeSalary),
            ("金额输入解析", runner.moneyParsing),
            ("菜单栏金额到元且可关闭", runner.menuBarYuanAndVisibilitySetting)
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

    func workStartBeginsEarningWithZeroElapsed() throws {
        let snap = snapshot(now: try makeDate(2026, 11, 3, 10, 0), settings: monthly(17_850))
        try expectEqual(snap.workedSeconds, 0, "刚到上班时刻还没有秒数")
        try expectDecimal(snap.todayEarned, 0, "还没赚到")
        try expectEqual(snap.isEarningNow, true, "已经进入带薪窗口")
        try expectDecimal(snap.earnRatePerHour, 100, "速度立刻是折算时薪")
    }

    func elapsedInsidePaidWindowEarns() throws {
        let atEleven = snapshot(now: try makeDate(2026, 11, 3, 11, 0), settings: monthly(17_850))
        try expectEqual(atEleven.workedSeconds, 3600, "10:00–11:00")
        try expectDecimal(atEleven.todayEarned, 100, "折算时薪 100，已过 1 小时")
        try expectDecimal(atEleven.earnRatePerHour, 100, "正在入账")
        try expectEqual(atEleven.isEarningNow, true, "处于带薪时段")
        try expectEqual(abs(atEleven.progress - (3600 / (8.5 * 3600))) < 0.0000001, true, "进度约为 1/8.5")

        let later = snapshot(now: try makeDate(2026, 11, 3, 11, 30), settings: monthly(17_850))
        try expectEqual(later.workedSeconds, 5400, "没有计时开关，时间往前走就继续累计")
        try expectDecimal(later.todayEarned, 150, "1.5 小时")
    }

    func lunchDoesNotEarn() throws {
        let atNoon = snapshot(now: try makeDate(2026, 11, 3, 12, 0), settings: monthly(17_850))
        let during = snapshot(now: try makeDate(2026, 11, 3, 13, 30), settings: monthly(17_850))
        try expectEqual(atNoon.workedSeconds, 2 * 3600, "上午整段")
        try expectDecimal(atNoon.todayEarned, 200, "上午已经赚到的保留")
        try expectEqual(during.workedSeconds, atNoon.workedSeconds, "午休期间不再增加")
        try expectDecimal(during.todayEarned, 200, "午休不加新收入")
        try expectEqual(during.isEarningNow, false, "当前不入账")
        try expectDecimal(during.earnRatePerHour, 0, "速度为 0")
    }

    func elapsedAcrossLunchCountsBothSides() throws {
        let before = snapshot(now: try makeDate(2026, 11, 3, 11, 30), settings: monthly(17_850))
        let after = snapshot(now: try makeDate(2026, 11, 3, 14, 30), settings: monthly(17_850))
        try expectEqual(before.workedSeconds, 1.5 * 3600, "10:00–11:30")
        try expectEqual(after.workedSeconds, 2.5 * 3600, "上午 2 小时 + 下午 30 分钟")
        try expectEqual(after.workedSeconds - before.workedSeconds, 3600, "跨午休只增加两边的 1 小时")
        try expectDecimal(after.todayEarned, 250, "2.5 × 100")
        try expectEqual(after.isEarningNow, true, "14:30 已回到带薪窗口")
    }

    func outsideWorkWindowDoesNotEarn() throws {
        let before = snapshot(now: try makeDate(2026, 11, 3, 9, 0), settings: monthly(17_850))
        try expectEqual(before.workedSeconds, 0, "上班前")
        try expectDecimal(before.todayEarned, 0, "上班前没有收入")
        try expectDecimal(before.earnRatePerHour, 0, "上班前速度为 0")
        try expectEqual(before.isEarningNow, false, "还没开始")

        let partial = snapshot(now: try makeDate(2026, 11, 3, 10, 30), settings: monthly(17_850))
        try expectEqual(partial.workedSeconds, 1800, "只计 10:00 之后")
        try expectDecimal(partial.todayEarned, 50, "半小时")

        let done = snapshot(now: try makeDate(2026, 11, 3, 20, 30), settings: monthly(17_850))
        let after = snapshot(now: try makeDate(2026, 11, 3, 22, 0), settings: monthly(17_850))
        try expectEqual(done.workedSeconds, 8.5 * 3600, "下班时刻记满")
        try expectEqual(after.workedSeconds, done.workedSeconds, "下班后不再增加")
        try expectDecimal(after.earnRatePerHour, 0, "班次外速度为 0")
        try expectDecimal(after.todayEarned, 850, "今天已是满勤")
        try expectEqual(after.isEarningNow, false, "已经下班")
    }

    func nonWorkdayDoesNotEarn() throws {
        let snap = snapshot(now: try makeDate(2026, 11, 1, 12, 0), settings: monthly(17_850))
        try expectEqual(calendar.component(.weekday, from: snap.now), 1, "11-01 是周日")
        try expectEqual(snap.workedSeconds, 0, "未勾选的周日")
        try expectDecimal(snap.todayEarned, 0, "非工作日没有今日收入")
        try expectDecimal(snap.earnRatePerHour, 0, "速度为 0")
        try expectEqual(snap.isEarningNow, false, "不入账")
        try expectEqual(snap.pastWorkdayCount, 0, "月初周日之前没有工作日")
        try expectDecimal(snap.monthEarned, 0, "本月还没开始累计")
    }

    func pastWeekdayUsesFullDay() throws {
        let snap = snapshot(now: try makeDate(2026, 11, 3, 15, 0), settings: monthly(17_850))
        try expectEqual(snap.pastWorkdayCount, 1, "11-02 周一已过，1 日周日不算")
        try expectEqual(snap.workedSeconds, 3 * 3600, "今天 10:00–12:00 加 14:00–15:00")
        try expectDecimal(snap.todayEarned, 300, "今天只算已经走过的 3 小时")
        try expectDecimal(snap.fullDayEarnings, 850, "100 × 8.5")
        try expectDecimal(snap.monthEarned, 1150, "昨天满勤 850 + 今天 300")
    }

    func todayIsNotCountedAsFullDay() throws {
        let snap = snapshot(now: try makeDate(2026, 11, 3, 11, 0), settings: monthly(17_850))
        try expectEqual(snap.pastWorkdayCount, 1, "今天周二不算已过")
        try expectDecimal(snap.todayEarned, 100, "今天只计 1 小时")
        try expectDecimal(snap.monthEarned, 950, "850 + 100，不能把今天再加一整份")
        try expectEqual(snap.workdayCountInMonth, 21, "分母仍是全月")
    }

    func firstWorkdayHasNoPastCredit() throws {
        let snap = snapshot(now: try makeDate(2026, 11, 2, 11, 0), settings: monthly(17_850))
        try expectEqual(snap.pastWorkdayCount, 0, "周一是本月第一个工作日")
        try expectDecimal(snap.todayEarned, 100, "今天已过 1 小时")
        try expectDecimal(snap.monthEarned, 100, "只有今天")
    }

    func thirdOfMonthCreditsTwoFullWorkdaysPlusToday() throws {
        var settings = monthly(25_500)
        settings.schedule.workdays = [1, 2, 3, 4, 5, 6, 7]
        let snap = snapshot(now: try makeDate(2026, 11, 3, 11, 0), settings: settings)
        try expectEqual(snap.workdayCountInMonth, 30, "2026-11 每天都上班")
        try expectEqual(snap.pastWorkdayCount, 2, "1 日和 2 日都已满勤")
        try expectEqual(snap.workedSeconds, 3600, "今天已过 1 小时带薪")
        try expectDecimal(snap.contractedHourlyRate, 100, "25500 / (30 × 8.5) = 100")
        try expectDecimal(snap.todayEarned, 100, "今天")
        try expectDecimal(snap.fullDayEarnings, 850, "日满勤")
        try expectDecimal(snap.monthEarned, 1800, "850 × 2 + 100")
    }

    func fullMonthMatchesSalary() throws {
        let snap = snapshot(now: try makeDate(2026, 11, 30, 20, 30), settings: monthly(17_850))
        try expectEqual(snap.pastWorkdayCount, 20, "30 日之前有 20 个工作日")
        try expectEqual(snap.workedSeconds, 8.5 * 3600, "今天满勤")
        try expectDecimal(snap.todayEarned, 850, "今天记满")
        try expectEqual(snap.isEarningNow, false, "20:30 已下班")
        try expectDecimal(snap.earnRatePerHour, 0, "下班后速度为 0")
        try expectDecimal(snap.monthEarned, 17_850, "20 个满勤日 + 今天 = 月薪")
    }

    func monthlyProrationMatchesHour() throws {
        let snap = snapshot(now: try makeDate(2026, 11, 3, 11, 0), settings: monthly(17_850))
        try expectDecimal(snap.contractedHourlyRate, 100, "17850 / (21 × 8.5) = 100")
        try expectDecimal(snap.todayEarned, 100, "已过 1 小时")
        try expectDecimal(snap.monthEarned, 950, "满勤 850 + 今天 100")
        try expectDecimal(snap.fullDayEarnings, 850, "日满勤")
        try expectDecimal(snap.earnRatePerHour, 100, "带薪时段内速度等于折算时薪")
    }

    func changingMonthlySalaryChangesEarnRate() throws {
        let now = try makeDate(2026, 11, 3, 11, 0)
        let low = snapshot(now: now, settings: monthly(17_850))
        let high = snapshot(now: now, settings: monthly(35_700))
        try expectDecimal(low.earnRatePerHour, 100, "17850 的速度")
        try expectDecimal(high.earnRatePerHour, 200, "月薪加倍，速度加倍")
        try expectDecimal(high.todayEarned, 200, "同一小时的收入加倍")
        try expectDecimal(high.contractedHourlyRate, 200, "折算时薪跟着月薪走")
    }

    func annualSalaryDividesIntoTheSameMonth() throws {
        let during = try makeDate(2026, 11, 3, 15, 0)
        let fromMonthly = snapshot(now: during, settings: monthly(17_850))
        let fromAnnual = snapshot(now: during, settings: annual(214_200))
        try expectDecimal(fromAnnual.contractedHourlyRate, fromMonthly.contractedHourlyRate, "214200 ÷ 12 等于月薪 17850")
        try expectDecimal(fromAnnual.todayEarned, fromMonthly.todayEarned, "今日已赚走同一套月度折算")
        try expectDecimal(fromAnnual.monthEarned, fromMonthly.monthEarned, "本月累计走同一套月度折算")
        try expectDecimal(fromAnnual.fullDayEarnings, fromMonthly.fullDayEarnings, "日满勤走同一套月度折算")
        try expectDecimal(fromAnnual.earnRatePerHour, fromMonthly.earnRatePerHour, "速度走同一套月度折算")
        try expectEqual(fromAnnual.workedSeconds, fromMonthly.workedSeconds, "工时仍按当天排班")
        try expectEqual(fromAnnual.pastWorkdayCount, fromMonthly.pastWorkdayCount, "已过工作日不变")
        try expectEqual(fromAnnual.workdayCountInMonth, 21, "分母仍是 2026-11 的工作日")

        let done = snapshot(now: try makeDate(2026, 11, 30, 20, 30), settings: annual(214_200))
        try expectDecimal(done.monthEarned, 17_850, "月末满勤等于年薪的十二分之一，不是整年")
        try expectEqual(done.workdayCountInMonth, 21, "统计范围仍是当前自然月")

        var uneven = AppSettings.default
        uneven.salaryMode = .annual
        uneven.annualSalary = 1
        try expectDecimal(uneven.effectiveMonthlySalary, Decimal(1) / 12, "年薪按 12 个月折算")
        let zero = snapshot(now: during, settings: annual(0))
        try expectDecimal(zero.contractedHourlyRate, 0, "年薪为 0 时不摊销")
        try expectDecimal(zero.monthEarned, 0, "年薪为 0 时本月没有收入")
    }

    func monthlyModeIgnoresAnnualSalary() throws {
        var settings = monthly(17_850)
        settings.annualSalary = 999_999
        let snap = snapshot(now: try makeDate(2026, 11, 3, 11, 0), settings: settings)
        try expectEqual(settings.salaryMode, .monthly, "默认按月薪输入")
        try expectDecimal(snap.contractedHourlyRate, 100, "月薪模式只用月薪")
        try expectDecimal(snap.todayEarned, 100, "今日已赚不看年薪")
        try expectDecimal(snap.monthEarned, 950, "本月累计不看年薪")
    }

    func salaryAmountsAndModePersist() throws {
        let suite = "idea8Progress.tests.\(UUID().uuidString)"
        let defaults = try makeDefaults(suite)
        defer { defaults.removePersistentDomain(forName: suite) }

        let during = try makeDate(2026, 11, 3, 11, 0)
        let retirement = RetirementDate(year: 2031, month: 5, day: 1)
        let model = EarningsModel(defaults: defaults, calendar: calendar, now: during, startTicker: false)
        model.setMonthlySalary(17_850, now: during)
        model.setAnnualSalary(214_200, now: during)
        model.setRetirementDate(retirement, now: during)
        try expectEqual(model.settings.salaryMode, .monthly, "还没切换时按月薪")
        try expectDecimal(model.snapshot.contractedHourlyRate, 100, "月薪 17850 的速度")

        model.setSalaryMode(.annual, now: during)
        try expectDecimal(model.settings.monthlySalary, 17_850, "切到年薪不改已存的月薪")
        try expectDecimal(model.settings.annualSalary, 214_200, "年薪仍是刚才填写的")
        try expectEqual(model.settings.retirementDate, retirement, "切换年薪不改退休日")
        try expectDecimal(model.snapshot.contractedHourlyRate, 100, "年薪 ÷ 12 后速度不变")
        try expectEqual(model.snapshot.workdayCountInMonth, 21, "面板仍按本月工作日")

        let monthEnd = try makeDate(2026, 11, 30, 20, 30)
        model.tick(now: monthEnd)
        try expectDecimal(model.snapshot.monthEarned, 17_850, "自然月末满勤等于年薪的十二分之一")

        model.setSalaryMode(.monthly, now: monthEnd)
        model.setAnnualSalary(-8, now: monthEnd)
        try expectDecimal(model.settings.annualSalary, 0, "负数年薪被清掉")
        try expectDecimal(model.snapshot.monthEarned, 17_850, "切回月薪后仍用月薪")
        try expectEqual(model.settings.retirementDate, retirement, "改年薪不改退休日")

        let loaded = StateStore.load(defaults: defaults)
        try expectEqual(loaded.settings.salaryMode, .monthly, "模式写入 UserDefaults")
        try expectDecimal(loaded.settings.monthlySalary, 17_850, "月薪写入 UserDefaults")
        try expectDecimal(loaded.settings.annualSalary, 0, "年薪写入 UserDefaults")
        try expectEqual(loaded.settings.retirementDate, retirement, "退休日仍在同一份存档里")
    }

    func unknownSalaryModeStaysMonthly() throws {
        let suite = "idea8Progress.tests.\(UUID().uuidString)"
        let defaults = try makeDefaults(suite)
        defer { defaults.removePersistentDomain(forName: suite) }

        let json = """
        {"settings":{"salaryMode":"hourly","monthlySalary":"17850","annualSalary":"10","schedule":{"workdays":[2,3,4,5,6],"workStartMinutes":600,"workEndMinutes":1230,"lunchStartMinutes":720,"lunchEndMinutes":840}}}
        """
        defaults.set(Data(json.utf8), forKey: StateStore.storageKey)
        let loaded = StateStore.load(defaults: defaults)
        try expectEqual(loaded.settings.salaryMode, .monthly, "认不出的模式按月薪")
        try expectDecimal(loaded.settings.monthlySalary, 17_850, "月薪还在")
        try expectDecimal(loaded.settings.annualSalary, 10, "年薪还在")
        try expectEqual(loaded.settings.retirementDate == nil, true, "没写退休日时仍是空")
        let snap = snapshot(now: try makeDate(2026, 11, 3, 11, 0), settings: loaded.settings)
        try expectDecimal(snap.contractedHourlyRate, 100, "仍按月薪折算")
    }

    func zeroScheduleDoesNotCrash() throws {
        var noDays = WorkSchedule.default
        noDays.workdays = []
        var settings = monthly(17_850)
        settings.schedule = noDays
        let empty = snapshot(now: try makeDate(2026, 11, 3, 11, 0), settings: settings)
        try expectEqual(empty.workdayCountInMonth, 0, "没有工作日")
        try expectDecimal(empty.contractedHourlyRate, 0, "无法摊销")
        try expectDecimal(empty.monthEarned, 0, "没有收入")
        try expectEqual(empty.progress, 0, "进度为 0")
        try expectEqual(empty.isEarningNow, false, "没有带薪窗口")

        var zeroNet = WorkSchedule.default
        zeroNet.workStartMinutes = 10 * 60
        zeroNet.workEndMinutes = 10 * 60
        settings.schedule = zeroNet
        let flat = snapshot(now: try makeDate(2026, 11, 3, 11, 0), settings: settings)
        try expectEqual(flat.scheduledNetSeconds, 0, "净工时为 0")
        try expectDecimal(flat.contractedHourlyRate, 0, "不除以 0")
        try expectDecimal(flat.monthEarned, 0, "没有收入")
    }

    func mondayOnlyChangesProration() throws {
        var schedule = WorkSchedule.default
        schedule.workdays = [2]
        var settings = monthly(17_850)
        settings.schedule = schedule
        let snap = snapshot(now: try makeDate(2026, 11, 3, 11, 0), settings: settings)
        try expectEqual(snap.workdayCountInMonth, 5, "2026-11 的周一")
        try expectEqual(snap.pastWorkdayCount, 1, "11-02 是周一")
        try expectDecimal(snap.contractedHourlyRate, 420, "17850 / (5 × 8.5)")
        try expectDecimal(snap.fullDayEarnings, 3570, "日满勤")
        try expectDecimal(snap.todayEarned, 0, "周二没勾选")
        try expectEqual(snap.isEarningNow, false, "非工作日不入账")
        try expectDecimal(snap.monthEarned, 3570, "只补已经过去的那个周一")
    }

    func todayStartsAtScheduledWindow() throws {
        let morning = snapshot(now: try makeDate(2026, 11, 3, 9, 0), settings: monthly(17_850))
        try expectEqual(morning.workedSeconds, 0, "今天还没到 10:00")
        try expectDecimal(morning.monthEarned, 850, "昨天按满勤")
        try expectEqual(morning.isEarningNow, false, "9:00 不入账")

        let later = snapshot(now: try makeDate(2026, 11, 3, 11, 0), settings: monthly(17_850))
        try expectEqual(later.workedSeconds, 3600, "今天 10:00–11:00")
        try expectDecimal(later.todayEarned, 100, "不把昨晚 20:00–20:30 再加进今天")
        try expectDecimal(later.monthEarned, 950, "满勤 850 + 今天 100")
    }

    func stateStoreRoundTrip() throws {
        let suite = "idea8Progress.tests.\(UUID().uuidString)"
        let defaults = try makeDefaults(suite)
        defer { defaults.removePersistentDomain(forName: suite) }

        var settings = AppSettings.default
        settings.salaryMode = .annual
        settings.monthlySalary = Decimal(string: "12345.67")!
        settings.annualSalary = Decimal(string: "99999.01")!
        var schedule = settings.schedule
        schedule.workdays.insert(9)
        schedule.workdays.remove(2)
        settings.schedule = schedule

        StateStore.save(PersistedState(settings: settings), defaults: defaults)
        let loaded = StateStore.load(defaults: defaults)
        try expectEqual(loaded.settings.salaryMode, .annual, "薪资模式往返")
        try expectDecimal(loaded.settings.monthlySalary, Decimal(string: "12345.67")!, "月薪按十进制往返")
        try expectDecimal(loaded.settings.annualSalary, Decimal(string: "99999.01")!, "年薪按十进制往返")
        try expectEqual(loaded.settings.schedule.workdays.contains(9), false, "非法星期被丢掉")
        try expectEqual(loaded.settings.schedule.workdays.contains(2), false, "取消的周一还在")

        settings.monthlySalary = -20
        settings.annualSalary = -5
        StateStore.save(PersistedState(settings: settings), defaults: defaults)
        let sanitized = StateStore.load(defaults: defaults)
        try expectDecimal(sanitized.settings.monthlySalary, 0, "负数月薪被清掉")
        try expectDecimal(sanitized.settings.annualSalary, 0, "负数年薪被清掉")
        try expectEqual(sanitized.settings.salaryMode, .annual, "清掉负数时保留模式")

        let saved = defaults.data(forKey: StateStore.storageKey) ?? Data()
        let text = String(decoding: saved, as: UTF8.self)
        try expectEqual(text.contains("timer"), false, "新存档不写计时")
        try expectEqual(text.contains("segments"), false, "新存档不写区间")
        try expectEqual(loaded.settings.retirementDate == nil, true, "没填退休日时读出来仍是空")
        try expectEqual(text.contains("retirementDate"), false, "没设置时不写退休日")
    }

    func panelPinPreferenceRoundTrip() throws {
        let suite = "idea8Progress.tests.pin.\(UUID().uuidString)"
        let defaults = try makeDefaults(suite)
        defer { defaults.removePersistentDomain(forName: suite) }

        try expectEqual(PanelPinStore.loadPinned(defaults: defaults), false, "默认不固定")
        PanelPinStore.savePinned(true, defaults: defaults)
        try expectEqual(PanelPinStore.loadPinned(defaults: defaults), true, "固定会记住")
        PanelPinStore.savePinned(false, defaults: defaults)
        try expectEqual(PanelPinStore.loadPinned(defaults: defaults), false, "取消固定会记住")

        let frame = StoredPanelFrame(x: 12, y: 34, width: 336, height: 420)
        PanelPinStore.saveFrame(frame, defaults: defaults)
        try expectEqual(PanelPinStore.loadFrame(defaults: defaults), frame, "浮动窗口位置会记住")
        try expectEqual(StoredPanelFrame(encoded: "bad"), nil, "坏的位置数据忽略")
        try expectEqual(StoredPanelFrame(encoded: "1,2,3,4"), nil, "过小的窗口忽略")
        PanelPinStore.saveFrame(nil, defaults: defaults)
        try expectEqual(PanelPinStore.loadFrame(defaults: defaults), nil, "位置可以清掉")
        try expectEqual(PanelPinStore.pinnedKey == StateStore.storageKey, false, "固定状态不写进计薪存档")
    }

    func legacyArchiveDropsTimerAndHourlyRate() throws {
        let suite = "idea8Progress.tests.\(UUID().uuidString)"
        let defaults = try makeDefaults(suite)
        defer { defaults.removePersistentDomain(forName: suite) }

        let json = """
        {"settings":{"payMode":"hourly","hourlyRate":"80","monthlySalary":"17850","schedule":{"workdays":[2,3,4,5,6],"workStartMinutes":600,"workEndMinutes":1230,"lunchStartMinutes":720,"lunchEndMinutes":840}},"timer":{"segments":[{"start":0,"end":null}]}}
        """
        defaults.set(Data(json.utf8), forKey: StateStore.storageKey)
        let loaded = StateStore.load(defaults: defaults)
        try expectEqual(loaded.settings.salaryMode, .monthly, "旧的时薪计薪方式不会改成按年薪输入")
        try expectDecimal(loaded.settings.monthlySalary, 17_850, "仍读取月薪")
        try expectDecimal(loaded.settings.annualSalary, 214_200, "没有年薪时按月薪 × 12 补齐")
        try expectEqual(loaded.settings.schedule, WorkSchedule.default, "排班还在")
        try expectEqual(loaded.settings.retirementDate == nil, true, "旧存档没有退休日")
        try expectEqual(loaded.settings.showMenuBarEarnings, true, "旧存档没有菜单栏开关时默认显示")

        let snap = snapshot(now: try makeDate(2026, 11, 3, 15, 0), settings: loaded.settings)
        try expectDecimal(snap.contractedHourlyRate, 100, "忽略旧时薪，按月薪折算")
        try expectDecimal(snap.fullDayEarnings, 850, "日满勤按月薪")
        try expectDecimal(snap.todayEarned, 300, "不看旧计时，今天按排班已过的 3 小时算")
        try expectEqual(snap.isEarningNow, true, "15:00 在带薪窗口里")

        let saved = defaults.data(forKey: StateStore.storageKey) ?? Data()
        let text = String(decoding: saved, as: UTF8.self)
        try expectEqual(text.contains("timer"), false, "重新保存后不再写计时")
        try expectEqual(text.contains("segments"), false, "重新保存后不再写区间")
        try expectEqual(text.contains("hourlyRate"), false, "不再写时薪")
        try expectEqual(text.contains("payMode"), false, "不再写计薪方式")
    }

    func corruptStoreFallsBack() throws {
        let suite = "idea8Progress.tests.\(UUID().uuidString)"
        let defaults = try makeDefaults(suite)
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(Data("not-json".utf8), forKey: StateStore.storageKey)
        let loaded = StateStore.load(defaults: defaults)
        try expectEqual(loaded.settings, AppSettings.default, "坏数据回到默认设置")
    }

    func retirementCountdownUsesCalendarDays() throws {
        try expectEqual(AppSettings.default.retirementDate == nil, true, "默认不填退休日")
        try expectEqual(
            RetirementDate.calendarDays(from: try makeDate(2026, 11, 3, 15, 0), until: nil, calendar: calendar) == nil,
            true,
            "没设置时不算天数"
        )
        try expectEqual(RetirementDate.panelSentence(days: 0), "距离退休还有 0 天", "当天")
        try expectEqual(RetirementDate.panelSentence(days: 12), "距离退休还有 12 天", "未来")
        try expectEqual(RetirementDate.panelSentence(days: -3), "退休日已过 3 天", "已过")
        try expectEqual(RetirementDate.unsetPrompt.contains("设置"), true, "空日期要提示去设置")

        let late = try makeDate(2026, 11, 3, 23, 59)
        try expectEqual(
            RetirementDate.calendarDays(from: late, until: RetirementDate(year: 2026, month: 11, day: 3), calendar: calendar),
            0,
            "同一自然日的深夜仍是 0 天"
        )
        try expectEqual(
            RetirementDate.calendarDays(from: late, until: RetirementDate(year: 2026, month: 11, day: 4), calendar: calendar),
            1,
            "过了午夜前仍按日历算到明天是 1 天"
        )
        try expectEqual(
            RetirementDate.calendarDays(from: try makeDate(2026, 11, 3, 0, 1), until: RetirementDate(year: 2026, month: 11, day: 1), calendar: calendar),
            -2,
            "退休日在两天前"
        )
        try expectEqual(
            RetirementDate.calendarDays(from: try makeDate(2026, 12, 31, 22, 0), until: RetirementDate(year: 2027, month: 1, day: 1), calendar: calendar),
            1,
            "跨年只差 1 个自然日"
        )
        try expectEqual(
            RetirementDate.calendarDays(from: try makeDate(2024, 2, 28, 23, 59), until: RetirementDate(year: 2024, month: 3, day: 1), calendar: calendar),
            2,
            "闰年 2 月 28 日到 3 月 1 日隔着 29 日"
        )
        try expectEqual(
            RetirementDate.calendarDays(from: try makeDate(2023, 2, 28, 8, 0), until: RetirementDate(year: 2023, month: 3, day: 1), calendar: calendar),
            1,
            "平年 2 月 28 日到 3 月 1 日只差 1 天"
        )
        try expectEqual(
            RetirementDate.calendarDays(from: try makeDate(2026, 11, 6, 18, 0), until: RetirementDate(year: 2026, month: 11, day: 9), calendar: calendar),
            3,
            "周五到周一是 3 个自然日，不是工作日"
        )

        try expectEqual(RetirementDate(year: 2024, month: 2, day: 29).validated() != nil, true, "闰日有效")
        try expectEqual(RetirementDate(year: 2023, month: 2, day: 29).validated() == nil, true, "平年 2 月 29 日无效")
        try expectEqual(RetirementDate(year: 2026, month: 2, day: 31).validated() == nil, true, "2 月 31 日无效")
        try expectEqual(RetirementDate.dayCount(year: 2024, month: 2), 29, "2024 年 2 月 29 天")
        try expectEqual(RetirementDate.dayCount(year: 2023, month: 2), 28, "2023 年 2 月 28 天")
        try expectEqual(RetirementDate.dayCount(year: 2026, month: 11), 30, "11 月 30 天")
        try expectEqual(RetirementDate.dayCount(year: 2026, month: 13) == nil, true, "没有 13 月")
    }

    func retirementDateRoundTrip() throws {
        let suite = "idea8Progress.tests.\(UUID().uuidString)"
        let defaults = try makeDefaults(suite)
        defer { defaults.removePersistentDomain(forName: suite) }

        let now = try makeDate(2026, 11, 3, 15, 0)
        let model = EarningsModel(defaults: defaults, calendar: calendar, now: now, startTicker: false)
        try expectEqual(model.settings.retirementDate == nil, true, "新存档没有退休日")
        let before = model.snapshot

        let date = RetirementDate(year: 2035, month: 6, day: 1)
        model.setRetirementDate(date, now: now)
        try expectEqual(model.settings.retirementDate, date, "模型记下退休日")
        try expectDecimal(model.snapshot.todayEarned, before.todayEarned, "设置退休日不改变今日已赚")
        try expectDecimal(model.snapshot.earnRatePerHour, before.earnRatePerHour, "设置退休日不改变速度")
        try expectEqual(model.snapshot.workedSeconds, before.workedSeconds, "设置退休日不改变工时")
        try expectDecimal(model.snapshot.monthEarned, before.monthEarned, "设置退休日不改变本月累计")
        try expectEqual(model.snapshot.isEarningNow, before.isEarningNow, "设置退休日不改变是否入账")

        let loaded = StateStore.load(defaults: defaults)
        try expectEqual(loaded.settings.retirementDate, date, "UserDefaults 里能读回退休日")
        try expectEqual(loaded.settings.schedule, WorkSchedule.default, "排班没被退休日改掉")
        try expectDecimal(loaded.settings.monthlySalary, 15_000, "月薪没被退休日改掉")
        try expectEqual(
            RetirementDate.calendarDays(from: now, until: loaded.settings.retirementDate, calendar: calendar),
            3132,
            "2026-11-03 到 2035-06-01 的自然日"
        )

        model.setRetirementDate(RetirementDate(year: 2023, month: 2, day: 29), now: now)
        try expectEqual(model.settings.retirementDate == nil, true, "平年 2 月 29 日不保存")

        let leapDay = RetirementDate(year: 2024, month: 2, day: 29)
        model.setRetirementDate(leapDay, now: now)
        try expectEqual(StateStore.load(defaults: defaults).settings.retirementDate, leapDay, "闰日可以保存")

        var invalid = AppSettings.default
        invalid.retirementDate = RetirementDate(year: 2026, month: 2, day: 31)
        StateStore.save(PersistedState(settings: invalid), defaults: defaults)
        try expectEqual(StateStore.load(defaults: defaults).settings.retirementDate == nil, true, "非法日期在保存时丢掉")

        model.setRetirementDate(nil, now: now)
        let cleared = defaults.data(forKey: StateStore.storageKey) ?? Data()
        let text = String(decoding: cleared, as: UTF8.self)
        try expectEqual(StateStore.load(defaults: defaults).settings.retirementDate == nil, true, "清除后存档为空")
        try expectEqual(text.contains("retirementDate"), false, "清除后不再写入退休日字段")
        try expectDecimal(model.snapshot.todayEarned, before.todayEarned, "清除退休日也不改变收入")
    }

    func malformedRetirementDateDoesNotWipeSalary() throws {
        let suite = "idea8Progress.tests.\(UUID().uuidString)"
        let defaults = try makeDefaults(suite)
        defer { defaults.removePersistentDomain(forName: suite) }

        let json = """
        {"settings":{"monthlySalary":"17850","schedule":{"workdays":[2,3,4,5,6],"workStartMinutes":600,"workEndMinutes":1230,"lunchStartMinutes":720,"lunchEndMinutes":840},"retirementDate":"soon"}}
        """
        defaults.set(Data(json.utf8), forKey: StateStore.storageKey)
        let loaded = StateStore.load(defaults: defaults)
        try expectDecimal(loaded.settings.monthlySalary, 17_850, "坏的退休日字段不丢掉月薪")
        try expectEqual(loaded.settings.schedule, WorkSchedule.default, "排班还在")
        try expectEqual(loaded.settings.retirementDate == nil, true, "坏的退休日当成没设置")
    }

    func moneyParsing() throws {
        try expectDecimal(MoneyFormat.parse("15000") ?? -1, 15_000, "整数")
        try expectDecimal(MoneyFormat.parse("¥1,500.50") ?? -1, Decimal(string: "1500.50")!, "货币符号和逗号")
        try expectDecimal(MoneyFormat.parse("1，234") ?? -1, 1234, "中文逗号")
        try expectDecimal(MoneyFormat.parse("  ") ?? -1, 0, "空白视为 0")
        try expectEqual(MoneyFormat.parse("abc") == nil, true, "无法解析")
        try expectEqual(MoneyFormat.currency(850), "¥850.00", "面板金额")
        try expectEqual(MoneyFormat.menuBar(Decimal(string: "12.5")!), "¥13", "菜单栏四舍五入到元")
        try expectEqual(MoneyFormat.menuBar(Decimal(string: "12.49")!), "¥12", "不到五角舍去")
        try expectEqual(MoneyFormat.menuBar(128), "¥128", "整数元")
        try expectEqual(MoneyFormat.menuBar(Decimal(string: "0.5")!), "¥1", "五角进一")
        try expectEqual(MoneyFormat.menuBar(0), "¥0", "可以为 ¥0")
        try expectEqual(MoneyFormat.menuBar(Decimal(string: "15000.4")!), "¥15000", "不缩写也不加小数")
        try expectEqual(MoneyFormat.menuBar(Decimal(string: "15000.5")!), "¥15001", "不用 k 缩写")
        try expectEqual(MoneyFormat.duration(3661), "1:01:01", "时分秒")
        try expectEqual(MoneyFormat.hours(8.5 * 3600), "8.5", "净工时展示")
    }

    func menuBarYuanAndVisibilitySetting() throws {
        try expectEqual(AppSettings.default.showMenuBarEarnings, true, "默认显示菜单栏金额")

        let suite = "idea8Progress.tests.\(UUID().uuidString)"
        let defaults = try makeDefaults(suite)
        defer { defaults.removePersistentDomain(forName: suite) }

        let now = try makeDate(2026, 11, 3, 11, 0)
        let model = EarningsModel(defaults: defaults, calendar: calendar, now: now, startTicker: false)
        try expectEqual(model.settings.showMenuBarEarnings, true, "新安装默认打开")
        let before = model.snapshot
        model.setShowMenuBarEarnings(false, now: now)
        try expectEqual(model.settings.showMenuBarEarnings, false, "可以关掉")
        try expectDecimal(model.snapshot.todayEarned, before.todayEarned, "开关不改变今日已赚")
        try expectDecimal(model.snapshot.earnRatePerHour, before.earnRatePerHour, "开关不改变速度")
        try expectEqual(model.snapshot.workedSeconds, before.workedSeconds, "开关不改变工时")
        try expectDecimal(model.snapshot.monthEarned, before.monthEarned, "开关不改变本月累计")
        try expectEqual(model.snapshot.isEarningNow, before.isEarningNow, "开关不改变是否入账")
        try expectEqual(model.settings.retirementDate == nil, true, "开关不改退休日")

        let loaded = StateStore.load(defaults: defaults)
        try expectEqual(loaded.settings.showMenuBarEarnings, false, "关闭状态写入 UserDefaults")
        try expectDecimal(loaded.settings.monthlySalary, 15_000, "月薪没被开关改掉")

        let restored = EarningsModel(defaults: defaults, calendar: calendar, now: now, startTicker: false)
        try expectEqual(restored.settings.showMenuBarEarnings, false, "下次启动仍关闭")

        let missing = """
        {"settings":{"monthlySalary":"17850","schedule":{"workdays":[2,3,4,5,6],"workStartMinutes":600,"workEndMinutes":1230,"lunchStartMinutes":720,"lunchEndMinutes":840}}}
        """
        defaults.set(Data(missing.utf8), forKey: StateStore.storageKey)
        let legacy = StateStore.load(defaults: defaults)
        try expectEqual(legacy.settings.showMenuBarEarnings, true, "缺字段时默认显示")
        try expectDecimal(legacy.settings.monthlySalary, 17_850, "缺字段不丢掉月薪")
    }

    private func monthly(_ salary: Decimal) -> AppSettings {
        var settings = AppSettings.default
        settings.salaryMode = .monthly
        settings.monthlySalary = salary
        return settings
    }

    private func annual(_ salary: Decimal) -> AppSettings {
        var settings = AppSettings.default
        settings.salaryMode = .annual
        settings.annualSalary = salary
        settings.monthlySalary = 1
        return settings
    }

    private func snapshot(now: Date, settings: AppSettings) -> EarningsSnapshot {
        EarningsCalculator.snapshot(
            EarningsInput(now: now, calendar: calendar, settings: settings)
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
