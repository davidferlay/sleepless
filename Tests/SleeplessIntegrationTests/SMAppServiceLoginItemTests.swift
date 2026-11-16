import Testing

@testable import SleeplessCore

@MainActor
struct SMAppServiceLoginItemTests {
    @Test func unbundledProcessReportsUnavailable() {
        #expect(SMAppServiceLoginItem(isBundled: false).status == .unavailable)
    }

    @Test func readingTheRealStatusHasNoSideEffect() {
        let item = SMAppServiceLoginItem(isBundled: true)
        let first = item.status
        let second = item.status
        #expect(first == second)
    }
}
