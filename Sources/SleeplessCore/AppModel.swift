import Foundation
import os

/// What the menu bar shows.
public enum AppStatus: Equatable, Sendable {
    case idle
    case playing
    case holding
    case failed(code: Int32)
}

/// Connects playback detection, the activation delays and the power assertion.
@MainActor
public final class AppModel {
    public private(set) var status: AppStatus = .idle
    public var onStatusChange: (@MainActor (AppStatus) -> Void)?

    private let detector: any PlaybackDetecting
    private let controller: ActivationController
    private let assertion: any SleepAssertion
    private let logger = Logger(subsystem: Log.subsystem, category: "assertion")

    public init(detector: any PlaybackDetecting, controller: ActivationController, assertion: any SleepAssertion) {
        self.detector = detector
        self.controller = controller
        self.assertion = assertion
    }

    public func start() {
        controller.onPhaseChange = { [weak self] phase in
            self?.phaseChanged(phase)
        }
        detector.onChange = { [weak self] isPlaying in
            self?.controller.playbackChanged(isPlaying)
        }
        detector.start()
        controller.playbackChanged(detector.isPlaying)
    }

    /// Re-reads the playback state, for example after wake from sleep.
    public func refresh() {
        detector.refresh()
    }

    /// Stops watching and releases the assertion. Called when the app quits.
    public func stop() {
        detector.stop()
        detector.onChange = nil
        controller.reset()
        releaseAssertion()
        setStatus(.idle)
    }

    private func phaseChanged(_ phase: ActivationPhase) {
        switch phase {
        case .idle, .pendingStart:
            releaseAssertion()
            setStatus(.idle)
        case .active, .holding:
            do {
                try acquireAssertion()
                setStatus(phase == .active ? .playing : .holding)
            } catch {
                setStatus(.failed(code: (error as? SleepAssertionError)?.code ?? -1))
            }
        }
    }

    private func acquireAssertion() throws {
        guard !assertion.isHeld else { return }
        do {
            try assertion.acquire()
            logger.notice("Assertion acquired")
        } catch {
            logger.error("Could not prevent sleep: \(String(describing: error), privacy: .public)")
            throw error
        }
    }

    private func releaseAssertion() {
        guard assertion.isHeld else { return }
        assertion.release()
        logger.notice("Assertion released")
    }

    private func setStatus(_ newStatus: AppStatus) {
        guard newStatus != status else { return }
        status = newStatus
        onStatusChange?(newStatus)
    }
}
