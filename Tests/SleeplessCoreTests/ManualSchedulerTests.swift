import Testing

@testable import SleeplessCore

@MainActor
private final class CallLog {
    var calls: [String] = []
}

@MainActor
struct ManualSchedulerTests {
    @Test func runsActionsOnlyWhenTheirTimeComes() {
        let scheduler = ManualScheduler()
        let log = CallLog()
        _ = scheduler.schedule(after: 2) { log.calls.append("a") }
        scheduler.advance(by: 1.5)
        #expect(log.calls.isEmpty)
        scheduler.advance(by: 0.5)
        #expect(log.calls == ["a"])
        #expect(scheduler.pendingCount == 0)
    }

    @Test func runsActionsInTimeOrder() {
        let scheduler = ManualScheduler()
        let log = CallLog()
        _ = scheduler.schedule(after: 3) { log.calls.append("late") }
        _ = scheduler.schedule(after: 1) { log.calls.append("early") }
        scheduler.advance(by: 5)
        #expect(log.calls == ["early", "late"])
    }

    @Test func cancelledActionsNeverRun() {
        let scheduler = ManualScheduler()
        let log = CallLog()
        let item = scheduler.schedule(after: 1) { log.calls.append("a") }
        item.cancel()
        scheduler.advance(by: 5)
        #expect(log.calls.isEmpty)
        #expect(scheduler.pendingCount == 0)
    }

    @Test func runsActionsScheduledByActionsWhenDue() {
        let scheduler = ManualScheduler()
        let log = CallLog()
        _ = scheduler.schedule(after: 1) {
            log.calls.append("first")
            _ = scheduler.schedule(after: 1) { log.calls.append("second") }
        }
        scheduler.advance(by: 1.5)
        #expect(log.calls == ["first"])
        scheduler.advance(by: 0.5)
        #expect(log.calls == ["first", "second"])
    }
}
