import Foundation

/// 一天里的一段带薪时间，区间为左闭右开 `[start, end)`。
struct PaidWindow: Equatable {
    var start: Date
    var end: Date

    var duration: TimeInterval {
        end.timeIntervalSince(start)
    }
}

/// 本地排班。净带薪工时 = 上班窗口 − 与午休重叠的部分。
struct WorkSchedule: Codable, Equatable {
    /// `Calendar` 的 weekday：1 = 周日 … 7 = 周六。
    var workdays: Set<Int>
    var workStartMinutes: Int
    var workEndMinutes: Int
    var lunchStartMinutes: Int
    var lunchEndMinutes: Int

    static let `default` = WorkSchedule(
        workdays: [2, 3, 4, 5, 6],
        workStartMinutes: 10 * 60,
        workEndMinutes: 20 * 60 + 30,
        lunchStartMinutes: 12 * 60,
        lunchEndMinutes: 14 * 60
    )

    /// 展示顺序：周一到周日。
    static let displayWeekdays: [Int] = [2, 3, 4, 5, 6, 7, 1]

    static func shortSymbol(for weekday: Int) -> String {
        switch weekday {
        case 1: return "日"
        case 2: return "一"
        case 3: return "二"
        case 4: return "三"
        case 5: return "四"
        case 6: return "五"
        case 7: return "六"
        default: return "?"
        }
    }

    var netPaidMinutes: Int {
        guard workEndMinutes > workStartMinutes else { return 0 }
        let workLength = workEndMinutes - workStartMinutes
        guard lunchEndMinutes > lunchStartMinutes else { return workLength }
        let overlapStart = max(workStartMinutes, lunchStartMinutes)
        let overlapEnd = min(workEndMinutes, lunchEndMinutes)
        let overlap = max(0, overlapEnd - overlapStart)
        return max(0, workLength - overlap)
    }

    var netPaidSeconds: TimeInterval {
        TimeInterval(netPaidMinutes * 60)
    }

    func sanitized() -> WorkSchedule {
        var copy = self
        copy.workdays = Set(workdays.filter { (1...7).contains($0) })
        copy.workStartMinutes = Self.clampMinutes(workStartMinutes)
        copy.workEndMinutes = Self.clampMinutes(workEndMinutes)
        copy.lunchStartMinutes = Self.clampMinutes(lunchStartMinutes)
        copy.lunchEndMinutes = Self.clampMinutes(lunchEndMinutes)
        return copy
    }

    func isWorkday(_ date: Date, calendar: Calendar) -> Bool {
        let weekday = calendar.component(.weekday, from: date)
        return workdays.contains(weekday)
    }

    /// 某一天的带薪窗口。非工作日、倒挂的上下班时间、或午休盖住整个班次时返回空。
    func paidWindows(on day: Date, calendar: Calendar) -> [PaidWindow] {
        let dayStart = calendar.startOfDay(for: day)
        guard isWorkday(dayStart, calendar: calendar) else { return [] }
        guard workEndMinutes > workStartMinutes else { return [] }
        guard
            let workStart = calendar.date(byAdding: .minute, value: workStartMinutes, to: dayStart),
            let workEnd = calendar.date(byAdding: .minute, value: workEndMinutes, to: dayStart),
            workEnd > workStart
        else {
            return []
        }

        guard
            lunchEndMinutes > lunchStartMinutes,
            let lunchStart = calendar.date(byAdding: .minute, value: lunchStartMinutes, to: dayStart),
            let lunchEnd = calendar.date(byAdding: .minute, value: lunchEndMinutes, to: dayStart),
            lunchEnd > lunchStart
        else {
            return [PaidWindow(start: workStart, end: workEnd)]
        }

        var windows: [PaidWindow] = []
        let beforeEnd = min(workEnd, lunchStart)
        if beforeEnd > workStart {
            windows.append(PaidWindow(start: workStart, end: beforeEnd))
        }
        let afterStart = max(workStart, lunchEnd)
        if workEnd > afterStart {
            windows.append(PaidWindow(start: afterStart, end: workEnd))
        }
        return windows
    }

    static func clampMinutes(_ value: Int) -> Int {
        min(max(value, 0), 23 * 60 + 59)
    }

    static func date(minutes: Int, calendar: Calendar) -> Date {
        let clamped = clampMinutes(minutes)
        var components = DateComponents()
        components.calendar = calendar
        components.timeZone = calendar.timeZone
        components.year = 2026
        components.month = 1
        components.day = 5
        components.hour = clamped / 60
        components.minute = clamped % 60
        components.second = 0
        return calendar.date(from: components) ?? Date(timeIntervalSinceReferenceDate: 0)
    }

    static func minutes(from date: Date, calendar: Calendar) -> Int {
        let hour = calendar.component(.hour, from: date)
        let minute = calendar.component(.minute, from: date)
        return clampMinutes(hour * 60 + minute)
    }
}
