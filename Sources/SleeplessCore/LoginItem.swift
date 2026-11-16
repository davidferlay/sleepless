import Foundation
import ServiceManagement

public enum LoginItemStatus: Equatable, Sendable {
    case enabled
    case requiresApproval
    case disabled
    /// Not running from an app bundle (`swift run`), or macOS cannot find the app.
    case unavailable
}

@MainActor
public protocol LoginItemManaging: AnyObject {
    var status: LoginItemStatus { get }
    func setEnabled(_ enabled: Bool) throws
    func openSystemSettings()
}

/// Launch at Login through `SMAppService.mainApp` (macOS 13+).
@MainActor
public final class SMAppServiceLoginItem: LoginItemManaging {
    private let isBundled: Bool

    public init(isBundled: Bool = Bundle.main.bundleURL.pathExtension == "app") {
        self.isBundled = isBundled
    }

    public var status: LoginItemStatus {
        guard isBundled else { return .unavailable }
        return Self.map(SMAppService.mainApp.status)
    }

    public func setEnabled(_ enabled: Bool) throws {
        guard isBundled else { return }
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }

    public func openSystemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }

    nonisolated static func map(_ status: SMAppService.Status) -> LoginItemStatus {
        switch status {
        case .enabled:
            return .enabled
        case .requiresApproval:
            return .requiresApproval
        case .notRegistered:
            return .disabled
        case .notFound:
            return .unavailable
        @unknown default:
            return .unavailable
        }
    }
}

/// How the Launch at Login menu item looks for a given status.
public struct LoginItemMenuState: Equatable, Sendable {
    public let title: String
    public let isChecked: Bool
    public let isEnabled: Bool
    /// Clicking opens System Settings > Login Items instead of toggling.
    public let opensSystemSettings: Bool

    public static func make(for status: LoginItemStatus) -> LoginItemMenuState {
        switch status {
        case .enabled:
            return LoginItemMenuState(
                title: "Launch at Login", isChecked: true, isEnabled: true, opensSystemSettings: false)
        case .disabled:
            return LoginItemMenuState(
                title: "Launch at Login", isChecked: false, isEnabled: true, opensSystemSettings: false)
        case .requiresApproval:
            return LoginItemMenuState(
                title: "Launch at Login (approve in System Settings)",
                isChecked: false,
                isEnabled: true,
                opensSystemSettings: true
            )
        case .unavailable:
            return LoginItemMenuState(
                title: "Launch at Login", isChecked: false, isEnabled: false, opensSystemSettings: false)
        }
    }
}
