import Combine
import Foundation

/// 菜单栏面板的状态。计算器保持纯函数；这里只负责持久化和大约每秒刷新一次快照。
final class EarningsModel: ObservableObject {
    @Published private(set) var snapshot: EarningsSnapshot
    @Published private(set) var settings: AppSettings
    @Published private(set) var timer: TimerState

    let calendar: Calendar

    private let defaults: UserDefaults
    private var ticker: Timer?

    init(
        defaults: UserDefaults = .standard,
        calendar: Calendar = .current,
        now: Date = Date(),
        startTicker: Bool = true
    ) {
        self.defaults = defaults
        self.calendar = calendar
        let loaded = StateStore.load(defaults: defaults)
        settings = loaded.settings
        timer = loaded.timer
        snapshot = EarningsCalculator.snapshot(
            EarningsInput(now: now, calendar: calendar, settings: loaded.settings, timer: loaded.timer)
        )
        if startTicker {
            let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
                self?.tick()
            }
            RunLoop.main.add(timer, forMode: .common)
            ticker = timer
        }
    }

    deinit {
        ticker?.invalidate()
    }

    func tick(now: Date = Date()) {
        let today = calendar.startOfDay(for: now)
        let before = timer
        timer.prune(keepingFrom: today)
        publish(now: now)
        if timer != before {
            persist()
        }
    }

    func toggleTimer(now: Date = Date()) {
        if timer.isRunning {
            timer.stop(now: now)
        } else {
            timer.start(now: now)
        }
        publish(now: now)
        persist()
    }

    func setMonthlySalary(_ value: Decimal, now: Date = Date()) {
        settings.monthlySalary = value < 0 ? 0 : value
        commitSettings(now: now)
    }

    func setSchedule(_ schedule: WorkSchedule, now: Date = Date()) {
        settings.schedule = schedule.sanitized()
        commitSettings(now: now)
    }

    func toggleWeekday(_ weekday: Int, now: Date = Date()) {
        guard (1...7).contains(weekday) else { return }
        var schedule = settings.schedule
        if schedule.workdays.contains(weekday) {
            schedule.workdays.remove(weekday)
        } else {
            schedule.workdays.insert(weekday)
        }
        setSchedule(schedule, now: now)
    }

    private func commitSettings(now: Date) {
        settings = settings.sanitized()
        publish(now: now)
        persist()
    }

    private func publish(now: Date) {
        snapshot = EarningsCalculator.snapshot(
            EarningsInput(now: now, calendar: calendar, settings: settings, timer: timer)
        )
    }

    private func persist() {
        StateStore.save(PersistedState(settings: settings, timer: timer), defaults: defaults)
    }
}
