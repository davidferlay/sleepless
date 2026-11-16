# Sleepless Implementation Plan

> For agentic workers: REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

Goal: Build Sleepless, a minimal macOS menu bar app that prevents idle system sleep while audio plays (with a 3 s start delay and a 30 s hold), shows the state with its menu bar icon, launches at login, and ships with unit, integration, bundle, smoke and end-to-end tests plus GitHub Actions CI and release pipelines.

Architecture: One Swift package. `SleeplessCore` holds all logic behind small protocols (playback detection, scheduling, power assertion, login item), so it is unit tested with fakes and a manual clock. `Sleepless` is a thin AppKit executable (status item and app delegate). Shell scripts assemble, sign, validate, smoke test and package a universal `.app`; the Makefile is the single entry point for local runs and CI.

Tech stack: Swift 6 (strict concurrency), Swift Package Manager, Swift Testing, AppKit, CoreAudio, IOKit power management, ServiceManagement, POSIX sh scripts, GitHub Actions.

Spec: `docs/specs/2026-11-16-sleepless-design.md`

---

## Conventions

- Repository: `/Users/john/Sources/Sleepless`. Run every command from there unless a step says otherwise.
- Commits are left to the owner: the agent never runs `git commit` or `git push`. Each task ends with a suggested commit message.
- Before linting Swift, run `make format` (it rewrites files with `swift format`), then `/usr/bin/swift format lint --strict --recursive Package.swift Sources Tests`. From Task 13 on, `make lint` runs everything.
- Use full command paths (`/usr/bin/swift`, `/usr/bin/git`, ...).
- Expected test totals count test functions: Swift Testing reports a parameterized test once, whatever its number of arguments. What matters is 0 failures; if a total differs only because of how the runner counts, note it and continue.
- Toolchain facts verified on 2026-11-16 on the owner's Mac (Command Line Tools 16.4, Swift 6.1.2, no Xcode):
  - Swift Testing works with the Command Line Tools only (`Testing.framework` is present, XCTest is not).
  - `swift build -c release --triple x86_64-apple-macosx13.0` works; `lipo` merges arm64 and x86_64; both slices have `minos 13.0`.
  - The test bundle binary is `.build/debug/SleeplessPackageTests.xctest/Contents/MacOS/SleeplessPackageTests`.
  - `UserDefaults.standard` reads `-startDelay 1` launch arguments.
  - GitHub runners: `macos-latest` is macOS 26 arm64 with Xcode 26.6 and Homebrew; `macos-15` and `macos-15-intel` are the oldest still offered (macOS 14 retired 2026-11-02). Runner images do not include shellcheck or actionlint.
  - Action majors: `actions/checkout@v7`, `actions/upload-artifact@v7`, `actions/download-artifact@v8`.

## File map

| File | Responsibility | Task |
|-|-|-|
| `.gitignore`, `.swift-format`, `LICENSE`, `Makefile` | Repository basics, formatting rules, entry points | 1 |
| `Package.swift` | Targets: `SleeplessCore`, `Sleepless`, `SleeplessCoreTests`, `SleeplessIntegrationTests` | 1, 4, 9 |
| `Sources/SleeplessCore/Log.swift` | Logging subsystem constant | 1 |
| `Sources/SleeplessCore/Settings.swift` | Start and stop delays from user defaults | 1 |
| `Sources/SleeplessCore/Scheduler.swift` | `Scheduling`, `ScheduledItem`, `DispatchScheduler` | 2 |
| `Sources/SleeplessCore/ActivationController.swift` | Delay state machine | 3 |
| `Sources/SleeplessCore/SleepAssertion.swift` | `SleepAssertion`, `IOPMSleepAssertion` | 4 |
| `Sources/SleeplessCore/PlaybackDetector.swift` | `PlaybackDetecting`, `CoreAudioPlaybackDetector` | 5 |
| `Sources/SleeplessCore/AppModel.swift` | Wiring and `AppStatus` | 6 |
| `Sources/SleeplessCore/LoginItem.swift` | `LoginItemManaging`, `SMAppServiceLoginItem`, `LoginItemMenuState` | 7 |
| `Sources/SleeplessCore/StatusPresentation.swift` | `StatusPresentation`, `BuildInfo` | 8 |
| `Sources/Sleepless/main.swift`, `AppDelegate.swift`, `StatusItemController.swift` | AppKit app | 9 |
| `Tests/SleeplessCoreTests/*.swift` | Unit tests and test doubles | 1-8 |
| `Tests/SleeplessIntegrationTests/*.swift` | Real IOKit, CoreAudio, Dispatch, ServiceManagement | 4, 5, 7 |
| `Resources/Info.plist`, `Resources/AppIcon.icns`, `Scripts/make-icon.swift` | Bundle metadata and icon | 10 |
| `Scripts/build-app.sh`, `Scripts/validate-bundle.sh`, `Scripts/package.sh` | Build, validate, package | 11 |
| `Scripts/smoke-test.sh`, `Scripts/e2e-playback.sh` | Runtime tests of the built app | 12 |
| `Scripts/lint.sh`, `Scripts/coverage-summary.sh`, `.githooks/pre-commit` | Static checks, coverage, hook | 13 |
| `.github/workflows/*.yml`, `.github/dependabot.yml` | CI and releases | 14 |
| `README.md`, `.github/ISSUE_TEMPLATE/feedback.md`, `.github/PULL_REQUEST_TEMPLATE.md` | Documentation | 15 |

---

### Task 0: Toolchain prerequisite (owner runs one sudo command)

The Command Line Tools on this Mac contain a stale `usr/include/swift/module.modulemap` (2023-08-18) from an older install. It redefines the `SwiftBridging` module that the current `bridging.modulemap` (2025-04-15) defines, so any build that imports `IOKit` fails with `redefinition of module 'SwiftBridging'`. Four stale `.private.swiftinterface` files were already moved aside on 2026-11-16 to `/Library/Developer/CLT-stale-swiftinterfaces-2024`.

- [ ] Step 1: Owner moves the stale module map aside (reversible):

```
/usr/bin/sudo /bin/sh -c 'B=/Library/Developer/CLT-stale-swiftinterfaces-2024; /bin/mkdir -p "$B/include-swift" && /bin/mv /Library/Developer/CommandLineTools/usr/include/swift/module.modulemap "$B/include-swift/" && /bin/ls -la "$B/include-swift"'
```

- [ ] Step 2: Verify with the probe package (built earlier in the scratchpad) without any overlay:

Run: `cd /private/tmp/claude-501/-Users-john-Sources-KeepingYouAwake/2163f658-6cf0-466c-a885-237630058241/scratchpad/probe && /bin/rm -rf .build && /usr/bin/swift test 2>&1 | /usr/bin/tail -4`
Expected: `✔ Test run with 2 tests passed` (one passes, one is skipped).

---

### Task 1: Repository scaffold and Settings

Files:
- Create: `.gitignore`, `.swift-format`, `LICENSE`, `Makefile`, `Package.swift`
- Create: `Sources/SleeplessCore/Log.swift`, `Sources/SleeplessCore/Settings.swift`
- Test: `Tests/SleeplessCoreTests/SettingsTests.swift`

- [ ] Step 1: Create `.gitignore`

```
.DS_Store
/.build/
/.swiftpm/
/build/
*.dmg
*.zip
```

- [ ] Step 2: Create `.swift-format` (the `swift format dump-configuration` defaults of swift-format 6.1, with 4-space indentation and 120 columns)

```json
{
  "fileScopedDeclarationPrivacy" : {
    "accessLevel" : "private"
  },
  "indentConditionalCompilationBlocks" : true,
  "indentSwitchCaseLabels" : false,
  "indentation" : {
    "spaces" : 4
  },
  "lineBreakAroundMultilineExpressionChainComponents" : false,
  "lineBreakBeforeControlFlowKeywords" : false,
  "lineBreakBeforeEachArgument" : false,
  "lineBreakBeforeEachGenericRequirement" : false,
  "lineBreakBetweenDeclarationAttributes" : false,
  "lineLength" : 120,
  "maximumBlankLines" : 1,
  "multiElementCollectionTrailingCommas" : true,
  "noAssignmentInExpressions" : {
    "allowedFunctions" : [
      "XCTAssertNoThrow"
    ]
  },
  "prioritizeKeepingFunctionOutputTogether" : false,
  "reflowMultilineStringLiterals" : {
    "never" : {

    }
  },
  "respectsExistingLineBreaks" : true,
  "rules" : {
    "AllPublicDeclarationsHaveDocumentation" : false,
    "AlwaysUseLiteralForEmptyCollectionInit" : false,
    "AlwaysUseLowerCamelCase" : true,
    "AmbiguousTrailingClosureOverload" : true,
    "AvoidRetroactiveConformances" : true,
    "BeginDocumentationCommentWithOneLineSummary" : false,
    "DoNotUseSemicolons" : true,
    "DontRepeatTypeInStaticProperties" : true,
    "FileScopedDeclarationPrivacy" : true,
    "FullyIndirectEnum" : true,
    "GroupNumericLiterals" : true,
    "IdentifiersMustBeASCII" : true,
    "NeverForceUnwrap" : false,
    "NeverUseForceTry" : false,
    "NeverUseImplicitlyUnwrappedOptionals" : false,
    "NoAccessLevelOnExtensionDeclaration" : true,
    "NoAssignmentInExpressions" : true,
    "NoBlockComments" : true,
    "NoCasesWithOnlyFallthrough" : true,
    "NoEmptyLinesOpeningClosingBraces" : false,
    "NoEmptyTrailingClosureParentheses" : true,
    "NoLabelsInCasePatterns" : true,
    "NoLeadingUnderscores" : false,
    "NoParensAroundConditions" : true,
    "NoPlaygroundLiterals" : true,
    "NoVoidReturnOnFunctionSignature" : true,
    "OmitExplicitReturns" : false,
    "OneCasePerLine" : true,
    "OneVariableDeclarationPerLine" : true,
    "OnlyOneTrailingClosureArgument" : true,
    "OrderedImports" : true,
    "ReplaceForEachWithForLoop" : true,
    "ReturnVoidInsteadOfEmptyTuple" : true,
    "TypeNamesShouldBeCapitalized" : true,
    "UseEarlyExits" : false,
    "UseExplicitNilCheckInConditions" : true,
    "UseLetInEveryBoundCaseVariable" : true,
    "UseShorthandTypeNames" : true,
    "UseSingleLinePropertyGetter" : true,
    "UseSynthesizedInitializer" : true,
    "UseTripleSlashForDocumentationComments" : true,
    "UseWhereClausesInForLoops" : false,
    "ValidateDocumentationComments" : false
  },
  "spacesAroundRangeFormationOperators" : false,
  "spacesBeforeEndOfLineComments" : 2,
  "tabWidth" : 8,
  "version" : 1
}
```

- [ ] Step 3: Create `LICENSE` from the GPL-3.0 text already used by Octatrack-Manager, and check it is the unmodified license

Run: `/bin/cp /Users/john/Sources/Octatrack-Manager/LICENSE LICENSE && /usr/bin/head -3 LICENSE && /usr/bin/wc -c < LICENSE`
Expected: `GNU GENERAL PUBLIC LICENSE` and `Version 3, 29 June 2007` in the first lines, and `35149` bytes (the size of the canonical GPL-3.0 text).

- [ ] Step 4: Create `Makefile` (recipe lines start with a tab)

```make
# Entry points used the same way locally and in CI.
SWIFT := /usr/bin/swift
APP := build/Sleepless.app
VERSION ?= 0.0.0

.PHONY: build test test-integration coverage format lint app validate smoke e2e package icon install-hooks clean

build:
	$(SWIFT) build

test:
	$(SWIFT) test --filter SleeplessCoreTests

test-integration:
	$(SWIFT) test --filter SleeplessIntegrationTests

coverage:
	$(SWIFT) test --filter SleeplessCoreTests --enable-code-coverage
	Scripts/coverage-summary.sh

format:
	$(SWIFT) format format --in-place --recursive Package.swift Sources Tests Scripts/make-icon.swift

lint:
	Scripts/lint.sh

app:
	Scripts/build-app.sh

validate:
	Scripts/validate-bundle.sh $(APP)

smoke:
	Scripts/smoke-test.sh $(APP)

e2e:
	Scripts/e2e-playback.sh $(APP)

package:
	Scripts/package.sh $(VERSION)

icon:
	$(SWIFT) Scripts/make-icon.swift Resources/AppIcon.icns

install-hooks:
	/usr/bin/git config core.hooksPath .githooks

clean:
	/bin/rm -rf .build build
```

