import Foundation

/// A scheduled action that can be cancelled before it runs.
@MainActor
public protocol ScheduledItem: AnyObject {
    func cancel()
}

/// Runs actions on the main actor after a delay. Injected so tests can control time.
@MainActor
public protocol Scheduling: AnyObject {
    func schedule(after delay: TimeInterval, _ action: @escaping @MainActor () -> Void) -> any ScheduledItem
}

/// Production scheduler backed by the main dispatch queue.
@MainActor
public final class DispatchScheduler: Scheduling {
    public init() {}

    public func schedule(after delay: TimeInterval, _ action: @escaping @MainActor () -> Void) -> any ScheduledItem {
        let item = DispatchScheduledItem(action: action)
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            MainActor.assumeIsolated { item.run() }
        }
        return item
    }
}

@MainActor
private final class DispatchScheduledItem: ScheduledItem {
    private var action: (@MainActor () -> Void)?

    init(action: @escaping @MainActor () -> Void) {
        self.action = action
    }

    func cancel() {
        action = nil
    }

    func run() {
        let action = self.action
        self.action = nil
        action?()
    }
}
