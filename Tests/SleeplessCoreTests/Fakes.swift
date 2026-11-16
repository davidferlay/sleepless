import Foundation

@testable import SleeplessCore

/// Scheduler whose clock only moves when a test calls `advance(by:)`.
@MainActor
final class ManualScheduler: Scheduling {
    private struct Entry {
        let order: Int
        let due: TimeInterval
        let item: ManualScheduledItem
    }

    private(set) var now: TimeInterval = 0
    private var entries: [Entry] = []
    private var nextOrder = 0

    /// Scheduled actions that have neither run nor been cancelled.
    var pendingCount: Int {
        entries.filter { !$0.item.isFinished }.count
    }

    func schedule(after delay: TimeInterval, _ action: @escaping @MainActor () -> Void) -> any ScheduledItem {
        let item = ManualScheduledItem(action: action)
        entries.append(Entry(order: nextOrder, due: now + delay, item: item))
        nextOrder += 1
        return item
    }

    /// Moves the clock forward and runs due actions in time order, including actions they schedule.
    func advance(by interval: TimeInterval) {
        let target = now + interval
        while let next = entries.filter({ $0.due <= target }).min(by: { ($0.due, $0.order) < ($1.due, $1.order) }) {
            entries.removeAll { $0.order == next.order }
            now = next.due
            next.item.runIfPending()
        }
        now = target
    }
}

@MainActor
final class ManualScheduledItem: ScheduledItem {
    private let action: @MainActor () -> Void
    private(set) var isFinished = false

    init(action: @escaping @MainActor () -> Void) {
        self.action = action
    }

    func cancel() {
        isFinished = true
    }

    func runIfPending() {
        guard !isFinished else { return }
        isFinished = true
        action()
    }
}

/// Playback detector driven by the test.
@MainActor
final class FakeDetector: PlaybackDetecting {
    var isPlaying = false
    var onChange: (@MainActor (Bool) -> Void)?
    private(set) var startCount = 0
    private(set) var stopCount = 0
    private(set) var refreshCount = 0

    func start() {
        startCount += 1
    }

    func stop() {
        stopCount += 1
    }

    func refresh() {
        refreshCount += 1
    }

    /// Simulates CoreAudio reporting a change.
    func simulate(playing: Bool) {
        isPlaying = playing
        onChange?(playing)
    }
}

/// Power assertion that records calls and can be told to fail.
@MainActor
final class FakeAssertion: SleepAssertion {
    private(set) var isHeld = false
    private(set) var acquireAttempts = 0
    private(set) var releaseCount = 0
    /// When set, `acquire()` throws this IOKit error code.
    var failureCode: Int32?

    func acquire() throws {
        acquireAttempts += 1
        if let failureCode {
            throw SleepAssertionError(code: failureCode)
        }
        isHeld = true
    }

    func release() {
        releaseCount += 1
        isHeld = false
    }
}