Until Task 10 creates `Scripts/make-icon.swift`, run `make format` as `/usr/bin/swift format format --in-place --recursive Package.swift Sources Tests`.

- [ ] Step 5: Create `Package.swift` (library and unit tests only for now)

```swift
// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "Sleepless",
    platforms: [.macOS(.v13)],
    targets: [
        .target(name: "SleeplessCore"),
        .testTarget(name: "SleeplessCoreTests", dependencies: ["SleeplessCore"]),
    ]
)
```

- [ ] Step 6: Create `Sources/SleeplessCore/Log.swift`

```swift
/// Logging constants shared by the app and its tests.
public enum Log {
    /// Unified logging subsystem, used by `log show` and `log stream` predicates.
    public static let subsystem = "io.github.davidferlay.Sleepless"
}
```

- [ ] Step 7: Write the failing tests `Tests/SleeplessCoreTests/SettingsTests.swift`

```swift
import Testing

@testable import SleeplessCore

struct SettingsTests {
    @Test func usesDefaultsWhenNothingIsSet() {
        let settings = Settings(lookup: { _ in nil })
        #expect(settings.startDelay == 3)
        #expect(settings.stopDelay == 30)
    }

    @Test func readsNumbers() {
        let values: [String: Any] = ["startDelay": 1.5, "stopDelay": 4]
        let settings = Settings(lookup: { values[$0] })
        #expect(settings.startDelay == 1.5)
        #expect(settings.stopDelay == 4)
    }

    @Test func readsNumericStringsFromLaunchArguments() {
        let values: [String: Any] = ["startDelay": "1", "stopDelay": "3.5"]
        let settings = Settings(lookup: { values[$0] })
        #expect(settings.startDelay == 1)
        #expect(settings.stopDelay == 3.5)
    }

    @Test(arguments: [0, -1, Double.nan, Double.infinity] as [Double])
    func rejectsNonPositiveOrNonFiniteNumbers(value: Double) {
        let settings = Settings(lookup: { _ in value })
        #expect(settings == Settings())
    }

    @Test(arguments: ["", "abc", "-2", "0"])
    func rejectsInvalidStrings(value: String) {
        let settings = Settings(lookup: { _ in value })
        #expect(settings == Settings())
    }

    @Test func rejectsOtherTypes() {
        let settings = Settings(lookup: { _ in [1, 2] })
        #expect(settings == Settings())
    }
}
```

- [ ] Step 8: Run the tests to verify they fail

Run: `/usr/bin/swift test --filter SleeplessCoreTests 2>&1 | /usr/bin/tail -5`
Expected: build failure, `cannot find 'Settings' in scope`.

- [ ] Step 9: Implement `Sources/SleeplessCore/Settings.swift`

```swift
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
```

- [ ] Step 10: Run the tests to verify they pass, and check the module filter selects them

Run: `/usr/bin/swift test --filter SleeplessCoreTests 2>&1 | /usr/bin/tail -3`
Expected: `✔ Test run with 6 tests passed` (the two parameterized tests run 4 cases each). If the filter selects 0 tests, change the Makefile `--filter` values to `SleeplessCoreTests\.` / `SleeplessIntegrationTests\.` and note it.

- [ ] Step 11: Format and lint

Run: `/usr/bin/swift format format --in-place --recursive Package.swift Sources Tests && /usr/bin/swift format lint --strict --recursive Package.swift Sources Tests`
Expected: no output, exit 0.

Suggested commit: `feat: scaffold Sleepless package with settings`

---

### Task 2: Scheduler and manual test clock

Files:
- Create: `Sources/SleeplessCore/Scheduler.swift`
- Create: `Tests/SleeplessCoreTests/Fakes.swift`
- Test: `Tests/SleeplessCoreTests/ManualSchedulerTests.swift`

- [ ] Step 1: Write `Tests/SleeplessCoreTests/Fakes.swift` (test double used by later tasks)

```swift
import Foundation

@testable import SleeplessCore

/// Scheduler whose clock only moves when a test calls `advance(by:)`.
@MainActor
final class ManualScheduler: Scheduling {
    private struct Entry {
        let order: Int
        let due: TimeInterval
        let item: ManualScheduledItem
    }

    private(set) var now: TimeInterval = 0
    private var entries: [Entry] = []
    private var nextOrder = 0

    /// Scheduled actions that have neither run nor been cancelled.
    var pendingCount: Int {
        entries.filter { !$0.item.isFinished }.count
    }

    func schedule(after delay: TimeInterval, _ action: @escaping @MainActor () -> Void) -> any ScheduledItem {
        let item = ManualScheduledItem(action: action)
        entries.append(Entry(order: nextOrder, due: now + delay, item: item))
        nextOrder += 1
        return item
    }

    /// Moves the clock forward and runs due actions in time order, including actions they schedule.
    func advance(by interval: TimeInterval) {
        let target = now + interval
        while let next = entries.filter({ $0.due <= target }).min(by: { ($0.due, $0.order) < ($1.due, $1.order) }) {
            entries.removeAll { $0.order == next.order }
            now = next.due
            next.item.runIfPending()
        }
        now = target
    }
}

@MainActor
final class ManualScheduledItem: ScheduledItem {
    private let action: @MainActor () -> Void
    private(set) var isFinished = false

    init(action: @escaping @MainActor () -> Void) {
        self.action = action
    }

    func cancel() {
        isFinished = true
    }

    func runIfPending() {
        guard !isFinished else { return }
        isFinished = true
        action()
    }
}
```

- [ ] Step 2: Write the failing tests `Tests/SleeplessCoreTests/ManualSchedulerTests.swift`

```swift
import Testing

@testable import SleeplessCore

@MainActor
private final class CallLog {
    var calls: [String] = []
}

@MainActor
struct ManualSchedulerTests {
    @Test func runsActionsOnlyWhenTheirTimeComes() {
        let scheduler = ManualScheduler()
        let log = CallLog()
        _ = scheduler.schedule(after: 2) { log.calls.append("a") }
        scheduler.advance(by: 1.5)
        #expect(log.calls.isEmpty)
        scheduler.advance(by: 0.5)
        #expect(log.calls == ["a"])
        #expect(scheduler.pendingCount == 0)
    }

    @Test func runsActionsInTimeOrder() {
        let scheduler = ManualScheduler()
        let log = CallLog()
        _ = scheduler.schedule(after: 3) { log.calls.append("late") }
        _ = scheduler.schedule(after: 1) { log.calls.append("early") }
        scheduler.advance(by: 5)
        #expect(log.calls == ["early", "late"])
    }

    @Test func cancelledActionsNeverRun() {
        let scheduler = ManualScheduler()
        let log = CallLog()
        let item = scheduler.schedule(after: 1) { log.calls.append("a") }
        item.cancel()
        scheduler.advance(by: 5)
        #expect(log.calls.isEmpty)
        #expect(scheduler.pendingCount == 0)
    }

    @Test func runsActionsScheduledByActionsWhenDue() {
        let scheduler = ManualScheduler()
        let log = CallLog()
        _ = scheduler.schedule(after: 1) {
            log.calls.append("first")
            _ = scheduler.schedule(after: 1) { log.calls.append("second") }
        }
        scheduler.advance(by: 1.5)
        #expect(log.calls == ["first"])
        scheduler.advance(by: 0.5)
        #expect(log.calls == ["first", "second"])
    }
}
```

- [ ] Step 3: Run the tests to verify they fail

Run: `/usr/bin/swift test --filter SleeplessCoreTests 2>&1 | /usr/bin/tail -5`
Expected: build failure, `cannot find type 'Scheduling' in scope`.

- [ ] Step 4: Implement `Sources/SleeplessCore/Scheduler.swift`

```swift
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
```

- [ ] Step 5: Run the tests to verify they pass

Run: `/usr/bin/swift test --filter SleeplessCoreTests 2>&1 | /usr/bin/tail -3`
Expected: `✔ Test run with 10 tests passed`.

- [ ] Step 6: Format and lint (as in Task 1 Step 11). Expected: exit 0.

Suggested commit: `feat: add scheduler abstraction and manual test clock`

---

### Task 3: ActivationController

Files:
- Create: `Sources/SleeplessCore/ActivationController.swift`
- Test: `Tests/SleeplessCoreTests/ActivationControllerTests.swift`

- [ ] Step 1: Write the failing tests `Tests/SleeplessCoreTests/ActivationControllerTests.swift`

```swift
import Foundation
import Testing

@testable import SleeplessCore

@MainActor
private final class PhaseRecorder {
    var phases: [ActivationPhase] = []
}

@MainActor
private func makeController(
    startDelay: TimeInterval = 3,
    stopDelay: TimeInterval = 30
) -> (ActivationController, ManualScheduler, PhaseRecorder) {
    let scheduler = ManualScheduler()
    let controller = ActivationController(
        settings: Settings(startDelay: startDelay, stopDelay: stopDelay),
        scheduler: scheduler
    )
    let recorder = PhaseRecorder()
    controller.onPhaseChange = { recorder.phases.append($0) }
    return (controller, scheduler, recorder)
}

@MainActor
struct ActivationControllerTests {
    @Test func startsIdle() {
        let (controller, _, recorder) = makeController()
        #expect(controller.phase == .idle)
        #expect(recorder.phases.isEmpty)
    }

    @Test func shortSoundDoesNotActivate() {
        let (controller, scheduler, recorder) = makeController()
        controller.playbackChanged(true)
        scheduler.advance(by: 2.5)
        controller.playbackChanged(false)
        scheduler.advance(by: 60)
        #expect(controller.phase == .idle)
        #expect(recorder.phases == [.pendingStart, .idle])
        #expect(scheduler.pendingCount == 0)
    }

    @Test func activatesAfterStartDelay() {
        let (controller, scheduler, recorder) = makeController()
        controller.playbackChanged(true)
        scheduler.advance(by: 2.5)
        #expect(controller.phase == .pendingStart)
        scheduler.advance(by: 0.5)
        #expect(controller.phase == .active)
        #expect(recorder.phases == [.pendingStart, .active])
    }

    @Test func holdsForStopDelayAfterPlaybackStops() {
        let (controller, scheduler, recorder) = makeController()
        controller.playbackChanged(true)
        scheduler.advance(by: 3)
        controller.playbackChanged(false)
        #expect(controller.phase == .holding)
        scheduler.advance(by: 29.5)
        #expect(controller.phase == .holding)
        scheduler.advance(by: 0.5)
        #expect(controller.phase == .idle)
        #expect(recorder.phases == [.pendingStart, .active, .holding, .idle])
    }

    @Test func resumingDuringHoldKeepsOneActivation() {
        let (controller, scheduler, recorder) = makeController()
        controller.playbackChanged(true)
        scheduler.advance(by: 3)
        controller.playbackChanged(false)
        scheduler.advance(by: 10)
        controller.playbackChanged(true)
        #expect(controller.phase == .active)
        scheduler.advance(by: 120)
        #expect(controller.phase == .active)
        #expect(recorder.phases == [.pendingStart, .active, .holding, .active])
        #expect(scheduler.pendingCount == 0)
    }

    @Test func flappingRestartsTheStartDelay() {
        let (controller, scheduler, recorder) = makeController()
        controller.playbackChanged(true)
        scheduler.advance(by: 1)
        controller.playbackChanged(false)
        scheduler.advance(by: 0.5)
        controller.playbackChanged(true)
        scheduler.advance(by: 2.5)
        #expect(controller.phase == .pendingStart)
        scheduler.advance(by: 0.5)
        #expect(controller.phase == .active)
        #expect(recorder.phases == [.pendingStart, .idle, .pendingStart, .active])
    }

    @Test func repeatedReportsAreIgnored() {
        let (controller, scheduler, recorder) = makeController()
        controller.playbackChanged(true)
        controller.playbackChanged(true)
        #expect(scheduler.pendingCount == 1)
        scheduler.advance(by: 3)
        controller.playbackChanged(true)
        controller.playbackChanged(false)
        controller.playbackChanged(false)
        #expect(scheduler.pendingCount == 1)
        #expect(recorder.phases == [.pendingStart, .active, .holding])
    }

    @Test func resetCancelsThePendingDelayAndGoesIdle() {
        let (controller, scheduler, recorder) = makeController()
        controller.playbackChanged(true)
        scheduler.advance(by: 3)
        controller.playbackChanged(false)
        controller.reset()
        #expect(controller.phase == .idle)
        #expect(scheduler.pendingCount == 0)
        scheduler.advance(by: 60)
        #expect(recorder.phases == [.pendingStart, .active, .holding, .idle])
    }

    @Test func usesConfiguredDelays() {
        let (controller, scheduler, _) = makeController(startDelay: 1, stopDelay: 4)
        controller.playbackChanged(true)
        scheduler.advance(by: 1)
        #expect(controller.phase == .active)
        controller.playbackChanged(false)
        scheduler.advance(by: 4)
        #expect(controller.phase == .idle)
    }
}
```

