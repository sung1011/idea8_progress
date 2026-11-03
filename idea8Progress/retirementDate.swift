import Foundation

/// 用户选择的退休日。只存公历年月日，默认不填。
struct RetirementDate: Codable, Equatable {
    var year: Int
    var month: Int
    var day: Int

    static let minimumYear = 1950
    static let maximumYear = 2100

    /// 还没选退休日时，主面板用这句话把人带到设置。
    static let unsetPrompt = "还没有退休日期。请在设置的「退休」里选择年、月、日。"

    /// 主面板上的一句倒计时。同一天是 0。退休日在过去时改成「退休日已过」。
    static func panelSentence(days: Int) -> String {
        if days >= 0 {
            return "距离退休还有 \(days) 天"
        }
        return "退休日已过 \(-days) 天"
    }

    var displayText: String {
        "\(year)年\(month)月\(day)日"
    }

    /// 不是真实公历日期时返回 nil，例如平年 2 月 29 日。
    func validated() -> RetirementDate? {
        guard (1...9999).contains(year), (1...12).contains(month), (1...31).contains(day) else {
            return nil
        }
        let calendar = Self.validationCalendar
        var components = DateComponents()
        components.calendar = calendar
        components.timeZone = calendar.timeZone
        components.year = year
        components.month = month
        components.day = day
        guard let date = calendar.date(from: components) else { return nil }
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        guard parts.year == year, parts.month == month, parts.day == day else { return nil }
        return RetirementDate(year: year, month: month, day: day)
    }

    /// 该年该月有多少天。用来限制「日」的选项。
    static func dayCount(year: Int, month: Int) -> Int? {
        guard (1...9999).contains(year), (1...12).contains(month) else { return nil }
        let calendar = validationCalendar
        var components = DateComponents()
        components.calendar = calendar
        components.timeZone = calendar.timeZone
        components.year = year
        components.month = month
        components.day = 1
        guard
            let date = calendar.date(from: components),
            let range = calendar.range(of: .day, in: .month, for: date)
        else {
            return nil
        }
        return range.count
    }

    /// 从 `now` 所在自然日到退休日的日历天数。同一天为 0，退休日在过去为负数。
    /// 按日期相减，不按工作日，也不按 24 小时整段。
    static func calendarDays(from now: Date, until retirement: RetirementDate?, calendar: Calendar) -> Int? {
        guard let valid = retirement?.validated() else { return nil }
        var parts = DateComponents()
        parts.calendar = calendar
        parts.timeZone = calendar.timeZone
        parts.year = valid.year
        parts.month = valid.month
        parts.day = valid.day
        parts.hour = 12
        guard let target = calendar.date(from: parts) else { return nil }
        let today = calendar.startOfDay(for: now)
        let retirementDay = calendar.startOfDay(for: target)
        return calendar.dateComponents([.day], from: today, to: retirementDay).day
    }

    private static let validationCalendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        calendar.locale = Locale(identifier: "en_US_POSIX")
        return calendar
    }()
}
