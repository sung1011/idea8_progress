import Foundation

/// 用户按下开始/停止之间的一段墙钟时间。`end == nil` 表示计时仍在进行。
struct TimerSegment: Codable, Equatable {
    var start: Date
    var end: Date?
}

/// 计时器状态。收入只来自这些区间与带薪窗口的交集；停止期间不会产生新区间。
struct TimerState: Codable, Equatable {
    var segments: [TimerSegment]

    var isRunning: Bool {
        segments.contains { $0.end == nil }
    }

    static func idle() -> TimerState {
        TimerState(segments: [])
    }

    mutating func start(now: Date) {
        guard !isRunning else { return }
        segments.append(TimerSegment(start: now, end: nil))
    }

    mutating func stop(now: Date) {
        guard let index = segments.lastIndex(where: { $0.end == nil }) else { return }
        if now <= segments[index].start {
            segments.remove(at: index)
            return
        }
        segments[index].end = now
    }

    /// 丢掉今天零点之前已经结束的区间。跨天仍在跑的区间保留，计算时只取今天的重叠部分。
    mutating func prune(keepingFrom dayStart: Date) {
        segments.removeAll { segment in
            guard let end = segment.end else { return false }
            return end <= dayStart
        }
    }

    func sanitized() -> TimerState {
        var closed: [TimerSegment] = []
        var openSegment: TimerSegment?
        for segment in segments {
            if segment.end == nil {
                openSegment = TimerSegment(start: segment.start, end: nil)
            } else if let end = segment.end, end > segment.start {
                closed.append(TimerSegment(start: segment.start, end: end))
            }
        }
        if let openSegment {
            closed.append(openSegment)
        }
        return TimerState(segments: closed)
    }
}
