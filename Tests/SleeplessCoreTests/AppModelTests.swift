import Testing

@testable import SleeplessCore

@MainActor
private final class Harness {
    let detector: FakeDetector
    let assertion: FakeAssertion
    let scheduler: ManualScheduler
    let model: AppModel
    var statuses: [AppStatus] = []

    init() {
        detector = FakeDetector()
        assertion = FakeAssertion()
        scheduler = ManualScheduler()
        model = AppModel(
            detector: detector,
            controller: ActivationController(settings: Settings(), scheduler: scheduler),
            assertion: assertion
        )
        model.onStatusChange = { [unowned self] in self.statuses.append($0) }
    }
}

@MainActor
struct AppModelTests {
    private let notPermitted = Int32(bitPattern: 0xE000_02E2)

    @Test func startsIdleAndStartsTheDetector() {
        let harness = Harness()
        harness.model.start()
        #expect(harness.detector.startCount == 1)
        #expect(harness.model.status == .idle)
        #expect(!harness.assertion.isHeld)
    }

    @Test func preventsSleepOnlyAfterTheStartDelay() {
        let harness = Harness()
        harness.model.start()
        harness.detector.simulate(playing: true)
        harness.scheduler.advance(by: 2.5)
        #expect(harness.model.status == .idle)
        #expect(!harness.assertion.isHeld)
        harness.scheduler.advance(by: 0.5)
        #expect(harness.model.status == .playing)
        #expect(harness.assertion.isHeld)
        #expect(harness.assertion.acquireAttempts == 1)
    }

    @Test func detectsPlaybackAlreadyRunningAtLaunch() {
        let harness = Harness()
        harness.detector.isPlaying = true
        harness.model.start()
        harness.scheduler.advance(by: 3)
        #expect(harness.model.status == .playing)
    }

    @Test func keepsOneAssertionAcrossTrackGaps() {
        let harness = Harness()
        harness.model.start()
        harness.detector.simulate(playing: true)
        harness.scheduler.advance(by: 3)
        harness.detector.simulate(playing: false)
        harness.scheduler.advance(by: 10)
        harness.detector.simulate(playing: true)
        harness.scheduler.advance(by: 3)
        #expect(harness.model.status == .playing)
        #expect(harness.assertion.acquireAttempts == 1)
        #expect(harness.assertion.releaseCount == 0)
        #expect(harness.statuses == [.playing, .holding, .playing])
    }

    @Test func releasesAfterTheHold() {
        let harness = Harness()
        harness.model.start()
        harness.detector.simulate(playing: true)
        harness.scheduler.advance(by: 3)
        harness.detector.simulate(playing: false)
        #expect(harness.model.status == .holding)
        #expect(harness.assertion.isHeld)
        harness.scheduler.advance(by: 30)
        #expect(harness.model.status == .idle)
        #expect(!harness.assertion.isHeld)
        #expect(harness.assertion.releaseCount == 1)
        #expect(harness.statuses == [.playing, .holding, .idle])
    }

    @Test func reportsAnAssertionFailure() {
        let harness = Harness()
        harness.assertion.failureCode = notPermitted
        harness.model.start()
        harness.detector.simulate(playing: true)
        harness.scheduler.advance(by: 3)
        #expect(harness.model.status == .failed(code: notPermitted))
        #expect(!harness.assertion.isHeld)
    }

    @Test func recoversOnTheNextActivationAfterAFailure() {
        let harness = Harness()
        harness.assertion.failureCode = notPermitted
        harness.model.start()
        harness.detector.simulate(playing: true)
        harness.scheduler.advance(by: 3)
        harness.detector.simulate(playing: false)
        harness.scheduler.advance(by: 30)
        #expect(harness.model.status == .idle)
        harness.assertion.failureCode = nil
        harness.detector.simulate(playing: true)
        harness.scheduler.advance(by: 3)
        #expect(harness.model.status == .playing)
        #expect(harness.assertion.isHeld)
    }

    @Test func stopReleasesTheAssertionAndStopsTheDetector() {
        let harness = Harness()
        harness.model.start()
        harness.detector.simulate(playing: true)
        harness.scheduler.advance(by: 3)
        harness.model.stop()
        #expect(!harness.assertion.isHeld)
        #expect(harness.assertion.releaseCount == 1)
        #expect(harness.model.status == .idle)
        #expect(harness.detector.stopCount == 1)
        harness.detector.simulate(playing: true)
        harness.scheduler.advance(by: 10)
        #expect(harness.model.status == .idle)
    }

    @Test func refreshAsksTheDetectorToRereadTheState() {
        let harness = Harness()
        harness.model.refresh()
        #expect(harness.detector.refreshCount == 1)
    }
}
