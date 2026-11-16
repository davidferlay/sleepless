import Foundation
import IOKit.pwr_mgt

/// IOKit error returned when a power assertion cannot be created.
public struct SleepAssertionError: Error, Equatable, Sendable {
    public let code: Int32

    public init(code: Int32) {
        self.code = code
    }
}

/// Prevents idle system sleep while held.
@MainActor
public protocol SleepAssertion: AnyObject {
    var isHeld: Bool { get }
    func acquire() throws
    func release()
}

/// A `PreventUserIdleSystemSleep` power assertion: the Mac stays awake, the display can still sleep.
/// macOS releases it automatically if the process exits or crashes.
@MainActor
public final class IOPMSleepAssertion: SleepAssertion {
    public nonisolated static let defaultName = "Sleepless: audio playback"

    public let name: String
    private var assertionID: IOPMAssertionID?

    public var isHeld: Bool { assertionID != nil }

    public init(name: String = IOPMSleepAssertion.defaultName) {
        self.name = name
    }

    public func acquire() throws {
        guard assertionID == nil else { return }
        var newID = IOPMAssertionID(0)
        let result = IOPMAssertionCreateWithName(
            kIOPMAssertionTypePreventUserIdleSystemSleep as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            name as CFString,
            &newID
        )
        guard result == kIOReturnSuccess else {
            throw SleepAssertionError(code: result)
        }
        assertionID = newID
    }

    public func release() {
        guard let assertionID else { return }
        IOPMAssertionRelease(assertionID)
        self.assertionID = nil
    }
}