- [ ] Step 2: Run the tests to verify they fail

Run: `/usr/bin/swift test --filter SleeplessCoreTests 2>&1 | /usr/bin/tail -5`
Expected: build failure, `cannot find type 'ActivationPhase' in scope`.

- [ ] Step 3: Implement `Sources/SleeplessCore/ActivationController.swift`

```swift
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
```

- [ ] Step 4: Run the tests to verify they pass

Run: `/usr/bin/swift test --filter SleeplessCoreTests 2>&1 | /usr/bin/tail -3`
Expected: `✔ Test run with 19 tests passed`.

- [ ] Step 5: Format and lint. Expected: exit 0.

Suggested commit: `feat: add activation controller with start delay and hold`

---

### Task 4: Power assertion

Files:
- Modify: `Package.swift` (add the integration test target)
- Create: `Sources/SleeplessCore/SleepAssertion.swift`
- Create: `Tests/SleeplessIntegrationTests/PowerAssertions.swift`
- Test: `Tests/SleeplessIntegrationTests/IOPMSleepAssertionTests.swift`

- [ ] Step 1: Replace `Package.swift`

```swift
// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "Sleepless",
    platforms: [.macOS(.v13)],
    targets: [
        .target(name: "SleeplessCore"),
        .testTarget(name: "SleeplessCoreTests", dependencies: ["SleeplessCore"]),
        .testTarget(name: "SleeplessIntegrationTests", dependencies: ["SleeplessCore"]),
    ]
)
```

- [ ] Step 2: Create `Tests/SleeplessIntegrationTests/PowerAssertions.swift`

```swift
import Foundation
import IOKit.pwr_mgt

struct PowerAssertion: Equatable {
    let type: String
    let name: String
}

enum PowerAssertions {
    /// Power assertions currently held by this test process, as reported by IOKit.
    static func forCurrentProcess() -> [PowerAssertion] {
        var unmanaged: Unmanaged<CFDictionary>?
        guard IOPMCopyAssertionsByProcess(&unmanaged) == kIOReturnSuccess,
            let byProcess = unmanaged?.takeRetainedValue() as? [NSNumber: [[String: Any]]]
        else { return [] }
        let entries = byProcess.first(where: { $0.key.int32Value == getpid() })?.value ?? []
        return entries.map {
            PowerAssertion(
                type: $0[kIOPMAssertionTypeKey] as? String ?? "",
                name: $0[kIOPMAssertionNameKey] as? String ?? ""
            )
        }
    }
}
```

- [ ] Step 3: Write the failing tests `Tests/SleeplessIntegrationTests/IOPMSleepAssertionTests.swift`

```swift
import Foundation
import Testing

@testable import SleeplessCore

@MainActor
@Suite(.serialized)
struct IOPMSleepAssertionTests {
    private func uniqueName() -> String {
        "Sleepless test \(UUID().uuidString)"
    }

    @Test func acquiredAssertionIsVisibleToPowerManagement() throws {
        let name = uniqueName()
        let assertion = IOPMSleepAssertion(name: name)
        try assertion.acquire()
        defer { assertion.release() }
        #expect(assertion.isHeld)
        let held = PowerAssertions.forCurrentProcess().filter { $0.name == name }
        #expect(held == [PowerAssertion(type: "PreventUserIdleSystemSleep", name: name)])
    }

    @Test func releaseRemovesTheAssertion() throws {
        let name = uniqueName()
        let assertion = IOPMSleepAssertion(name: name)
        try assertion.acquire()
        assertion.release()
        #expect(!assertion.isHeld)
        #expect(PowerAssertions.forCurrentProcess().filter { $0.name == name }.isEmpty)
    }

    @Test func acquiringTwiceHoldsOneAssertion() throws {
        let name = uniqueName()
        let assertion = IOPMSleepAssertion(name: name)
        try assertion.acquire()
        try assertion.acquire()
        defer { assertion.release() }
        #expect(PowerAssertions.forCurrentProcess().filter { $0.name == name }.count == 1)
    }

    @Test func releasingWithoutAcquiringIsHarmless() {
        let assertion = IOPMSleepAssertion(name: uniqueName())
        assertion.release()
        assertion.release()
        #expect(!assertion.isHeld)
    }

    @Test func defaultNameIsTheOneTheEndToEndTestLooksFor() {
        #expect(IOPMSleepAssertion().name == "Sleepless: audio playback")
    }
}
```

- [ ] Step 4: Run the tests to verify they fail

Run: `/usr/bin/swift test --filter SleeplessIntegrationTests 2>&1 | /usr/bin/tail -5`
Expected: build failure, `cannot find 'IOPMSleepAssertion' in scope`.

- [ ] Step 5: Implement `Sources/SleeplessCore/SleepAssertion.swift`

```swift
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
```

- [ ] Step 6: Run the tests to verify they pass

Run: `/usr/bin/swift test --filter SleeplessIntegrationTests 2>&1 | /usr/bin/tail -3`
Expected: `✔ Test run with 5 tests passed`.

- [ ] Step 7: Check the unit test filter still excludes integration tests

Run: `/usr/bin/swift test --filter SleeplessCoreTests 2>&1 | /usr/bin/tail -1`
Expected: `✔ Test run with 19 tests passed` (unchanged count).

- [ ] Step 8: Format and lint. Expected: exit 0.

Suggested commit: `feat: add IOKit power assertion with integration tests`

---

### Task 5: Playback detection

Files:
- Create: `Sources/SleeplessCore/PlaybackDetector.swift`
- Test: `Tests/SleeplessIntegrationTests/CoreAudioPlaybackDetectorTests.swift`

- [ ] Step 1: Write the failing tests `Tests/SleeplessIntegrationTests/CoreAudioPlaybackDetectorTests.swift`

```swift
import CoreAudio
import Testing

@testable import SleeplessCore

@MainActor
@Suite(.enabled(if: CoreAudioPlaybackDetector.defaultOutputDevice() != nil, "needs a default audio output device"))
struct CoreAudioPlaybackDetectorTests {
    @Test func startRegistersListenersAndStopRemovesThem() {
        let detector = CoreAudioPlaybackDetector()
        detector.start()
        #expect(detector.isWatching)
        detector.stop()
        #expect(!detector.isWatching)
    }

    @Test func startingTwiceIsHarmless() {
        let detector = CoreAudioPlaybackDetector()
        detector.start()
        detector.start()
        #expect(detector.isWatching)
        detector.stop()
        #expect(!detector.isWatching)
    }

    @Test func reportsTheStateCoreAudioReports() throws {
        let detector = CoreAudioPlaybackDetector()
        detector.start()
        defer { detector.stop() }
        let device = try #require(CoreAudioPlaybackDetector.defaultOutputDevice())
        #expect(detector.isPlaying == CoreAudioPlaybackDetector.isRunningSomewhere(device))
    }
}

struct CoreAudioQueryTests {
    @Test func unknownDeviceIsNotRunning() {
        #expect(!CoreAudioPlaybackDetector.isRunningSomewhere(AudioObjectID(kAudioObjectUnknown)))
    }
}
```

- [ ] Step 2: Run the tests to verify they fail

Run: `/usr/bin/swift test --filter SleeplessIntegrationTests 2>&1 | /usr/bin/tail -5`
Expected: build failure, `cannot find 'CoreAudioPlaybackDetector' in scope`.

- [ ] Step 3: Implement `Sources/SleeplessCore/PlaybackDetector.swift`

```swift
import CoreAudio
import Foundation
import os

/// Reports whether audio is playing.
@MainActor
public protocol PlaybackDetecting: AnyObject {
    var isPlaying: Bool { get }
    var onChange: (@MainActor (Bool) -> Void)? { get set }
    func start()
    func stop()
    /// Re-reads the current state, for example after the Mac wakes from sleep.
    func refresh()
}

/// Detects playback on the default output device through `kAudioDevicePropertyDeviceIsRunningSomewhere`.
/// Event driven: CoreAudio calls the listeners on the main queue, nothing polls.
@MainActor
public final class CoreAudioPlaybackDetector: PlaybackDetecting {
    public private(set) var isPlaying = false
    public var onChange: (@MainActor (Bool) -> Void)?

    private var deviceID = CoreAudioPlaybackDetector.unknownDevice
    private var defaultDeviceListener: AudioObjectPropertyListenerBlock?
    private var runningListener: AudioObjectPropertyListenerBlock?
    private let logger = Logger(subsystem: Log.subsystem, category: "playback")

    public init() {}

    /// True while the default-device listener and, when a device exists, its running-state listener are registered.
    public var isWatching: Bool {
        defaultDeviceListener != nil && (deviceID == Self.unknownDevice || runningListener != nil)
    }

    public func start() {
        guard defaultDeviceListener == nil else { return }
        let listener: AudioObjectPropertyListenerBlock = { @Sendable [weak self] _, _ in
            MainActor.assumeIsolated { self?.defaultDeviceChanged() }
        }
        var address = Self.defaultOutputDeviceAddress
        let status = AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            DispatchQueue.main,
            listener
        )
        if status == noErr {
            defaultDeviceListener = listener
        } else {
            logger.error("Could not watch the default output device (OSStatus \(status))")
        }
        defaultDeviceChanged()
    }

    public func stop() {
        removeRunningListener()
        if let listener = defaultDeviceListener {
            var address = Self.defaultOutputDeviceAddress
            AudioObjectRemovePropertyListenerBlock(
                AudioObjectID(kAudioObjectSystemObject),
                &address,
                DispatchQueue.main,
                listener
            )
            defaultDeviceListener = nil
        }
        deviceID = Self.unknownDevice
    }

    public func refresh() {
        let playing = deviceID != Self.unknownDevice && Self.isRunningSomewhere(deviceID)
        guard playing != isPlaying else { return }
        isPlaying = playing
        logger.notice("Playback detected: \(playing ? "YES" : "NO", privacy: .public)")
        onChange?(playing)
    }

    /// The current default output device, or `nil` when there is none.
    public nonisolated static func defaultOutputDevice() -> AudioObjectID? {
        var address = defaultOutputDeviceAddress
        var device = unknownDevice
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &size,
            &device
        )
        guard status == noErr, device != unknownDevice else { return nil }
        return device
    }

    /// Whether any process is doing I/O on `device`.
    public nonisolated static func isRunningSomewhere(_ device: AudioObjectID) -> Bool {
        guard device != unknownDevice else { return false }
        var address = runningSomewhereAddress
        var running = UInt32(0)
        var size = UInt32(MemoryLayout<UInt32>.size)
        let status = AudioObjectGetPropertyData(device, &address, 0, nil, &size, &running)
        return status == noErr && running != 0
    }

    private nonisolated static let unknownDevice = AudioObjectID(kAudioObjectUnknown)

    private nonisolated static var defaultOutputDeviceAddress: AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
    }

    private nonisolated static var runningSomewhereAddress: AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceIsRunningSomewhere,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
    }

    private func defaultDeviceChanged() {
        let newDevice = Self.defaultOutputDevice() ?? Self.unknownDevice
        if newDevice != deviceID {
            removeRunningListener()
            deviceID = newDevice
            addRunningListener()
            logger.notice("Default output device: \(newDevice)")
        }
        refresh()
    }

    private func addRunningListener() {
        guard deviceID != Self.unknownDevice else { return }
        let listener: AudioObjectPropertyListenerBlock = { @Sendable [weak self] _, _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        var address = Self.runningSomewhereAddress
        let status = AudioObjectAddPropertyListenerBlock(deviceID, &address, DispatchQueue.main, listener)
        if status == noErr {
            runningListener = listener
        } else {
            logger.error("Could not watch output device \(self.deviceID) (OSStatus \(status))")
        }
    }

    private func removeRunningListener() {
        guard let listener = runningListener else { return }
        var address = Self.runningSomewhereAddress
        AudioObjectRemovePropertyListenerBlock(deviceID, &address, DispatchQueue.main, listener)
        runningListener = nil
    }
}
```

- [ ] Step 4: Run the tests to verify they pass

