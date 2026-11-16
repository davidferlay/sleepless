import ServiceManagement
import Testing

@testable import SleeplessCore

struct LoginItemTests {
    @Test(arguments: [
        (SMAppService.Status.enabled, LoginItemStatus.enabled),
        (.requiresApproval, .requiresApproval),
        (.notRegistered, .disabled),
        (.notFound, .unavailable),
    ])
    func mapsServiceManagementStatus(service: SMAppService.Status, expected: LoginItemStatus) {
        #expect(SMAppServiceLoginItem.map(service) == expected)
    }

    @Test func enabledIsChecked() {
        #expect(
            LoginItemMenuState.make(for: .enabled)
                == LoginItemMenuState(
                    title: "Launch at Login", isChecked: true, isEnabled: true, opensSystemSettings: false)
        )
    }

    @Test func disabledIsUnchecked() {
        #expect(
            LoginItemMenuState.make(for: .disabled)
                == LoginItemMenuState(
                    title: "Launch at Login", isChecked: false, isEnabled: true, opensSystemSettings: false)
        )
    }

    @Test func requiresApprovalOpensSystemSettings() {
        #expect(
            LoginItemMenuState.make(for: .requiresApproval)
                == LoginItemMenuState(
                    title: "Launch at Login (approve in System Settings)",
                    isChecked: false,
                    isEnabled: true,
                    opensSystemSettings: true
                )
        )
    }

    @Test func unavailableIsDisabled() {
        #expect(
            LoginItemMenuState.make(for: .unavailable)
                == LoginItemMenuState(
                    title: "Launch at Login", isChecked: false, isEnabled: false, opensSystemSettings: false)
        )
    }
}
