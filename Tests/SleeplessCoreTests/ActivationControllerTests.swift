import Foundation
import Testing

@testable import SleeplessCore

@MainActor
private final class PhaseRecorder {
    var phases: [ActivationPhase] = []
}

@MainActor
private func makeController(
    startDelay: TimeInterval = 3,
    stopDelay: TimeInterval = 30
) -> (ActivationController, ManualScheduler, PhaseRecorder) {
    let scheduler = ManualScheduler()
    let controller = ActivationController(
        settings: Settings(startDelay: startDelay, stopDelay: stopDelay),
        scheduler: scheduler
    )
    let recorder = PhaseRecorder()
    controller.onPhaseChange = { recorder.phases.append($0) }
    return (controller, scheduler, recorder)
}

@MainActor
struct ActivationControllerTests {
    @Test func startsIdle() {
        let (controller, _, recorder) = makeController()
        #expect(controller.phase == .idle)
        #expect(recorder.phases.isEmpty)
    }

    @Test func shortSoundDoesNotActivate() {
        let (controller, scheduler, recorder) = makeController()
        controller.playbackChanged(true)
        scheduler.advance(by: 2.5)
        controller.playbackChanged(false)
        scheduler.advance(by: 60)
        #expect(controller.phase == .idle)
        #expect(recorder.phases == [.pendingStart, .idle])
        #expect(scheduler.pendingCount == 0)
    }

    @Test func activatesAfterStartDelay() {
        let (controller, scheduler, recorder) = makeController()
        controller.playbackChanged(true)
        scheduler.advance(by: 2.5)
        #expect(controller.phase == .pendingStart)
        scheduler.advance(by: 0.5)
        #expect(controller.phase == .active)
        #expect(recorder.phases == [.pendingStart, .active])
    }

    @Test func holdsForStopDelayAfterPlaybackStops() {
        let (controller, scheduler, recorder) = makeController()
        controller.playbackChanged(true)
        scheduler.advance(by: 3)
        controller.playbackChanged(false)
        #expect(controller.phase == .holding)
        scheduler.advance(by: 29.5)
        #expect(controller.phase == .holding)
        scheduler.advance(by: 0.5)
        #expect(controller.phase == .idle)
        #expect(recorder.phases == [.pendingStart, .active, .holding, .idle])
    }

    @Test func resumingDuringHoldKeepsOneActivation() {
        let (controller, scheduler, recorder) = makeController()
        controller.playbackChanged(true)
        scheduler.advance(by: 3)
        controller.playbackChanged(false)
        scheduler.advance(by: 10)
        controller.playbackChanged(true)
        #expect(controller.phase == .active)
        scheduler.advance(by: 120)
        #expect(controller.phase == .active)
        #expect(recorder.phases == [.pendingStart, .active, .holding, .active])
        #expect(scheduler.pendingCount == 0)
    }

    @Test func flappingRestartsTheStartDelay() {
        let (controller, scheduler, recorder) = makeController()
        controller.playbackChanged(true)
        scheduler.advance(by: 1)
        controller.playbackChanged(false)
        scheduler.advance(by: 0.5)
        controller.playbackChanged(true)
        scheduler.advance(by: 2.5)
        #expect(controller.phase == .pendingStart)
        scheduler.advance(by: 0.5)
        #expect(controller.phase == .active)
        #expect(recorder.phases == [.pendingStart, .idle, .pendingStart, .active])
    }

    @Test func repeatedReportsAreIgnored() {
        let (controller, scheduler, recorder) = makeController()
        controller.playbackChanged(true)
        controller.playbackChanged(true)
        #expect(scheduler.pendingCount == 1)
        scheduler.advance(by: 3)
        controller.playbackChanged(true)
        controller.playbackChanged(false)
        controller.playbackChanged(false)
        #expect(scheduler.pendingCount == 1)
        #expect(recorder.phases == [.pendingStart, .active, .holding])
    }

    @Test func resetCancelsThePendingDelayAndGoesIdle() {
        let (controller, scheduler, recorder) = makeController()
        controller.playbackChanged(true)
        scheduler.advance(by: 3)
        controller.playbackChanged(false)
        controller.reset()
        #expect(controller.phase == .idle)
        #expect(scheduler.pendingCount == 0)
        scheduler.advance(by: 60)
        #expect(recorder.phases == [.pendingStart, .active, .holding, .idle])
    }

    @Test func usesConfiguredDelays() {
        let (controller, scheduler, _) = makeController(startDelay: 1, stopDelay: 4)
        controller.playbackChanged(true)
        scheduler.advance(by: 1)
        #expect(controller.phase == .active)
        controller.playbackChanged(false)
        scheduler.advance(by: 4)
        #expect(controller.phase == .idle)
    }
}