Run: `/usr/bin/swift test --filter SleeplessIntegrationTests 2>&1 | /usr/bin/tail -3`
Expected: `✔ Test run with 9 tests passed`. If the compiler rejects the `@Sendable` closure conversion to `AudioObjectPropertyListenerBlock`, remove `@Sendable` from both listener closures (they run on the main queue either way) and re-run.

- [ ] Step 5: Format and lint. Expected: exit 0.

Suggested commit: `feat: detect playback on the default output device`

---

### Task 6: AppModel

Files:
- Modify: `Tests/SleeplessCoreTests/Fakes.swift` (append fakes)
- Create: `Sources/SleeplessCore/AppModel.swift`
- Test: `Tests/SleeplessCoreTests/AppModelTests.swift`

- [ ] Step 1: Append to `Tests/SleeplessCoreTests/Fakes.swift`

```swift

/// Playback detector driven by the test.
@MainActor
final class FakeDetector: PlaybackDetecting {
    var isPlaying = false
    var onChange: (@MainActor (Bool) -> Void)?
    private(set) var startCount = 0
    private(set) var stopCount = 0
    private(set) var refreshCount = 0

    func start() {
        startCount += 1
    }

    func stop() {
        stopCount += 1
    }

    func refresh() {
        refreshCount += 1
    }

    /// Simulates CoreAudio reporting a change.
    func simulate(playing: Bool) {
        isPlaying = playing
        onChange?(playing)
    }
}

/// Power assertion that records calls and can be told to fail.
@MainActor
final class FakeAssertion: SleepAssertion {
    private(set) var isHeld = false
    private(set) var acquireAttempts = 0
    private(set) var releaseCount = 0
    /// When set, `acquire()` throws this IOKit error code.
    var failureCode: Int32?

    func acquire() throws {
        acquireAttempts += 1
        if let failureCode {
            throw SleepAssertionError(code: failureCode)
        }
        isHeld = true
    }

    func release() {
        releaseCount += 1
        isHeld = false
    }
}
```

- [ ] Step 2: Write the failing tests `Tests/SleeplessCoreTests/AppModelTests.swift`

```swift
import Testing

@testable import SleeplessCore

@MainActor
private final class Harness {
    let detector: FakeDetector
    let assertion: FakeAssertion
    let scheduler: ManualScheduler
    let model: AppModel
    var statuses: [AppStatus] = []

    init() {
        detector = FakeDetector()
        assertion = FakeAssertion()
        scheduler = ManualScheduler()
        model = AppModel(
            detector: detector,
            controller: ActivationController(settings: Settings(), scheduler: scheduler),
            assertion: assertion
        )
        model.onStatusChange = { [unowned self] in self.statuses.append($0) }
    }
}

@MainActor
struct AppModelTests {
    private let notPermitted = Int32(bitPattern: 0xE000_02E2)

    @Test func startsIdleAndStartsTheDetector() {
        let harness = Harness()
        harness.model.start()
        #expect(harness.detector.startCount == 1)
        #expect(harness.model.status == .idle)
        #expect(!harness.assertion.isHeld)
    }

    @Test func preventsSleepOnlyAfterTheStartDelay() {
        let harness = Harness()
        harness.model.start()
        harness.detector.simulate(playing: true)
        harness.scheduler.advance(by: 2.5)
        #expect(harness.model.status == .idle)
        #expect(!harness.assertion.isHeld)
        harness.scheduler.advance(by: 0.5)
        #expect(harness.model.status == .playing)
        #expect(harness.assertion.isHeld)
        #expect(harness.assertion.acquireAttempts == 1)
    }

    @Test func detectsPlaybackAlreadyRunningAtLaunch() {
        let harness = Harness()
        harness.detector.isPlaying = true
        harness.model.start()
        harness.scheduler.advance(by: 3)
        #expect(harness.model.status == .playing)
    }

    @Test func keepsOneAssertionAcrossTrackGaps() {
        let harness = Harness()
        harness.model.start()
        harness.detector.simulate(playing: true)
        harness.scheduler.advance(by: 3)
        harness.detector.simulate(playing: false)
        harness.scheduler.advance(by: 10)
        harness.detector.simulate(playing: true)
        harness.scheduler.advance(by: 3)
        #expect(harness.model.status == .playing)
        #expect(harness.assertion.acquireAttempts == 1)
        #expect(harness.assertion.releaseCount == 0)
        #expect(harness.statuses == [.playing, .holding, .playing])
    }

    @Test func releasesAfterTheHold() {
        let harness = Harness()
        harness.model.start()
        harness.detector.simulate(playing: true)
        harness.scheduler.advance(by: 3)
        harness.detector.simulate(playing: false)
        #expect(harness.model.status == .holding)
        #expect(harness.assertion.isHeld)
        harness.scheduler.advance(by: 30)
        #expect(harness.model.status == .idle)
        #expect(!harness.assertion.isHeld)
        #expect(harness.assertion.releaseCount == 1)
        #expect(harness.statuses == [.playing, .holding, .idle])
    }

    @Test func reportsAnAssertionFailure() {
        let harness = Harness()
        harness.assertion.failureCode = notPermitted
        harness.model.start()
        harness.detector.simulate(playing: true)
        harness.scheduler.advance(by: 3)
        #expect(harness.model.status == .failed(code: notPermitted))
        #expect(!harness.assertion.isHeld)
    }

    @Test func recoversOnTheNextActivationAfterAFailure() {
        let harness = Harness()
        harness.assertion.failureCode = notPermitted
        harness.model.start()
        harness.detector.simulate(playing: true)
        harness.scheduler.advance(by: 3)
        harness.detector.simulate(playing: false)
        harness.scheduler.advance(by: 30)
        #expect(harness.model.status == .idle)
        harness.assertion.failureCode = nil
        harness.detector.simulate(playing: true)
        harness.scheduler.advance(by: 3)
        #expect(harness.model.status == .playing)
        #expect(harness.assertion.isHeld)
    }

    @Test func stopReleasesTheAssertionAndStopsTheDetector() {
        let harness = Harness()
        harness.model.start()
        harness.detector.simulate(playing: true)
        harness.scheduler.advance(by: 3)
        harness.model.stop()
        #expect(!harness.assertion.isHeld)
        #expect(harness.assertion.releaseCount == 1)
        #expect(harness.model.status == .idle)
        #expect(harness.detector.stopCount == 1)
        harness.detector.simulate(playing: true)
        harness.scheduler.advance(by: 10)
        #expect(harness.model.status == .idle)
    }

    @Test func refreshAsksTheDetectorToRereadTheState() {
        let harness = Harness()
        harness.model.refresh()
        #expect(harness.detector.refreshCount == 1)
    }
}
```

- [ ] Step 3: Run the tests to verify they fail

Run: `/usr/bin/swift test --filter SleeplessCoreTests 2>&1 | /usr/bin/tail -5`
Expected: build failure, `cannot find type 'AppStatus' in scope`.

- [ ] Step 4: Implement `Sources/SleeplessCore/AppModel.swift`

```swift
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
```

- [ ] Step 5: Run the tests to verify they pass

Run: `/usr/bin/swift test --filter SleeplessCoreTests 2>&1 | /usr/bin/tail -3`
Expected: `✔ Test run with 28 tests passed`.

- [ ] Step 6: Format and lint. Expected: exit 0.

Suggested commit: `feat: add app model wiring detection, delays and assertion`

---

### Task 7: Launch at Login

Files:
- Create: `Sources/SleeplessCore/LoginItem.swift`
- Test: `Tests/SleeplessCoreTests/LoginItemTests.swift`
- Test: `Tests/SleeplessIntegrationTests/SMAppServiceLoginItemTests.swift`

- [ ] Step 1: Write the failing unit tests `Tests/SleeplessCoreTests/LoginItemTests.swift`

```swift
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
```

- [ ] Step 2: Write the failing integration tests `Tests/SleeplessIntegrationTests/SMAppServiceLoginItemTests.swift`

```swift
import Testing

@testable import SleeplessCore

@MainActor
struct SMAppServiceLoginItemTests {
    @Test func unbundledProcessReportsUnavailable() {
        #expect(SMAppServiceLoginItem(isBundled: false).status == .unavailable)
    }

    @Test func readingTheRealStatusHasNoSideEffect() {
        let item = SMAppServiceLoginItem(isBundled: true)
        let first = item.status
        let second = item.status
        #expect(first == second)
    }
}
```

- [ ] Step 3: Run the tests to verify they fail

Run: `/usr/bin/swift test 2>&1 | /usr/bin/tail -5`
Expected: build failure, `cannot find 'SMAppServiceLoginItem' in scope`.

- [ ] Step 4: Implement `Sources/SleeplessCore/LoginItem.swift`

```swift
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
```

- [ ] Step 5: Run all tests to verify they pass

Run: `/usr/bin/swift test 2>&1 | /usr/bin/tail -3`
Expected: `✔ Test run with 44 tests passed` (33 unit, 11 integration). The CoreAudio suite's 3 tests are skipped on a machine without an output device; there must be 0 failures.

- [ ] Step 6: Format and lint. Expected: exit 0.

Suggested commit: `feat: add launch at login through SMAppService`

---

### Task 8: Status presentation and build info

Files:
- Create: `Sources/SleeplessCore/StatusPresentation.swift`
- Test: `Tests/SleeplessCoreTests/StatusPresentationTests.swift`

- [ ] Step 1: Write the failing tests `Tests/SleeplessCoreTests/StatusPresentationTests.swift`

```swift
import Testing

@testable import SleeplessCore

struct StatusPresentationTests {
    @Test func idleShowsTheMonochromeMoon() {
        #expect(
            StatusPresentation.make(for: .idle)
                == StatusPresentation(
                    symbolName: "moon.zzz",
                    isTinted: false,
                    statusText: "No audio playing, Mac can sleep",
                    accessibilityLabel: "Sleepless: Mac can sleep"
                )
        )
    }

    @Test func playingShowsTheTintedNote() {
        #expect(
            StatusPresentation.make(for: .playing)
                == StatusPresentation(
                    symbolName: "music.note",
                    isTinted: true,
                    statusText: "Audio playing, keeping Mac awake",
                    accessibilityLabel: "Sleepless: keeping Mac awake"
                )
        )
    }

    @Test func holdingStillShowsTheTintedNote() {
        #expect(
            StatusPresentation.make(for: .holding)
                == StatusPresentation(
                    symbolName: "music.note",
                    isTinted: true,
                    statusText: "Audio stopped, keeping Mac awake for a moment",
                    accessibilityLabel: "Sleepless: keeping Mac awake"
                )
        )
    }

    @Test func failureShowsTheMoonAndTheErrorInHex() {
        #expect(
            StatusPresentation.make(for: .failed(code: Int32(bitPattern: 0xE000_02C2)))
                == StatusPresentation(
                    symbolName: "moon.zzz",
                    isTinted: false,
                    statusText: "Could not prevent sleep (error 0xE00002C2)",
                    accessibilityLabel: "Sleepless: Mac can sleep"
                )
        )
    }
}

struct BuildInfoTests {
    @Test func releaseTooltipShowsOnlyTheVersion() {
        #expect(BuildInfo(version: "0.1.0", channel: "release", commit: "abc1234").tooltip == "Sleepless 0.1.0")
    }

    @Test(arguments: ["dev", "rc", "local"])
    func otherChannelsShowChannelAndCommit(channel: String) {
        #expect(
            BuildInfo(version: "0.0.0", channel: channel, commit: "abc1234").tooltip
                == "Sleepless 0.0.0 (\(channel) abc1234)"
        )
    }

    @Test func unbundledTooltip() {
        #expect(BuildInfo(infoDictionary: nil).tooltip == "Sleepless (unbundled)")
    }

    @Test func readsInfoPlistKeys() {
        let info: [String: Any] = [
            "CFBundleShortVersionString": "0.2.0",
            "SleeplessBuildChannel": "rc",
            "SleeplessBuildCommit": "def5678",
        ]
        #expect(BuildInfo(infoDictionary: info) == BuildInfo(version: "0.2.0", channel: "rc", commit: "def5678"))
    }

    @Test func missingKeysFallBackToLocalAndUnknown() {
        let info: [String: Any] = ["CFBundleShortVersionString": "0.2.0"]
        #expect(BuildInfo(infoDictionary: info) == BuildInfo(version: "0.2.0", channel: "local", commit: "unknown"))
    }
}
```

- [ ] Step 2: Run the tests to verify they fail

