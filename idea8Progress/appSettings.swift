import Foundation

/// 会写入 UserDefaults 的用户设置。金额用十进制字符串保存，避免浮点误差。
/// 时薪不单独保存，一律由月薪、本月工作日和每日净工时折算。
/// 退休日默认为空，只有用户在设置里选定年月日之后才写入。
struct AppSettings: Equatable {
    var monthlySalary: Decimal
    var schedule: WorkSchedule
    var retirementDate: RetirementDate?

    static let `default` = AppSettings(
        monthlySalary: 15_000,
        schedule: .default,
        retirementDate: nil
    )

    func sanitized() -> AppSettings {
        var copy = self
        if copy.monthlySalary < 0 { copy.monthlySalary = 0 }
        copy.schedule = schedule.sanitized()
        copy.retirementDate = retirementDate?.validated()
        return copy
    }
}

extension AppSettings: Codable {
    private enum CodingKeys: String, CodingKey {
        case monthlySalary
        case schedule
        case retirementDate
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        monthlySalary = Self.decodeDecimal(container, key: .monthlySalary)
        schedule = try container.decodeIfPresent(WorkSchedule.self, forKey: .schedule) ?? .default
        retirementDate = Self.decodeRetirementDate(container)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(Self.encodeDecimal(monthlySalary), forKey: .monthlySalary)
        try container.encode(schedule, forKey: .schedule)
        try container.encodeIfPresent(retirementDate, forKey: .retirementDate)
    }

    /// 缺字段、null 或类型不对都当成还没设置，避免坏字段把月薪和排班一起丢掉。
    private static func decodeRetirementDate(_ container: KeyedDecodingContainer<CodingKeys>) -> RetirementDate? {
        guard container.contains(.retirementDate) else { return nil }
        return (try? container.decode(RetirementDate.self, forKey: .retirementDate))?.validated()
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
