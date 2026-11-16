import Foundation

/// Menu bar icon and status line for an `AppStatus`.
public struct StatusPresentation: Equatable, Sendable {
    public static let idleSymbol = "moon.zzz"
    public static let activeSymbol = "music.note"

    public let symbolName: String
    /// Draw the symbol in the accent color instead of as a monochrome template.
    public let isTinted: Bool
    public let statusText: String
    public let accessibilityLabel: String

    public static func make(for status: AppStatus) -> StatusPresentation {
        switch status {
        case .idle:
            return StatusPresentation(
                symbolName: idleSymbol,
                isTinted: false,
                statusText: "No audio playing, Mac can sleep",
                accessibilityLabel: "Sleepless: Mac can sleep"
            )
        case .playing:
            return StatusPresentation(
                symbolName: activeSymbol,
                isTinted: true,
                statusText: "Audio playing, keeping Mac awake",
                accessibilityLabel: "Sleepless: keeping Mac awake"
            )
        case .holding:
            return StatusPresentation(
                symbolName: activeSymbol,
                isTinted: true,
                statusText: "Audio stopped, keeping Mac awake for a moment",
                accessibilityLabel: "Sleepless: keeping Mac awake"
            )
        case .failed(let code):
            return StatusPresentation(
                symbolName: idleSymbol,
                isTinted: false,
                statusText: "Could not prevent sleep (error \(hex(code)))",
                accessibilityLabel: "Sleepless: Mac can sleep"
            )
        }
    }

    /// Formats an IOKit return code the way Apple documents them, for example 0xE00002C2.
    static func hex(_ code: Int32) -> String {
        String(format: "0x%08X", UInt32(bitPattern: code))
    }
}

/// Version information that Scripts/build-app.sh writes into Info.plist.
public struct BuildInfo: Equatable, Sendable {
    public static let channelKey = "SleeplessBuildChannel"
    public static let commitKey = "SleeplessBuildCommit"

    /// `nil` when running without an app bundle (`swift run`).
    public let version: String?
    public let channel: String
    public let commit: String

    public init(version: String?, channel: String, commit: String) {
        self.version = version
        self.channel = channel
        self.commit = commit
    }

    public init(infoDictionary: [String: Any]?) {
        self.init(
            version: infoDictionary?["CFBundleShortVersionString"] as? String,
            channel: infoDictionary?[BuildInfo.channelKey] as? String ?? "local",
            commit: infoDictionary?[BuildInfo.commitKey] as? String ?? "unknown"
        )
    }

    public var tooltip: String {
        guard let version else { return "Sleepless (unbundled)" }
        if channel == "release" {
            return "Sleepless \(version)"
        }
        return "Sleepless \(version) (\(channel) \(commit))"
    }
}
