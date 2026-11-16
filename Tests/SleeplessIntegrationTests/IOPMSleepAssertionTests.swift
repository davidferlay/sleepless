import Foundation
import Testing

@testable import SleeplessCore

@MainActor
@Suite(.serialized)
struct IOPMSleepAssertionTests {
    private func uniqueName() -> String {
        "Sleepless test \(UUID().uuidString)"
    }

    @Test func acquiredAssertionIsVisibleToPowerManagement() throws {
        let name = uniqueName()
        let assertion = IOPMSleepAssertion(name: name)
        try assertion.acquire()
        defer { assertion.release() }
        #expect(assertion.isHeld)
        let held = PowerAssertions.forCurrentProcess().filter { $0.name == name }
        #expect(held == [PowerAssertion(type: "PreventUserIdleSystemSleep", name: name)])
    }

    @Test func releaseRemovesTheAssertion() throws {
        let name = uniqueName()
        let assertion = IOPMSleepAssertion(name: name)
        try assertion.acquire()
        assertion.release()
        #expect(!assertion.isHeld)
        #expect(PowerAssertions.forCurrentProcess().filter { $0.name == name }.isEmpty)
    }

    @Test func acquiringTwiceHoldsOneAssertion() throws {
        let name = uniqueName()
        let assertion = IOPMSleepAssertion(name: name)
        try assertion.acquire()
        try assertion.acquire()
        defer { assertion.release() }
        #expect(PowerAssertions.forCurrentProcess().filter { $0.name == name }.count == 1)
    }

    @Test func releasingWithoutAcquiringIsHarmless() {
        let assertion = IOPMSleepAssertion(name: uniqueName())
        assertion.release()
        assertion.release()
        #expect(!assertion.isHeld)
    }

    @Test func defaultNameIsTheOneTheEndToEndTestLooksFor() {
        #expect(IOPMSleepAssertion().name == "Sleepless: audio playback")
    }
}
