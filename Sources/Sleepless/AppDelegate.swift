import AppKit
import SleeplessCore
import os

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let logger = Logger(subsystem: Log.subsystem, category: "app")
    private var model: AppModel?
    private var statusItemController: StatusItemController?
    private var wakeObserver: (any NSObjectProtocol)?
    private var terminationSource: (any DispatchSourceSignal)?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let settings = Settings(defaults: .standard)
        let model = AppModel(
            detector: CoreAudioPlaybackDetector(),
            controller: ActivationController(settings: settings, scheduler: DispatchScheduler()),
            assertion: IOPMSleepAssertion()
        )
        let statusItemController = StatusItemController(
            loginItem: SMAppServiceLoginItem(),
            buildInfo: BuildInfo(infoDictionary: Bundle.main.infoDictionary)
        )
        model.onStatusChange = { [weak statusItemController] status in
            statusItemController?.render(status)
        }
        model.start()
        statusItemController.render(model.status)
        self.model = model
        self.statusItemController = statusItemController

        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak model] _ in
            MainActor.assumeIsolated { model?.refresh() }
        }
        terminationSource = Self.quitOnSIGTERM()
        logger.notice(
            "Sleepless started (start delay \(settings.startDelay) s, stop delay \(settings.stopDelay) s)"
        )
    }

    func applicationWillTerminate(_ notification: Notification) {
        model?.stop()
        logger.notice("Sleepless stopped")
    }

    /// Turns SIGTERM into a normal quit, so the assertion is released and the stop is logged.
    private static func quitOnSIGTERM() -> any DispatchSourceSignal {
        signal(SIGTERM, SIG_IGN)
        let source = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
        source.setEventHandler {
            MainActor.assumeIsolated { NSApplication.shared.terminate(nil) }
        }
        source.resume()
        return source
    }
}
