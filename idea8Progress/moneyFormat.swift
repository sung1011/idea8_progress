import Foundation

enum MoneyFormat {
    private static let panelFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        formatter.usesGroupingSeparator = true
        formatter.decimalSeparator = "."
        formatter.groupingSeparator = ","
        return formatter
    }()

    private static let menuFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        formatter.usesGroupingSeparator = false
        formatter.decimalSeparator = "."
        return formatter
    }()

    private static let hoursFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 2
        formatter.decimalSeparator = "."
        return formatter
    }()

    private static let clockFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    static func currency(_ value: Decimal) -> String {
        let number = panelFormatter.string(from: NSDecimalNumber(decimal: value)) ?? "0.00"
        return "¥\(number)"
    }

    static func menuBar(_ value: Decimal) -> String {
        let number = menuFormatter.string(from: NSDecimalNumber(decimal: value)) ?? "0.00"
        return "¥\(number)"
    }

    static func perHour(_ value: Decimal) -> String {
        "\(currency(value))/小时"
    }

    static func editable(_ value: Decimal) -> String {
        NSDecimalNumber(decimal: value).stringValue
    }

    static func hours(_ seconds: TimeInterval) -> String {
        let value = Decimal(max(0, seconds)) / Decimal(3600)
        return hoursFormatter.string(from: NSDecimalNumber(decimal: value)) ?? "0"
    }

    static func duration(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded(.down)))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60
        return String(format: "%d:%02d:%02d", hours, minutes, secs)
    }

    static func percent(_ progress: Double) -> String {
        let safe = progress.isFinite ? progress : 0
        return String(format: "%.1f%%", safe * 100)
    }

    static func clock(_ date: Date) -> String {
        clockFormatter.string(from: date)
    }

    /// 接受 `15000`、`15000.5`、`¥1,500`、中文逗号。空字符串视为 0；无法解析时返回 nil。
    static func parse(_ text: String) -> Decimal? {
        let cleaned = text
            .replacingOccurrences(of: "¥", with: "")
            .replacingOccurrences(of: "￥", with: "")
            .replacingOccurrences(of: ",", with: "")
            .replacingOccurrences(of: "，", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.isEmpty { return 0 }
        let posix = Locale(identifier: "en_US_POSIX")
        return Decimal(string: cleaned, locale: posix)
    }
}
