import Foundation

struct PersistedState: Codable, Equatable {
    var settings: AppSettings

    func sanitized() -> PersistedState {
        PersistedState(settings: settings.sanitized())
    }
}

/// 月薪和排班放在标准 UserDefaults 里，不访问网络。旧存档里的计时区间不再读取。
enum StateStore {
    static let storageKey = "com.sung1011.idea8progress.state.v1"

    static func load(defaults: UserDefaults = .standard) -> PersistedState {
        guard let data = defaults.data(forKey: storageKey) else {
            return PersistedState(settings: .default)
        }
        do {
            let state = try JSONDecoder().decode(PersistedState.self, from: data).sanitized()
            if Self.containsTimer(data) {
                save(state, defaults: defaults)
            }
            return state
        } catch {
            return PersistedState(settings: .default)
        }
    }

    static func save(_ state: PersistedState, defaults: UserDefaults = .standard) {
        let clean = state.sanitized()
        guard let data = try? JSONEncoder().encode(clean) else { return }
        defaults.set(data, forKey: storageKey)
    }

    /// 旧版本把计时区间写在同一个键里。读到就丢掉，只把月薪和排班写回去。
    private static func containsTimer(_ data: Data) -> Bool {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return false
        }
        return object["timer"] != nil
    }
}
