import Testing

@testable import SleeplessCore

struct StatusPresentationTests {
    @Test func idleShowsTheMonochromeMoon() {
        #expect(
            StatusPresentation.make(for: .idle)
                == StatusPresentation(
                    symbolName: "moon.zzz",
                    isTinted: false,
                    statusText: "No audio playing, Mac can sleep",
                    accessibilityLabel: "Sleepless: Mac can sleep"
                )
        )
    }

    @Test func playingShowsTheTintedNote() {
        #expect(
            StatusPresentation.make(for: .playing)
                == StatusPresentation(
                    symbolName: "music.note",
                    isTinted: true,
                    statusText: "Audio playing, keeping Mac awake",
                    accessibilityLabel: "Sleepless: keeping Mac awake"
                )
        )
    }

    @Test func holdingStillShowsTheTintedNote() {
        #expect(
            StatusPresentation.make(for: .holding)
                == StatusPresentation(
                    symbolName: "music.note",
                    isTinted: true,
                    statusText: "Audio stopped, keeping Mac awake for a moment",
                    accessibilityLabel: "Sleepless: keeping Mac awake"
                )
        )
    }

    @Test func failureShowsTheMoonAndTheErrorInHex() {
        #expect(
            StatusPresentation.make(for: .failed(code: Int32(bitPattern: 0xE000_02C2)))
                == StatusPresentation(
                    symbolName: "moon.zzz",
                    isTinted: false,
                    statusText: "Could not prevent sleep (error 0xE00002C2)",
                    accessibilityLabel: "Sleepless: Mac can sleep"
                )
        )
    }
}

struct BuildInfoTests {
    @Test func releaseTooltipShowsOnlyTheVersion() {
        #expect(BuildInfo(version: "0.1.0", channel: "release", commit: "abc1234").tooltip == "Sleepless 0.1.0")
    }

    @Test(arguments: ["dev", "rc", "local"])
    func otherChannelsShowChannelAndCommit(channel: String) {
        #expect(
            BuildInfo(version: "0.0.0", channel: channel, commit: "abc1234").tooltip
                == "Sleepless 0.0.0 (\(channel) abc1234)"
        )
    }

    @Test func unbundledTooltip() {
        #expect(BuildInfo(infoDictionary: nil).tooltip == "Sleepless (unbundled)")
    }

    @Test func readsInfoPlistKeys() {
        let info: [String: Any] = [
            "CFBundleShortVersionString": "0.2.0",
            "SleeplessBuildChannel": "rc",
            "SleeplessBuildCommit": "def5678",
        ]
        #expect(BuildInfo(infoDictionary: info) == BuildInfo(version: "0.2.0", channel: "rc", commit: "def5678"))
    }

    @Test func missingKeysFallBackToLocalAndUnknown() {
        let info: [String: Any] = ["CFBundleShortVersionString": "0.2.0"]
        #expect(BuildInfo(infoDictionary: info) == BuildInfo(version: "0.2.0", channel: "local", commit: "unknown"))
    }
}
