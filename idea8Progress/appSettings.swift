import Foundation

/// 会写入 UserDefaults 的用户设置。金额用十进制字符串保存，避免浮点误差。
struct AppSettings: Equatable {
    var payMode: PayMode
    var monthlySalary: Decimal
    var hourlyRate: Decimal
    var schedule: WorkSchedule

    static let `default` = AppSettings(
        payMode: .monthly,
        monthlySalary: 15_000,
        hourlyRate: 100,
        schedule: .default
    )

    func sanitized() -> AppSettings {
        var copy = self
        if copy.monthlySalary < 0 { copy.monthlySalary = 0 }
        if copy.hourlyRate < 0 { copy.hourlyRate = 0 }
        copy.schedule = schedule.sanitized()
        return copy
    }
}

extension AppSettings: Codable {
    private enum CodingKeys: String, CodingKey {
        case payMode
        case monthlySalary
        case hourlyRate
        case schedule
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        payMode = try container.decodeIfPresent(PayMode.self, forKey: .payMode) ?? .monthly
        monthlySalary = Self.decodeDecimal(container, key: .monthlySalary)
        hourlyRate = Self.decodeDecimal(container, key: .hourlyRate)
        schedule = try container.decodeIfPresent(WorkSchedule.self, forKey: .schedule) ?? .default
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(payMode, forKey: .payMode)
        try container.encode(Self.encodeDecimal(monthlySalary), forKey: .monthlySalary)
        try container.encode(Self.encodeDecimal(hourlyRate), forKey: .hourlyRate)
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
