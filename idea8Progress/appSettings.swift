import Foundation

/// 会写入 UserDefaults 的用户设置。金额用十进制字符串保存，避免浮点误差。
/// 时薪不单独保存，一律由月薪、本月工作日和每日净工时折算。
struct AppSettings: Equatable {
    var monthlySalary: Decimal
    var schedule: WorkSchedule

    static let `default` = AppSettings(
        monthlySalary: 15_000,
        schedule: .default
    )

    func sanitized() -> AppSettings {
        var copy = self
        if copy.monthlySalary < 0 { copy.monthlySalary = 0 }
        copy.schedule = schedule.sanitized()
        return copy
    }
}

extension AppSettings: Codable {
    private enum CodingKeys: String, CodingKey {
        case monthlySalary
        case schedule
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        monthlySalary = Self.decodeDecimal(container, key: .monthlySalary)
        schedule = try container.decodeIfPresent(WorkSchedule.self, forKey: .schedule) ?? .default
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(Self.encodeDecimal(monthlySalary), forKey: .monthlySalary)
        try container.encode(schedule, forKey: .schedule)
    }

    private static func decodeDecimal(
        _ container: KeyedDecodingContainer<CodingKeys>,
        key: CodingKeys
    ) -> Decimal {
        if let text = try? container.decode(String.self, forKey: key),
           let value = Decimal(string: text, locale: Locale(identifier: "en_US_POSIX")) {
            return value
        }
        if let number = try? container.decode(Double.self, forKey: key), number.isFinite {
            return Decimal(number)
        }
        return 0
    }

    private static func encodeDecimal(_ value: Decimal) -> String {
        NSDecimalNumber(decimal: value).stringValue
    }
}