Run: `/usr/bin/swift test --filter SleeplessCoreTests 2>&1 | /usr/bin/tail -5`
Expected: build failure, `cannot find 'StatusPresentation' in scope`.

- [ ] Step 3: Implement `Sources/SleeplessCore/StatusPresentation.swift`

```swift
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
```

- [ ] Step 4: Run the tests to verify they pass

Run: `/usr/bin/swift test --filter SleeplessCoreTests 2>&1 | /usr/bin/tail -3`
Expected: `✔ Test run with 42 tests passed` and 0 failures.

- [ ] Step 5: Format and lint. Expected: exit 0.

Suggested commit: `feat: add status presentation and build info`

---

### Task 9: AppKit app

Files:
- Modify: `Package.swift` (final form)
- Create: `Sources/Sleepless/main.swift`, `Sources/Sleepless/AppDelegate.swift`, `Sources/Sleepless/StatusItemController.swift`

- [ ] Step 1: Replace `Package.swift`

```swift
// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "Sleepless",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "Sleepless", targets: ["Sleepless"])
    ],
    targets: [
        .target(name: "SleeplessCore"),
        .executableTarget(name: "Sleepless", dependencies: ["SleeplessCore"]),
        .testTarget(name: "SleeplessCoreTests", dependencies: ["SleeplessCore"]),
        .testTarget(name: "SleeplessIntegrationTests", dependencies: ["SleeplessCore"]),
    ]
)
```

- [ ] Step 2: Create `Sources/Sleepless/main.swift`

```swift
import AppKit

MainActor.assumeIsolated {
    let application = NSApplication.shared
    let delegate = AppDelegate()
    application.delegate = delegate
    application.setActivationPolicy(.accessory)
    withExtendedLifetime(delegate) {
        application.run()
    }
}
```

- [ ] Step 3: Create `Sources/Sleepless/StatusItemController.swift`

```swift
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
```

- [ ] Step 4: Create `Sources/Sleepless/AppDelegate.swift`

```swift
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
```

- [ ] Step 5: Build

Run: `/usr/bin/swift build 2>&1 | /usr/bin/tail -3`
Expected: `Build complete!` with no errors. Concurrency diagnostics to expect and how to fix them:
  - If a closure passed to `addObserver` or `setEventHandler` is rejected as non-Sendable, add `@Sendable` before its capture list or parameters.
  - If `StatusItemController`'s stored property initializer is rejected as main-actor isolated, move the `statusItem` creation into `init` before `super.init()`.

- [ ] Step 6: Manual check unbundled (owner watches the menu bar)

Run: `/usr/bin/swift run Sleepless -startDelay 1 -stopDelay 5` (in a second terminal or in the background), then play audio for 3 s and stop.
Expected:
  - The `moon.zzz` icon turns into a `music.note` in the accent color about 1 s after playback starts.
  - The icon turns back into the moon about 5 s after playback stops.
  - The menu shows the matching status line, a disabled Launch at Login item and Quit Sleepless.
  - `/usr/bin/pmset -g assertions | /usr/bin/grep -i sleepless` shows the assertion only while the note is shown.
  - Quit with Cmd-Q from the menu.

- [ ] Step 7: Format and lint. Expected: exit 0. Run all tests again: `/usr/bin/swift test 2>&1 | /usr/bin/tail -1`, 0 failures.

Suggested commit: `feat: add menu bar app`

---

### Task 10: Bundle resources and icon

Files:
- Create: `Resources/Info.plist`, `Scripts/make-icon.swift`
- Create (generated): `Resources/AppIcon.icns`

- [ ] Step 1: Create `Resources/Info.plist` (placeholders are replaced by Scripts/build-app.sh)

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleDevelopmentRegion</key>
	<string>en</string>
	<key>CFBundleDisplayName</key>
	<string>Sleepless</string>
	<key>CFBundleExecutable</key>
	<string>Sleepless</string>
	<key>CFBundleIconFile</key>
	<string>AppIcon</string>
	<key>CFBundleIdentifier</key>
	<string>io.github.davidferlay.Sleepless</string>
	<key>CFBundleInfoDictionaryVersion</key>
	<string>6.0</string>
	<key>CFBundleName</key>
	<string>Sleepless</string>
	<key>CFBundlePackageType</key>
	<string>APPL</string>
	<key>CFBundleShortVersionString</key>
	<string>__VERSION__</string>
	<key>CFBundleVersion</key>
	<string>__BUILD_NUMBER__</string>
	<key>LSApplicationCategoryType</key>
	<string>public.app-category.utilities</string>
	<key>LSMinimumSystemVersion</key>
	<string>13.0</string>
	<key>LSUIElement</key>
	<true/>
	<key>NSHumanReadableCopyright</key>
	<string>Copyright 2026 davidferlay. Licensed under GPL-3.0.</string>
	<key>SleeplessBuildChannel</key>
	<string>__CHANNEL__</string>
	<key>SleeplessBuildCommit</key>
	<string>__COMMIT__</string>
</dict>
</plist>
```

- [ ] Step 2: Create `Scripts/make-icon.swift`

```swift
// Renders Resources/AppIcon.icns from the moon.zzz SF Symbol.
// Usage: /usr/bin/swift Scripts/make-icon.swift Resources/AppIcon.icns
import AppKit

let output = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "Resources/AppIcon.icns"
let iconset = URL(fileURLWithPath: NSTemporaryDirectory())
    .appendingPathComponent("Sleepless-\(UUID().uuidString).iconset")
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

func renderIcon(size: Int) -> Data {
    let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: size,
        pixelsHigh: size,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    )!
    bitmap.size = NSSize(width: size, height: size)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)

    // macOS icon grid: an 824 pt rounded square centered on a 1024 pt canvas.
    let side = CGFloat(size)
    let inset = side * 100 / 1024
    let body = NSRect(x: inset, y: inset, width: side - 2 * inset, height: side - 2 * inset)
    let shape = NSBezierPath(roundedRect: body, xRadius: body.width * 0.225, yRadius: body.width * 0.225)
    let night = NSGradient(
        starting: NSColor(calibratedRed: 0.20, green: 0.22, blue: 0.48, alpha: 1),
        ending: NSColor(calibratedRed: 0.05, green: 0.06, blue: 0.17, alpha: 1)
    )!
    night.draw(in: shape, angle: -90)

    let configuration = NSImage.SymbolConfiguration(pointSize: body.width * 0.45, weight: .medium)
        .applying(NSImage.SymbolConfiguration(paletteColors: [.white]))
    if let symbol = NSImage(systemSymbolName: "moon.zzz", accessibilityDescription: nil)?
        .withSymbolConfiguration(configuration)
    {
        let symbolSize = symbol.size
        symbol.draw(
            in: NSRect(
                x: body.midX - symbolSize.width / 2,
                y: body.midY - symbolSize.height / 2,
                width: symbolSize.width,
                height: symbolSize.height
            )
        )
    }

    NSGraphicsContext.restoreGraphicsState()
    return bitmap.representation(using: .png, properties: [:])!
}

let sizes: [(name: String, pixels: Int)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32),
    ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256),
    ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024),
]
for entry in sizes {
    try renderIcon(size: entry.pixels).write(to: iconset.appendingPathComponent("\(entry.name).png"))
}

let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", output]
try iconutil.run()
iconutil.waitUntilExit()
try? FileManager.default.removeItem(at: iconset)
guard iconutil.terminationStatus == 0 else {
    FileHandle.standardError.write(Data("iconutil failed\n".utf8))
    exit(1)
}
print("Wrote \(output)")
```

- [ ] Step 3: Generate the icon and check it

Run: `/bin/mkdir -p Resources && make icon && /usr/bin/file Resources/AppIcon.icns && /usr/bin/sips -g pixelWidth Resources/AppIcon.icns`
Expected: `Wrote Resources/AppIcon.icns`, `Mac OS X icon`, `pixelWidth: 1024`. If the interpreter (`swift file.swift`) fails, compile instead: `/usr/bin/swiftc Scripts/make-icon.swift -o .build/make-icon && .build/make-icon Resources/AppIcon.icns`, and change the Makefile `icon` target the same way.

- [ ] Step 4: Look at the icon (owner)

Run: `/usr/bin/qlmanage -p Resources/AppIcon.icns`
Expected: a white moon with "zzz" on a dark blue rounded square.

- [ ] Step 5: Check Info.plist syntax, format and lint Swift

Run: `/usr/bin/plutil -lint Resources/Info.plist && make format && /usr/bin/swift format lint --strict --recursive Package.swift Sources Tests Scripts/make-icon.swift`
Expected: `Resources/Info.plist: OK`, then exit 0.

Suggested commit: `feat: add bundle metadata and generated app icon`

---

### Task 11: Build, validate and package scripts

Files:
- Create: `Scripts/build-app.sh`, `Scripts/validate-bundle.sh`, `Scripts/package.sh`

- [ ] Step 1: Create `Scripts/build-app.sh`

```sh
#!/bin/sh
# Builds build/Sleepless.app with SwiftPM and the Command Line Tools (Xcode not required).
#
# Environment (all optional):
#   VERSION       CFBundleShortVersionString, default 0.0.0
#   BUILD_NUMBER  CFBundleVersion, default the commit count
#   CHANNEL       release, rc, dev or local, default local
#   ARCHS         architectures to build, default "arm64 x86_64"
#   OUTPUT_DIR    default build
set -eu

ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
cd "$ROOT"

VERSION=${VERSION:-0.0.0}
BUILD_NUMBER=${BUILD_NUMBER:-$(/usr/bin/git rev-list --count HEAD 2>/dev/null || echo 1)}
CHANNEL=${CHANNEL:-local}
COMMIT=$(/usr/bin/git rev-parse --short HEAD 2>/dev/null || echo unknown)
ARCHS=${ARCHS:-arm64 x86_64}
OUTPUT_DIR=${OUTPUT_DIR:-build}
APP="$OUTPUT_DIR/Sleepless.app"

case "$CHANNEL" in
    release | rc | dev | local) ;;
    *)
        echo "error: CHANNEL must be release, rc, dev or local (got '$CHANNEL')" >&2
        exit 1
        ;;
esac

binaries=""
for arch in $ARCHS; do
    echo "==> Building $arch"
    /usr/bin/swift build -c release --product Sleepless --triple "$arch-apple-macosx13.0"
    binaries="$binaries .build/$arch-apple-macosx/release/Sleepless"
done

echo "==> Assembling $APP"
/bin/rm -rf "$APP"
/bin/mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
# shellcheck disable=SC2086 # the binary list is split on purpose; the paths contain no spaces
/usr/bin/lipo -create $binaries -output "$APP/Contents/MacOS/Sleepless"
/usr/bin/sed \
    -e "s/__VERSION__/$VERSION/g" \
    -e "s/__BUILD_NUMBER__/$BUILD_NUMBER/g" \
    -e "s/__CHANNEL__/$CHANNEL/g" \
    -e "s/__COMMIT__/$COMMIT/g" \
    Resources/Info.plist >"$APP/Contents/Info.plist"
/usr/bin/plutil -lint "$APP/Contents/Info.plist" >/dev/null
/usr/bin/printf 'APPL????' >"$APP/Contents/PkgInfo"
/bin/cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

echo "==> Signing (ad-hoc)"
/usr/bin/codesign --force --sign - --timestamp=none "$APP"

echo "Built $APP ($VERSION, build $BUILD_NUMBER, $CHANNEL $COMMIT, $(/usr/bin/lipo -archs "$APP/Contents/MacOS/Sleepless"))"
```

- [ ] Step 2: Create `Scripts/validate-bundle.sh`

```sh
#!/bin/sh
# Checks that the built app bundle is well formed, signed and universal.
# Usage: Scripts/validate-bundle.sh [path to Sleepless.app]
# Environment: EXPECTED_VERSION (optional), EXPECTED_ARCHS (default "arm64 x86_64").
set -eu

APP=${1:-build/Sleepless.app}
EXPECTED_ARCHS=${EXPECTED_ARCHS:-arm64 x86_64}
PLIST="$APP/Contents/Info.plist"
BINARY="$APP/Contents/MacOS/Sleepless"
failures=0

pass() {
    echo "ok   $1"
}

fail() {
    echo "FAIL $1"
    failures=$((failures + 1))
}

expect_equal() {
    if [ "$2" = "$3" ]; then
        pass "$1"
    else
        fail "$1 (got '$2', expected '$3')"
    fi
}

plist_value() {
    /usr/bin/plutil -extract "$1" raw -o - "$PLIST" 2>/dev/null || echo "<missing>"
}

