import Foundation

/// Timing settings. They are read from user defaults so tests can override them with launch
/// arguments (`-startDelay 1 -stopDelay 3`); there is no UI for them.
public struct Settings: Equatable, Sendable {
    public static let defaultStartDelay: TimeInterval = 3
    public static let defaultStopDelay: TimeInterval = 30
    public static let startDelayKey = "startDelay"
    public static let stopDelayKey = "stopDelay"

    /// Seconds of continuous playback before sleep is prevented.
    public let startDelay: TimeInterval
    /// Seconds sleep stays prevented after playback stops.
    public let stopDelay: TimeInterval

    public init(
        startDelay: TimeInterval = Settings.defaultStartDelay,
        stopDelay: TimeInterval = Settings.defaultStopDelay
    ) {
        self.startDelay = startDelay
        self.stopDelay = stopDelay
    }

    /// Reads both delays through `lookup`. Missing, non-numeric, non-finite, zero or negative
    /// values fall back to the defaults.
    public init(lookup: (String) -> Any?) {
        self.init(
            startDelay: Settings.positiveSeconds(lookup(Settings.startDelayKey)) ?? Settings.defaultStartDelay,
            stopDelay: Settings.positiveSeconds(lookup(Settings.stopDelayKey)) ?? Settings.defaultStopDelay
        )
    }

    public init(defaults: UserDefaults) {
        self.init(lookup: { defaults.object(forKey: $0) })
    }

    static func positiveSeconds(_ value: Any?) -> TimeInterval? {
        guard let value else { return nil }
        let seconds: Double?
        switch value {
        case let number as NSNumber:
            seconds = number.doubleValue
        case let text as String:
            seconds = Double(text)
        default:
            seconds = nil
        }
        guard let seconds, seconds.isFinite, seconds > 0 else { return nil }
        return seconds
    }
}
