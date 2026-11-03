import Foundation

/// 设置里薪资金额按月填写还是按年填写。计算周期始终是自然月。
enum SalaryMode: String, Codable, Equatable {
    case monthly
    case annual
}

/// 会写入 UserDefaults 的用户设置。金额用十进制字符串保存，避免浮点误差。
/// 时薪不单独保存。年薪先折成有效月薪，再按本月工作日和每日净工时折算。
/// 退休日默认为空，只有用户在设置里选定年月日之后才写入。
struct AppSettings: Equatable {
    var salaryMode: SalaryMode
    var monthlySalary: Decimal
    var annualSalary: Decimal
    var schedule: WorkSchedule
    var retirementDate: RetirementDate?

    static let `default` = AppSettings(
        salaryMode: .monthly,
        monthlySalary: 15_000,
        annualSalary: 180_000,
        schedule: .default,
        retirementDate: nil
    )

    /// 进入月度计算的金额。年薪模式为年薪 ÷ 12，月薪模式为填写的月薪。
    var effectiveMonthlySalary: Decimal {
        switch salaryMode {
        case .monthly:
            return monthlySalary
        case .annual:
            return annualSalary / 12
        }
    }

    func sanitized() -> AppSettings {
        var copy = self
        if copy.monthlySalary < 0 { copy.monthlySalary = 0 }
        if copy.annualSalary < 0 { copy.annualSalary = 0 }
        copy.schedule = schedule.sanitized()
        copy.retirementDate = retirementDate?.validated()
        return copy
    }
}

extension AppSettings: Codable {
    private enum CodingKeys: String, CodingKey {
        case salaryMode
        case monthlySalary
        case annualSalary
        case schedule
        case retirementDate
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        monthlySalary = Self.decodeDecimal(container, key: .monthlySalary)
        if container.contains(.annualSalary) {
            annualSalary = Self.decodeDecimal(container, key: .annualSalary)
        } else {
            annualSalary = monthlySalary * 12
        }
        if let raw = try? container.decode(String.self, forKey: .salaryMode),
           let mode = SalaryMode(rawValue: raw) {
            salaryMode = mode
        } else {
            salaryMode = .monthly
        }
        schedule = try container.decodeIfPresent(WorkSchedule.self, forKey: .schedule) ?? .default
        retirementDate = Self.decodeRetirementDate(container)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(salaryMode.rawValue, forKey: .salaryMode)
        try container.encode(Self.encodeDecimal(monthlySalary), forKey: .monthlySalary)
        try container.encode(Self.encodeDecimal(annualSalary), forKey: .annualSalary)
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
