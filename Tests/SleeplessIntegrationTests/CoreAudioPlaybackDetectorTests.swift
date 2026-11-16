import CoreAudio
import Testing

@testable import SleeplessCore

@MainActor
@Suite(.enabled(if: CoreAudioPlaybackDetector.defaultOutputDevice() != nil, "needs a default audio output device"))
struct CoreAudioPlaybackDetectorTests {
    @Test func startRegistersListenersAndStopRemovesThem() {
        let detector = CoreAudioPlaybackDetector()
        detector.start()
        #expect(detector.isWatching)
        detector.stop()
        #expect(!detector.isWatching)
    }

    @Test func startingTwiceIsHarmless() {
        let detector = CoreAudioPlaybackDetector()
        detector.start()
        detector.start()
        #expect(detector.isWatching)
        detector.stop()
        #expect(!detector.isWatching)
    }

    @Test func reportsTheStateCoreAudioReports() throws {
        let detector = CoreAudioPlaybackDetector()
        detector.start()
        defer { detector.stop() }
        let device = try #require(CoreAudioPlaybackDetector.defaultOutputDevice())
        #expect(detector.isPlaying == CoreAudioPlaybackDetector.isRunningSomewhere(device))
    }
}

struct CoreAudioQueryTests {
    @Test func unknownDeviceIsNotRunning() {
        #expect(!CoreAudioPlaybackDetector.isRunningSomewhere(AudioObjectID(kAudioObjectUnknown)))
    }
}
