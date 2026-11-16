import Testing

@testable import SleeplessCore

@MainActor
private final class Flag {
    var isSet = false
}

@MainActor
struct DispatchSchedulerTests {
    @Test func runsTheActionAfterTheDelay() async throws {
        let flag = Flag()
        _ = DispatchScheduler().schedule(after: 0.05) { flag.isSet = true }
        #expect(!flag.isSet)
        try await Task.sleep(for: .milliseconds(500))
        #expect(flag.isSet)
    }

    @Test func cancelledActionNeverRuns() async throws {
        let flag = Flag()
        let item = DispatchScheduler().schedule(after: 0.05) { flag.isSet = true }
        item.cancel()
        try await Task.sleep(for: .milliseconds(500))
        #expect(!flag.isSet)
    }
}
