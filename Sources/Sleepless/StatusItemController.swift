import AppKit
import SleeplessCore

/// Shows the status in the menu bar and owns the menu.
@MainActor
final class StatusItemController: NSObject, NSMenuDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let statusMenuItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private let loginMenuItem = NSMenuItem(title: "Launch at Login", action: nil, keyEquivalent: "")
    private let loginItem: any LoginItemManaging

    init(loginItem: any LoginItemManaging, buildInfo: BuildInfo) {
        self.loginItem = loginItem
        super.init()

        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.delegate = self
        statusMenuItem.isEnabled = false
        menu.addItem(statusMenuItem)
        menu.addItem(.separator())
        loginMenuItem.target = self
        loginMenuItem.action = #selector(toggleLaunchAtLogin(_:))
        menu.addItem(loginMenuItem)
        menu.addItem(.separator())
        let quitItem = NSMenuItem(
            title: "Quit Sleepless",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        quitItem.target = NSApplication.shared
        menu.addItem(quitItem)

        statusItem.menu = menu
        statusItem.button?.toolTip = buildInfo.tooltip
        updateLoginMenuItem()
        render(.idle)
    }

    func render(_ status: AppStatus) {
        let presentation = StatusPresentation.make(for: status)
        statusMenuItem.title = presentation.statusText
        statusItem.button?.image = Self.image(for: presentation)
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        updateLoginMenuItem()
    }

    private func updateLoginMenuItem() {
        let state = LoginItemMenuState.make(for: loginItem.status)
        loginMenuItem.title = state.title
        loginMenuItem.state = state.isChecked ? .on : .off
        loginMenuItem.isEnabled = state.isEnabled
    }

    @objc private func toggleLaunchAtLogin(_ sender: NSMenuItem) {
        let state = LoginItemMenuState.make(for: loginItem.status)
        if state.opensSystemSettings {
            loginItem.openSystemSettings()
            return
        }
        do {
            try loginItem.setEnabled(!state.isChecked)
        } catch {
            NSApplication.shared.activate(ignoringOtherApps: true)
            NSAlert(error: error).runModal()
        }
        updateLoginMenuItem()
    }

    private static func image(for presentation: StatusPresentation) -> NSImage? {
        guard
            let symbol = NSImage(
                systemSymbolName: presentation.symbolName,
                accessibilityDescription: presentation.accessibilityLabel
            )
        else { return nil }
        guard presentation.isTinted else {
            symbol.isTemplate = true
            return symbol
        }
        let configuration = NSImage.SymbolConfiguration(paletteColors: [.controlAccentColor])
        let tinted = symbol.withSymbolConfiguration(configuration) ?? symbol
        tinted.isTemplate = false
        return tinted
    }
}
