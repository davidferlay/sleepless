import Foundation

/// Where the activation is in its start and stop delays.
public enum ActivationPhase: Equatable, Sendable {
    /// No playback, or the hold ended. Sleep is allowed.
    case idle
    /// Playback started, waiting for the start delay. Sleep is still allowed.
    case pendingStart
    /// Playback lasted at least the start delay. Sleep is prevented.
    case active
    /// Playback stopped, waiting for the stop delay. Sleep is still prevented.
    case holding
}

/// Turns raw playback changes into activation phases by applying the start and stop delays.
@MainActor
public final class ActivationController {
    public private(set) var phase: ActivationPhase = .idle
    public var onPhaseChange: (@MainActor (ActivationPhase) -> Void)?

    private let settings: Settings
    private let scheduler: any Scheduling
    private var pendingItem: (any ScheduledItem)?

    public init(settings: Settings, scheduler: any Scheduling) {
        self.settings = settings
        self.scheduler = scheduler
    }

    public func playbackChanged(_ isPlaying: Bool) {
        switch (phase, isPlaying) {
        case (.idle, true):
            transition(to: .pendingStart)
            pendingItem = scheduler.schedule(after: settings.startDelay) { [weak self] in
                self?.delayElapsed(expecting: .pendingStart, next: .active)
            }
        case (.pendingStart, false):
            cancelPendingItem()
            transition(to: .idle)
        case (.active, false):
            transition(to: .holding)
            pendingItem = scheduler.schedule(after: settings.stopDelay) { [weak self] in
                self?.delayElapsed(expecting: .holding, next: .idle)
            }
        case (.holding, true):
            cancelPendingItem()
            transition(to: .active)
        case (.idle, false), (.pendingStart, true), (.active, true), (.holding, false):
            break
        }
    }

    /// Cancels any pending delay and returns to idle.
    public func reset() {
        cancelPendingItem()
        transition(to: .idle)
    }

    private func delayElapsed(expecting expected: ActivationPhase, next: ActivationPhase) {
        pendingItem = nil
        guard phase == expected else { return }
        transition(to: next)
    }

    private func cancelPendingItem() {
        pendingItem?.cancel()
        pendingItem = nil
    }

    private func transition(to newPhase: ActivationPhase) {
        guard newPhase != phase else { return }
        phase = newPhase
        onPhaseChange?(newPhase)
    }
}
