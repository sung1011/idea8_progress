import Foundation

/// 计薪方式。月薪按当月工作日均摊成时薪；时薪直接使用用户填写的小时单价。
enum PayMode: String, Codable, CaseIterable, Identifiable {
    case monthly
    case hourly

    var id: String { rawValue }

    var title: String {
        switch self {
        case .monthly:
            return "月薪"
        case .hourly:
            return "时薪"
        }
    }
}
