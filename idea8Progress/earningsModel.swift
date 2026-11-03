import Combine
import Foundation

/// 菜单栏面板的状态。计算器保持纯函数；这里只负责持久化和大约每秒刷新一次快照。
final class EarningsModel: ObservableObject {
    @Published private(set) var snapshot: EarningsSnapshot
    @Published private(set) var settings: AppSettings

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
        snapshot = EarningsCalculator.snapshot(
            EarningsInput(now: now, calendar: calendar, settings: loaded.settings)
        )
        if startTicker {
            let refresh = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
                self?.tick()
            }
            RunLoop.main.add(refresh, forMode: .common)
            ticker = refresh
        }
    }

    deinit {
        ticker?.invalidate()
    }

    func tick(now: Date = Date()) {
        publish(now: now)
    }

    func setSalaryMode(_ mode: SalaryMode, now: Date = Date()) {
        settings.salaryMode = mode
        commitSettings(now: now)
    }

    func setMonthlySalary(_ value: Decimal, now: Date = Date()) {
        settings.monthlySalary = value < 0 ? 0 : value
        commitSettings(now: now)
    }

    func setAnnualSalary(_ value: Decimal, now: Date = Date()) {
        settings.annualSalary = value < 0 ? 0 : value
        commitSettings(now: now)
    }

    func setSchedule(_ schedule: WorkSchedule, now: Date = Date()) {
        settings.schedule = schedule.sanitized()
        commitSettings(now: now)
    }

    func setRetirementDate(_ date: RetirementDate?, now: Date = Date()) {
        settings.retirementDate = date?.validated()
        commitSettings(now: now)
    }

    func setShowMenuBarEarnings(_ visible: Bool, now: Date = Date()) {
        settings.showMenuBarEarnings = visible
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
            EarningsInput(now: now, calendar: calendar, settings: settings)
        )
    }

    private func persist() {
        StateStore.save(PersistedState(settings: settings), defaults: defaults)
    }
}