if [ ! -d "$APP" ]; then
    echo "error: $APP not found, run make app first" >&2
    exit 1
fi

if /usr/bin/plutil -lint "$PLIST" >/dev/null; then pass "Info.plist is valid"; else fail "Info.plist is valid"; fi
expect_equal "bundle identifier" "$(plist_value CFBundleIdentifier)" io.github.davidferlay.Sleepless
expect_equal "executable name" "$(plist_value CFBundleExecutable)" Sleepless
expect_equal "LSUIElement" "$(plist_value LSUIElement)" true
expect_equal "minimum macOS" "$(plist_value LSMinimumSystemVersion)" 13.0
if [ -n "${EXPECTED_VERSION:-}" ]; then
    expect_equal "version" "$(plist_value CFBundleShortVersionString)" "$EXPECTED_VERSION"
fi
case "$(plist_value SleeplessBuildChannel)" in
    release | rc | dev | local) pass "build channel" ;;
    *) fail "build channel" ;;
esac
if /usr/bin/grep -q '__[A-Z_]*__' "$PLIST"; then
    fail "no unsubstituted placeholders"
else
    pass "no unsubstituted placeholders"
fi
expect_equal "PkgInfo" "$(/bin/cat "$APP/Contents/PkgInfo" 2>/dev/null || true)" 'APPL????'
if [ -s "$APP/Contents/Resources/AppIcon.icns" ]; then pass "app icon"; else fail "app icon"; fi

archs=$(/usr/bin/lipo -archs "$BINARY" 2>/dev/null || true)
for arch in $EXPECTED_ARCHS; do
    case " $archs " in
        *" $arch "*) pass "architecture $arch" ;;
        *) fail "architecture $arch (binary has: $archs)" ;;
    esac
done
for arch in $archs; do
    minos=$(/usr/bin/vtool -arch "$arch" -show-build "$BINARY" 2>/dev/null | /usr/bin/awk '/minos/ { print $2 }')
    expect_equal "minimum OS of the $arch slice" "$minos" 13.0
done

if /usr/bin/codesign --verify --strict --verbose=2 "$APP" 2>/dev/null; then
    pass "code signature"
else
    fail "code signature"
fi

non_system=$(/usr/bin/otool -L "$BINARY" | /usr/bin/awk 'NR > 1 && !/:$/ { print $1 }' |
    /usr/bin/grep -v -E '^(/usr/lib/|/System/Library/)' || true)
if [ -z "$non_system" ]; then
    pass "links only system libraries"
else
    fail "links only system libraries (also: $non_system)"
fi

if [ "$failures" -gt 0 ]; then
    echo "$failures check(s) failed"
    exit 1
fi
echo "All bundle checks passed"
```

- [ ] Step 3: Create `Scripts/package.sh`

```sh
#!/bin/sh
# Packages build/Sleepless.app into Sleepless-<version>.dmg, Sleepless-<version>.zip and SHA256SUMS.txt.
# Usage: Scripts/package.sh <version>
set -eu

ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
cd "$ROOT"

VERSION=${1:?usage: Scripts/package.sh <version>}
OUTPUT_DIR=${OUTPUT_DIR:-build}
APP="$OUTPUT_DIR/Sleepless.app"
DMG="$OUTPUT_DIR/Sleepless-$VERSION.dmg"
ZIP="$OUTPUT_DIR/Sleepless-$VERSION.zip"
STAGING="$OUTPUT_DIR/dmg-staging"

if [ ! -d "$APP" ]; then
    echo "error: $APP not found, run make app first" >&2
    exit 1
fi

/bin/rm -rf "$STAGING" "$DMG" "$ZIP" "$OUTPUT_DIR/SHA256SUMS.txt"
/bin/mkdir -p "$STAGING"
/usr/bin/ditto "$APP" "$STAGING/Sleepless.app"
/bin/ln -s /Applications "$STAGING/Applications"

# hdiutil occasionally fails with "Resource busy" on CI runners; retry a few times.
attempt=1
until /usr/bin/hdiutil create -volname "Sleepless $VERSION" -srcfolder "$STAGING" -fs HFS+ -format UDZO -ov "$DMG"; do
    if [ "$attempt" -ge 3 ]; then
        echo "error: hdiutil failed $attempt times" >&2
        exit 1
    fi
    attempt=$((attempt + 1))
    echo "hdiutil failed, retrying ($attempt/3)"
    sleep 5
done
/bin/rm -rf "$STAGING"

