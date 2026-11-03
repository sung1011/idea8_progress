import Foundation

struct PersistedState: Codable, Equatable {
    var settings: AppSettings
    var timer: TimerState

    func sanitized() -> PersistedState {
        PersistedState(settings: settings.sanitized(), timer: timer.sanitized())
    }
}

/// 设置和计时区间都放在标准 UserDefaults 里，不访问网络。
enum StateStore {
    static let storageKey = "com.sung1011.idea8progress.state.v1"

    static func load(defaults: UserDefaults = .standard) -> PersistedState {
        guard let data = defaults.data(forKey: storageKey) else {
            return PersistedState(settings: .default, timer: .idle())
        }
        do {
            return try JSONDecoder().decode(PersistedState.self, from: data).sanitized()
        } catch {
            return PersistedState(settings: .default, timer: .idle())
        }
    }

    static func save(_ state: PersistedState, defaults: UserDefaults = .standard) {
        let clean = state.sanitized()
        guard let data = try? JSONEncoder().encode(clean) else { return }
        defaults.set(data, forKey: storageKey)
    }
}