/usr/bin/ditto -c -k --keepParent "$APP" "$ZIP"
(cd "$OUTPUT_DIR" && /usr/bin/shasum -a 256 "Sleepless-$VERSION.dmg" "Sleepless-$VERSION.zip" >SHA256SUMS.txt)
/bin/cat "$OUTPUT_DIR/SHA256SUMS.txt"
```

- [ ] Step 4: Make the scripts executable, build and validate

Run: `/bin/chmod +x Scripts/*.sh && make app && make validate`
Expected: `Built build/Sleepless.app (0.0.0, build 1, local unknown, x86_64 arm64)` (commit shows `unknown` until the first commit), then `ok` lines and `All bundle checks passed`.

- [ ] Step 5: Check that validation catches a broken bundle

Run: `EXPECTED_VERSION=9.9.9 make validate; echo "exit $?"`
Expected: `FAIL version (got '0.0.0', expected '9.9.9')`, `1 check(s) failed`, a non-zero exit.

- [ ] Step 6: Package

Run: `make package VERSION=0.0.0 && /bin/ls -la build/`
Expected: `Sleepless-0.0.0.dmg`, `Sleepless-0.0.0.zip`, `SHA256SUMS.txt` with two lines.

- [ ] Step 7: Launch the bundled app once (owner)

Run: `/usr/bin/open build/Sleepless.app`
Expected: the moon icon appears; hovering shows `Sleepless 0.0.0 (local unknown)`; Launch at Login is enabled and clickable. Do not enable Launch at Login for the copy in `build/`. Quit from the menu.

Suggested commit: `build: add app bundle, validation and packaging scripts`

---

### Task 12: Smoke and end-to-end tests

Files:
- Create: `Scripts/smoke-test.sh`, `Scripts/e2e-playback.sh`

- [ ] Step 1: Create `Scripts/smoke-test.sh`

```sh
#!/bin/sh
# Smoke test: the app starts, stays up, logs its start, and quits cleanly on SIGTERM.
# Usage: Scripts/smoke-test.sh [path to Sleepless.app]
set -eu

APP=${1:-build/Sleepless.app}
BINARY="$APP/Contents/MacOS/Sleepless"
SUBSYSTEM=io.github.davidferlay.Sleepless

fail() {
    echo "FAIL $1" >&2
    exit 1
}

# True while the process exists and is not a zombie.
is_running() {
    state=$(/bin/ps -p "$1" -o stat= 2>/dev/null || true)
    [ -n "$state" ] && [ "${state#Z}" = "$state" ]
}

# Waits up to $1 seconds for a log message of this run that contains $2.
wait_for_log() {
    remaining=$1
    while [ "$remaining" -gt 0 ]; do
        if /usr/bin/log show --style compact --start "$START" \
            --predicate "subsystem == \"$SUBSYSTEM\" AND processIdentifier == $pid" 2>/dev/null |
            /usr/bin/grep -q -F "$2"; then
            return 0
        fi
        sleep 1
        remaining=$((remaining - 1))
    done
    return 1
}

[ -x "$BINARY" ] || fail "$BINARY not found, run make app first"

START=$(/bin/date '+%Y-%m-%d %H:%M:%S')
"$BINARY" &
pid=$!
trap 'kill "$pid" 2>/dev/null || true' EXIT

sleep 5
is_running "$pid" || fail "the app exited within 5 s of launch"
echo "ok   still running after 5 s (pid $pid)"

wait_for_log 10 "Sleepless started" || fail "'Sleepless started' was not logged"
echo "ok   start logged"

kill -TERM "$pid"
waited=0
while is_running "$pid"; do
    [ "$waited" -lt 5 ] || fail "still running 5 s after SIGTERM"
    sleep 1
    waited=$((waited + 1))
done
status=0
wait "$pid" || status=$?
[ "$status" -eq 0 ] || fail "exit status $status after SIGTERM"
echo "ok   exited with status 0 after SIGTERM"

wait_for_log 10 "Sleepless stopped" || fail "'Sleepless stopped' was not logged"
echo "ok   stop logged"

crash=$(/usr/bin/find "$HOME/Library/Logs/DiagnosticReports" -name 'Sleepless*' -newer "$APP/Contents/Info.plist" \
    2>/dev/null | /usr/bin/head -1)
[ -z "$crash" ] || fail "crash report found: $crash"
echo "ok   no crash report"

trap - EXIT
echo "Smoke test passed"
```

- [ ] Step 2: Run the smoke test

Run: `/bin/chmod +x Scripts/smoke-test.sh && make smoke`
Expected: five `ok` lines and `Smoke test passed`.

- [ ] Step 3: Check the exact `pmset` line format the end-to-end test relies on

Run: `/usr/bin/swift run Sleepless -startDelay 1 -stopDelay 30 &` then play any audio for 3 s, then `/usr/bin/pmset -g assertions | /usr/bin/grep -i sleepless`, then `kill %1`.
Expected: a line containing `pid <number>(Sleepless)` and `PreventUserIdleSystemSleep named: "Sleepless: audio playback"`. If the format differs, adjust `has_assertion` in Step 4 to match it.

- [ ] Step 4: Create `Scripts/e2e-playback.sh`

```sh
#!/bin/sh
# End-to-end: real audio playback makes Sleepless hold its power assertion, and the assertion is
# released after the hold. Exits 0 with a notice when the machine has no default audio output device.
# Usage: Scripts/e2e-playback.sh [path to Sleepless.app]
set -eu

APP=${1:-build/Sleepless.app}
BINARY="$APP/Contents/MacOS/Sleepless"
ASSERTION_NAME="Sleepless: audio playback"
START_DELAY=1
STOP_DELAY=4
TONE_SECONDS=6

notice() {
    if [ -n "${GITHUB_ACTIONS:-}" ]; then
        echo "::notice title=End-to-end playback test::$1"
    else
        echo "$1"
    fi
}

fail() {
    echo "FAIL $1" >&2
    exit 1
}

has_assertion() {
    /usr/bin/pmset -g assertions | /usr/bin/grep -i -F "pid $pid(Sleepless)" |
        /usr/bin/grep -q -F "\"$ASSERTION_NAME\""
}

# shellcheck disable=SC2317 # called indirectly through wait_until
has_no_assertion() {
    ! has_assertion
}

# Runs the command "$2 ..." every 0.5 s for up to $1 seconds until it succeeds.
wait_until() {
    tries=$(($1 * 2))
    shift
    while [ "$tries" -gt 0 ]; do
        if "$@"; then
            return 0
        fi
        sleep 0.5
        tries=$((tries - 1))
    done
    return 1
}

[ -x "$BINARY" ] || fail "$BINARY not found, run make app first"

if ! /usr/sbin/system_profiler SPAudioDataType 2>/dev/null | /usr/bin/grep -q "Default Output Device: Yes"; then
    notice "No default audio output device on this machine, skipping the end-to-end playback test"
    exit 0
fi

WORK_DIR=$(/usr/bin/mktemp -d)
TONE="$WORK_DIR/tone.wav"
/usr/bin/python3 - "$TONE" "$TONE_SECONDS" <<'EOF'
import math
import struct
import sys
import wave

path, seconds = sys.argv[1], int(sys.argv[2])
rate = 44100
frames = b"".join(
    struct.pack("<h", int(1000 * math.sin(2 * math.pi * 440 * i / rate))) for i in range(rate * seconds)
)
with wave.open(path, "wb") as tone:
    tone.setnchannels(1)
    tone.setsampwidth(2)
    tone.setframerate(rate)
    tone.writeframes(frames)
EOF

"$BINARY" -startDelay "$START_DELAY" -stopDelay "$STOP_DELAY" &
pid=$!
player=""
# shellcheck disable=SC2317 # called by the EXIT trap
cleanup() {
    if [ -n "$player" ]; then
        kill "$player" 2>/dev/null || true
    fi
    kill "$pid" 2>/dev/null || true
    /bin/rm -rf "$WORK_DIR"
}
trap cleanup EXIT

sleep $((START_DELAY + 2))
if has_assertion; then
    fail "the assertion is held before the test plays anything: other audio is playing on this Mac, stop it and re-run"
fi
echo "ok   no assertion while nothing plays"

/usr/bin/afplay -v 0.3 "$TONE" &
player=$!
wait_until 5 has_assertion || fail "no assertion within 5 s of playback starting"
echo "ok   assertion held during playback"

wait "$player" || true
player=""
sleep 1
has_assertion || fail "assertion gone less than 1 s after playback stopped (stop delay is $STOP_DELAY s)"
echo "ok   assertion still held right after playback (hold)"

wait_until $((STOP_DELAY + 5)) has_no_assertion || fail "assertion still held $((STOP_DELAY + 5)) s after playback"
echo "ok   assertion released after the hold"

echo "End-to-end playback test passed"
```

- [ ] Step 5: Run the end-to-end test (a quiet 440 Hz tone plays for 6 s; nothing else may be playing)

Run: `/bin/chmod +x Scripts/e2e-playback.sh && make e2e`
Expected: four `ok` lines and `End-to-end playback test passed`.

- [ ] Step 6: Check the skip path

Run: `S=/private/tmp/claude-501/-Users-john-Sources-KeepingYouAwake/2163f658-6cf0-466c-a885-237630058241/scratchpad && /usr/bin/sed 's/Default Output Device: Yes/Default Output Device: Never/' Scripts/e2e-playback.sh > "$S/e2e-skip.sh" && /bin/sh "$S/e2e-skip.sh" build/Sleepless.app; echo "exit $?"; /bin/rm "$S/e2e-skip.sh"`
Expected: `No default audio output device on this machine, skipping ...` and `exit 0`.

Suggested commit: `test: add smoke and end-to-end playback tests`

---

### Task 13: Lint, coverage and pre-commit hook

Files:
- Create: `Scripts/lint.sh`, `Scripts/coverage-summary.sh`, `.githooks/pre-commit`

- [ ] Step 1: Create `Scripts/lint.sh`

```sh
#!/bin/sh
# Static checks: Swift formatting, Info.plist, shell scripts, workflows.
# shellcheck and actionlint are optional locally and required in CI (CI=true).
set -eu

ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
cd "$ROOT"

status=0

run() {
    echo "==> $*"
    if ! "$@"; then
        status=1
    fi
}

optional_tool() {
    tool=$1
    shift
    if command -v "$tool" >/dev/null 2>&1; then
        run "$tool" "$@"
    elif [ "${CI:-}" = true ]; then
        echo "error: $tool is required in CI" >&2
        status=1
    else
        echo "==> $tool not installed, skipped (install with: brew install $tool)"
    fi
}

run /usr/bin/swift format lint --strict --recursive Package.swift Sources Tests Scripts/make-icon.swift
run /usr/bin/plutil -lint Resources/Info.plist
optional_tool shellcheck Scripts/*.sh .githooks/pre-commit
optional_tool actionlint

exit "$status"
```

- [ ] Step 2: Create `Scripts/coverage-summary.sh`

```sh
#!/bin/sh
# Prints line coverage of SleeplessCore from the last `swift test --enable-code-coverage` run and,
# in GitHub Actions, adds it to the job summary.
set -eu

ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
cd "$ROOT"

BIN_PATH=$(/usr/bin/swift build --show-bin-path)
PROFDATA="$BIN_PATH/codecov/default.profdata"
TEST_BINARY="$BIN_PATH/SleeplessPackageTests.xctest/Contents/MacOS/SleeplessPackageTests"

if [ ! -f "$PROFDATA" ]; then
    echo "error: $PROFDATA not found, run make coverage" >&2
    exit 1
fi

REPORT=$(/usr/bin/xcrun llvm-cov report "$TEST_BINARY" -instr-profile "$PROFDATA" Sources/SleeplessCore)
echo "$REPORT"

if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
    {
        echo "### Unit test coverage (SleeplessCore)"
        echo
        echo '```'
        echo "$REPORT"
        echo '```'
    } >>"$GITHUB_STEP_SUMMARY"
fi
```

- [ ] Step 3: Create `.githooks/pre-commit`

```sh
#!/bin/sh
# Pre-commit: swift format lint on staged Swift files, then a debug build.
# Enable once per clone with: make install-hooks
set -eu

files=$(/usr/bin/git diff --cached --name-only --diff-filter=ACM -- '*.swift')
if [ -n "$files" ]; then
    echo "Running swift format lint on staged Swift files..."
    # shellcheck disable=SC2086 # one path per word; repository paths contain no spaces
    if ! /usr/bin/swift format lint --strict $files; then
        echo "swift format lint failed. Run 'make format' and stage the changes." >&2
        exit 1
    fi
fi

echo "Running swift build..."
if ! /usr/bin/swift build; then
    echo "swift build failed. Fix the errors before committing." >&2
    exit 1
fi

echo "Pre-commit checks passed."
```

- [ ] Step 4: Make them executable and run

Run: `/bin/chmod +x Scripts/lint.sh Scripts/coverage-summary.sh .githooks/pre-commit && make lint && make coverage`
Expected:
  - `make lint`: the swift-format and plutil steps pass, and shellcheck and actionlint are reported as skipped locally.
  - `make coverage`: a table that lists each `Sources/SleeplessCore/*.swift` file and a TOTAL line. `ActivationController.swift`, `Settings.swift`, `AppModel.swift` and `StatusPresentation.swift` are near 100 %; `PlaybackDetector.swift` and `SleepAssertion.swift` are low (integration-tested).
  - If `llvm-cov` reports no files for the `Sources/SleeplessCore` filter, replace it with `-ignore-filename-regex '(\.build|Tests)/'`.

- [ ] Step 5: Install the hook and dry-run it against a throwaway index (the real index and any commits stay untouched)

Run: `make install-hooks && I=/private/tmp/claude-501/-Users-john-Sources-KeepingYouAwake/2163f658-6cf0-466c-a885-237630058241/scratchpad/hook-index && /bin/rm -f "$I" && GIT_INDEX_FILE="$I" /usr/bin/git add -A && GIT_INDEX_FILE="$I" .githooks/pre-commit; /bin/rm -f "$I"`
Expected: `Running swift format lint on staged Swift files...`, `Running swift build...`, `Pre-commit checks passed.`

Suggested commit: `build: add lint, coverage summary and pre-commit hook`

---

### Task 14: GitHub workflows

Files:
- Create: `.github/workflows/ci.yml`, `.github/workflows/build.yml`, `.github/workflows/release.yml`, `.github/workflows/prerelease.yml`, `.github/dependabot.yml`

- [ ] Step 1: Create `.github/workflows/ci.yml`

```yaml
name: CI

on:
  push:
    branches: ['**']
    paths:
      - 'Package.swift'
      - 'Sources/**'
      - 'Tests/**'
      - 'Resources/**'
      - 'Scripts/**'
      - 'Makefile'
      - '.swift-format'
      - '.githooks/**'
      - '.github/workflows/**'
  pull_request:
    branches: [main]
    paths:
      - 'Package.swift'
      - 'Sources/**'
      - 'Tests/**'
      - 'Resources/**'
      - 'Scripts/**'
      - 'Makefile'
      - '.swift-format'
      - '.githooks/**'
      - '.github/workflows/**'

concurrency:
  group: ci-${{ github.ref }}
  cancel-in-progress: true

permissions:
  contents: read

jobs:
  lint:
    name: Lint
    runs-on: macos-latest
    steps:
      - name: Checkout repository
        uses: actions/checkout@v7

      - name: Show toolchain
        run: |
          /usr/bin/xcodebuild -version
          /usr/bin/swift --version

      # Not preinstalled on the macOS runner images.
      - name: Install shellcheck and actionlint
        run: brew install shellcheck actionlint

      - name: Lint
        run: make lint

  unit-tests:
    name: Unit Tests
    runs-on: macos-latest
    steps:
      - name: Checkout repository
        uses: actions/checkout@v7

      - name: Show toolchain
        run: /usr/bin/swift --version

      - name: Run unit tests with coverage
        run: make coverage

  integration-tests:
    name: Integration Tests
    runs-on: macos-latest
    steps:
      - name: Checkout repository
        uses: actions/checkout@v7

      - name: Show toolchain
        run: /usr/bin/swift --version

      - name: Run integration tests
        run: make test-integration

  app:
    name: App (${{ matrix.runner }})
    strategy:
      fail-fast: false
      matrix:
        # macos-latest: current macOS on Apple silicon. macos-15: oldest macOS still offered.
        # macos-15-intel: runs the x86_64 slice of the universal binary.
        runner: [macos-latest, macos-15, macos-15-intel]
    runs-on: ${{ matrix.runner }}
    env:
      CHANNEL: dev
      BUILD_NUMBER: ${{ github.run_number }}
    steps:
      - name: Checkout repository
        uses: actions/checkout@v7

      - name: Show system and toolchain
        run: |
          /usr/bin/sw_vers
          /usr/bin/uname -m
          /usr/bin/swift --version

      - name: Build universal app
        run: make app

      - name: Validate bundle
        run: make validate

      - name: Smoke test
        run: make smoke

      - name: End-to-end playback test
        run: make e2e

      - name: Zip app
        if: matrix.runner == 'macos-latest'
        run: /usr/bin/ditto -c -k --keepParent build/Sleepless.app "build/Sleepless-${GITHUB_SHA}.zip"

      - name: Upload app
        if: matrix.runner == 'macos-latest'
        uses: actions/upload-artifact@v7
        with:
          name: Sleepless-${{ github.sha }}
          path: build/Sleepless-${{ github.sha }}.zip
          retention-days: 7
          if-no-files-found: error
```

- [ ] Step 2: Create `.github/workflows/build.yml`

```yaml
name: Build

on:
  workflow_call:
    inputs:
      version:
        description: 'App version, for example 0.1.0 or 0.0.1-rc'
        required: true
        type: string
      channel:
        description: 'release, rc or dev'
        required: true
        type: string

permissions:
  contents: read

jobs:
  build:
    name: Build ${{ inputs.version }} (${{ inputs.channel }})
    runs-on: macos-latest
    env:
      VERSION: ${{ inputs.version }}
      CHANNEL: ${{ inputs.channel }}
      BUILD_NUMBER: ${{ github.run_number }}
      EXPECTED_VERSION: ${{ inputs.version }}
    steps:
      - name: Checkout repository
        uses: actions/checkout@v7

      - name: Show toolchain
        run: /usr/bin/swift --version

      - name: Check version format
        run: |
          if ! printf '%s\n' "$VERSION" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.]+)?$'; then
            echo "::error::Invalid version '$VERSION' (expected for example 0.1.0 or 0.0.1-rc)"
            exit 1
          fi

      - name: Build universal app
        run: make app

      - name: Validate bundle
        run: make validate

      - name: Smoke test
        run: make smoke

      - name: Package
        run: make package

      - name: Upload packages
        uses: actions/upload-artifact@v7
        with:
          name: sleepless-${{ inputs.version }}
          path: |
            build/Sleepless-${{ inputs.version }}.dmg
            build/Sleepless-${{ inputs.version }}.zip
            build/SHA256SUMS.txt
          if-no-files-found: error
```

- [ ] Step 3: Create `.github/workflows/release.yml`

```yaml
name: Release

on:
  release:
    types: [published]
  workflow_dispatch:
    inputs:
      version:
        description: 'Version to build (semver, for example 0.1.0)'
        required: true
        type: string

permissions:
  contents: read

jobs:
  version:
    name: Resolve version
    runs-on: ubuntu-latest
    outputs:
      version: ${{ steps.resolve.outputs.version }}
    steps:
      - name: Resolve version
        id: resolve
        env:
          INPUT_VERSION: ${{ inputs.version }}
          TAG_NAME: ${{ github.event.release.tag_name }}
        run: |
          VERSION="${INPUT_VERSION:-${TAG_NAME#v}}"
          echo "Version: $VERSION"
          echo "version=$VERSION" >> "$GITHUB_OUTPUT"

  unit-tests:
    name: Unit Tests
    runs-on: macos-latest
    steps:
      - name: Checkout repository
        uses: actions/checkout@v7

      - name: Run unit tests
        run: make test

  build:
    name: Build
    needs: [version, unit-tests]
    uses: ./.github/workflows/build.yml
    with:
      version: ${{ needs.version.outputs.version }}
      channel: release

  # Only for a published release; a manual run just leaves the packages as workflow artifacts.
  publish:
    name: Publish release
    needs: [version, build]
    if: github.event_name == 'release'
    runs-on: ubuntu-latest
    permissions:
      contents: write
    steps:
      - name: Download packages
        uses: actions/download-artifact@v8
        with:
          name: sleepless-${{ needs.version.outputs.version }}
          path: dist

      # Uploading assets can leave the release drafted; publish it explicitly.
      - name: Upload assets and publish
        env:
          GH_TOKEN: ${{ github.token }}
          TAG_NAME: ${{ github.event.release.tag_name }}
        run: |
          gh release upload "$TAG_NAME" dist/* --clobber --repo "$GITHUB_REPOSITORY"
          gh release edit "$TAG_NAME" --draft=false --repo "$GITHUB_REPOSITORY"
```

- [ ] Step 4: Create `.github/workflows/prerelease.yml`

```yaml
name: Prerelease

on:
  workflow_dispatch:
    inputs:
      channel:
        description: 'dev recreates v0.0.0, rc recreates v0.0.1-rc'
        required: true
        type: choice
        options:
          - dev
          - rc
        default: dev

permissions:
  contents: read

jobs:
  version:
    name: Resolve version
    runs-on: ubuntu-latest
    outputs:
      version: ${{ steps.resolve.outputs.version }}
      tag: ${{ steps.resolve.outputs.tag }}
    steps:
      - name: Resolve version
        id: resolve
        env:
          CHANNEL: ${{ inputs.channel }}
        run: |
          case "$CHANNEL" in
            dev) VERSION=0.0.0 ;;
            rc) VERSION=0.0.1-rc ;;
            *) echo "::error::Unknown channel '$CHANNEL'"; exit 1 ;;
          esac
          echo "version=$VERSION" >> "$GITHUB_OUTPUT"
          echo "tag=v$VERSION" >> "$GITHUB_OUTPUT"

  build:
    name: Build
    needs: version
    uses: ./.github/workflows/build.yml
    with:
      version: ${{ needs.version.outputs.version }}
      channel: ${{ inputs.channel }}

  # Replaces the release only after a successful build, so a failed build never leaves it missing.
  publish:
    name: Recreate prerelease
    needs: [version, build]
    runs-on: ubuntu-latest
    permissions:
      contents: write
    steps:
      - name: Download packages
        uses: actions/download-artifact@v8
        with:
          name: sleepless-${{ needs.version.outputs.version }}
          path: dist

      - name: Replace release and tag
        env:
          GH_TOKEN: ${{ github.token }}
          TAG: ${{ needs.version.outputs.tag }}
          CHANNEL: ${{ inputs.channel }}
        run: |
          if gh release view "$TAG" --repo "$GITHUB_REPOSITORY" >/dev/null 2>&1; then
            gh release delete "$TAG" --yes --cleanup-tag --repo "$GITHUB_REPOSITORY"
          fi
          gh api --method DELETE "repos/$GITHUB_REPOSITORY/git/refs/tags/$TAG" >/dev/null 2>&1 || true
          gh release create "$TAG" dist/* \
            --repo "$GITHUB_REPOSITORY" \
            --target "$GITHUB_SHA" \
            --prerelease \
            --title "Sleepless $CHANNEL build (${GITHUB_SHA:0:7})" \
            --notes "Automated $CHANNEL build of commit $GITHUB_SHA. Ad-hoc signed: see the README for the Gatekeeper step."
```

- [ ] Step 5: Create `.github/dependabot.yml`

```yaml
version: 2
updates:
  - package-ecosystem: github-actions
    directory: /
    schedule:
      interval: weekly
```

- [ ] Step 6: Validate the YAML syntax locally (actionlint runs in CI)

Run: `for f in .github/workflows/*.yml .github/dependabot.yml; do /usr/bin/ruby -ryaml -e 'YAML.load_file(ARGV[0])' "$f" && echo "ok $f"; done`
Expected: `ok` for each of the five files (`/usr/bin/ruby` with its YAML library is present on this Mac, checked 2026-11-16). Full workflow checks run with actionlint in CI.

Suggested commit: `ci: add CI, reusable build, release and prerelease workflows`

---

### Task 15: Documentation and templates

Files:
- Create: `README.md`, `.github/ISSUE_TEMPLATE/feedback.md`, `.github/PULL_REQUEST_TEMPLATE.md`

- [ ] Step 1: Create `README.md`

````markdown
# Sleepless

Sleepless is a minimal macOS menu bar app that keeps your Mac awake while audio is playing, and lets it sleep again shortly after playback stops.

## Why

On battery, macOS can put a Mac to sleep in the middle of a playlist played in a browser (Spotify Web, YouTube). While audio plays, the browser and `coreaudiod` hold sleep assertions, but they release them at every track change or pause. If the display is already off and you are idle, the Mac sleeps within seconds of such a gap. Sleepless holds its own assertion across those gaps.

## How it works

- It watches the default output device (speakers, headphones, Bluetooth) with CoreAudio. No polling, no microphone access.
- After 3 seconds of continuous playback, it prevents idle system sleep. Short sounds such as notifications do not count.
- When playback stops, it keeps the Mac awake for 30 more seconds, which bridges track gaps and short pauses.
- The display still turns off on its normal schedule.

## Menu bar icon

| Icon | Meaning |
|-|-|
| Moon with "zzz", monochrome | No audio playing, the Mac can sleep |
| Music note, accent color | Audio playing, or stopped less than 30 seconds ago: the Mac stays awake |

The menu shows the current status, Launch at Login and Quit Sleepless. Hover the icon to see the version.

## Install

1. Download `Sleepless-<version>.dmg` from the [Releases page](../../releases/latest).
2. Open it and drag Sleepless to Applications.
3. Builds are ad-hoc signed (no Apple Developer ID), so macOS blocks the first launch. Either remove the quarantine flag:

   ```
   /usr/bin/xattr -dr com.apple.quarantine /Applications/Sleepless.app
   ```

   or open it once, then go to System Settings > Privacy & Security and click Open Anyway.
4. Optionally enable Launch at Login from the menu.

Requires macOS 13 or later, on Apple silicon or Intel.

## Limits

- Closing the lid on battery without an external display always puts the Mac to sleep; no app can prevent it.
- A pause longer than 30 seconds ends the activation, by design.
- Any app playing to the default output counts, including video calls and games.

## Troubleshooting

Follow what Sleepless does:

```
/usr/bin/log stream --style compact --predicate 'subsystem == "io.github.davidferlay.Sleepless"'
```

Check that it holds its assertion while music plays:

```
/usr/bin/pmset -g assertions | /usr/bin/grep -i sleepless
```

## Build from source

Xcode is not required; the Command Line Tools are enough (`xcode-select --install`).

```
make app        # build/Sleepless.app (universal, ad-hoc signed)
make package    # build/Sleepless-0.0.0.dmg, .zip and SHA256SUMS.txt
```

If SwiftPM fails with `Invalid manifest` or `redefinition of module 'SwiftBridging'`, an older Command Line Tools install left stale files behind: move aside the `*.private.swiftinterface` files under `/Library/Developer/CommandLineTools/usr/lib/swift/pm/` and `/Library/Developer/CommandLineTools/usr/include/swift/module.modulemap`, or reinstall the Command Line Tools.

## Tests

| Command | What it checks |
|-|-|
| `make lint` | Swift formatting (`swift format`), Info.plist, shell scripts (shellcheck) and workflows (actionlint) |
| `make test` | Unit tests: delays, model, presentation, settings, login item mapping |
| `make coverage` | Unit tests with a line coverage report |
| `make test-integration` | Real power assertions, CoreAudio listeners, dispatch timing, login item status |
| `make validate` | The built bundle: Info.plist, architectures, minimum macOS, signature, icon, linked libraries |
| `make smoke` | The app starts, stays up and quits cleanly on SIGTERM |
| `make e2e` | Real playback creates the assertion and the hold releases it (plays a quiet tone for 6 seconds) |

`make install-hooks` enables a pre-commit hook that runs `swift format lint` on staged files and `swift build`.

## Releases

| Workflow | Trigger | Result |
|-|-|-|
| CI | Push, pull request | Lint, unit, integration, and app tests on macOS 26 and 15 (Apple silicon and Intel) |
| Release | Publishing a GitHub release `vX.Y.Z` | DMG, zip and checksums attached to the release |
| Prerelease | Manual, channel `dev` or `rc` | Recreates the `v0.0.0` or `v0.0.1-rc` prerelease from the current commit |

## License

GPL-3.0, see [LICENSE](LICENSE).
````

- [ ] Step 2: Create `.github/ISSUE_TEMPLATE/feedback.md`

```markdown
---
name: Feedback
about: Share an idea, or report something that did not work as expected.
title: ''
labels: feedback
assignees: ''

---

## Steps


## Observed


## Expected


## Versions

- Sleepless (hover the menu bar icon):
- macOS:
```

- [ ] Step 3: Create `.github/PULL_REQUEST_TEMPLATE.md`

```markdown
## Description

<!-- What does this PR do? Why is it needed? -->

## Observed

<!-- What is the current behavior? (bug fixes) / What is missing? (features) -->

## Expected

<!-- What should happen instead? / What should the feature do? -->

## Changes

-

## Test Coverage

- [ ] Unit tests added or updated for new or changed logic (`make test`)
- [ ] Integration tests updated if OS API usage changed (`make test-integration`)
- [ ] App checks pass (`make app validate smoke e2e`)
- [ ] `make lint` clean

## Documentation

- [ ] README updated

## Screenshots

<!-- For menu bar or menu changes, include before/after screenshots -->

## Checklist

- [ ] All tests pass
- [ ] Commit messages are clear and descriptive
```

- [ ] Step 4: Check the Markdown rules (no bold, hyphen lists, no trailing spaces)

Run: `/usr/bin/grep -nE '\*\*[A-Za-z0-9]|^\s*\* | +$' README.md .github/ISSUE_TEMPLATE/feedback.md .github/PULL_REQUEST_TEMPLATE.md docs/specs/*.md docs/plans/*.md || echo clean`
Expected: `clean` (the pattern matches bold text, not workflow globs such as `Sources/**`).

Suggested commit: `docs: add README and GitHub templates`

---

### Added during execution (2026-11-16)

- `Tests/SleeplessIntegrationTests/DispatchSchedulerTests.swift`: the spec's "`DispatchScheduler` fire and cancel" integration tests, missing from Tasks 4-7. Two tests (fires after 0.05 s; a cancelled item never fires), 13 integration tests in total.

---

### Task 16: Final verification and handoff

- [ ] Step 1: Full local run from a clean state

Run: `make clean && make lint && make test && make test-integration && make app && make validate && make smoke && make e2e && make package VERSION=0.0.0`
Expected: every step exits 0; `make test` ends with 0 failures; the end-to-end test passes (nothing else playing).

- [ ] Step 2: Owner acceptance test (real use, from the spec)

  1. Install the build: `/usr/bin/ditto build/Sleepless.app /Applications/Sleepless.app`, then open it and enable Launch at Login.
  2. On battery, play a playlist in Brave and leave the Mac untouched for 15 minutes with the display off.
  3. Check that there was no idle sleep while music played and that the assertion bridged the track gaps:

     ```
     /usr/bin/pmset -g log | /usr/bin/grep -E "Sleepless|Entering Sleep state due to 'Idle Sleep'"
     ```

  4. Stop the music: the icon returns to the moon about 30 s later.
  5. Log out and back in: Sleepless starts again.

- [ ] Step 3: Publish to GitHub (owner decides; nothing is pushed by the agent)

  Create an empty repository named `Sleepless` on github.com under `davidferlay`, then:

  ```
  /usr/bin/git -C /Users/john/Sources/Sleepless remote add origin https://github.com/davidferlay/Sleepless.git
  /usr/bin/git -C /Users/john/Sources/Sleepless push -u origin main
  ```

  On the first CI run, check that:
  - `macos-15-intel` is accepted as a runner label. If it is not, remove it from the `app` matrix.
  - actionlint knows every runner label. If it reports one as unknown, add a `.github/actionlint.yaml` with `self-hosted-runner: labels: [<label>]`.
  - The end-to-end step either passes or shows the "No default audio output device" notice.

- [ ] Step 4: Copy the final plan and spec to the OneDrive Plans folder again if they changed

Run: `/bin/cp docs/plans/2026-11-16-sleepless.md /Users/john/Library/CloudStorage/OneDrive-Personal/Notes/OSX/Plans/Sleepless-Implementation-Plan.md && /bin/cp docs/specs/2026-11-16-sleepless-design.md /Users/john/Library/CloudStorage/OneDrive-Personal/Notes/OSX/Plans/Sleepless-Design.md`
