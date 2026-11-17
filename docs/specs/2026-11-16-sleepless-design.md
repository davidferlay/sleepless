# Sleepless Design

Date: 2026-11-16
Status: approved in brainstorming, pending written-spec review

## Goal

A minimal macOS menu bar app that keeps the Mac from idle sleeping while audio is playing, and lets it sleep again shortly after playback stops. The menu bar icon shows whether playback is detected and sleep is being prevented.

## Background

On battery, macOS puts the Mac to sleep in the middle of browser playback (Spotify Web, YouTube in Brave). The power log (`/usr/bin/pmset -g log`) shows why:

- While audio streams, Brave holds a `NoIdleSleepAssertion` ("Playing audio") and `coreaudiod` holds a `PreventUserIdleSystemSleep` assertion for the output device.
- Both are released at every track change or pause.
- With the display already off and the user idle, the Mac sleeps within 5 to 30 seconds of such a gap. Example, 2026-11-11: display off at 13:26:38, Brave assertion released at 13:42:23, `coreaudiod` assertion off at 13:42:24 (`[System: No Assertions]`), Idle Sleep at 13:42:29.

Sleepless holds its own assertion across those gaps.

## Scope

In scope:

- Automatic detection of playback on the default output device.
- Preventing idle system sleep while playback is detected, plus a 30 s hold after it stops.
- Menu bar icon with two states, a status line, Launch at Login, Quit.
- Unit, integration, bundle, smoke and end-to-end tests; CI and release pipelines on GitHub Actions.

Out of scope:

- Keeping the display awake (the display sleeps on its normal timer).
- Preventing sleep when the lid is closed on battery without an external display (macOS forces it; no app can prevent it).
- Settings window, manual activation, pause toggle, About window.
- Developer ID signing and notarization (builds are ad-hoc signed).
- Per-app detection (any process playing to the default output counts).

## Requirements

| Item | Decision |
|-|-|
| Name | Sleepless |
| Repository | `/Users/john/Sources/Sleepless`, branch `main`, local only until the owner creates the GitHub repo |
| Bundle identifier | `io.github.davidferlay.Sleepless` |
| Language and build | Swift 6 (strict concurrency), Swift Package Manager, builds with Command Line Tools only (no Xcode) |
| Minimum macOS | 13.0 (`SMAppService`) |
| Architectures | Universal (arm64 and x86_64) for releases |
| Signing | Ad-hoc (`codesign --sign -`), no App Sandbox, no hardened runtime requirement |
| Dock icon | None (`LSUIElement` = true) |
| License | GPL-3.0 |

## Behavior

### Detection

- Reads `kAudioDevicePropertyDeviceIsRunningSomewhere` on the default output device (`kAudioHardwarePropertyDefaultOutputDevice`).
- Event driven: property listener blocks on the main queue, no polling, no microphone permission.
- When the default output device changes, the listener moves to the new device and the state is re-read.
- After wake from sleep (`NSWorkspace.didWakeNotification`), the state is re-read.
- No default output device means "not playing".

### Timing

| Event | Reaction |
|-|-|
| Playback starts | Activate after 3 s of continuous playback (`startDelay`) |
| Playback stops while active | Stay active for 30 s (`stopDelay`), then release |
| Playback resumes during the hold | Cancel the release, stay active |
| Playback stops before the 3 s elapse | Cancel the activation |

Both delays are read from user defaults keys `startDelay` and `stopDelay` (seconds, `Double`). Missing, zero-or-negative, or non-numeric values fall back to 3 and 30. They are passed as launch arguments in tests (`-startDelay 1 -stopDelay 3`). There is no UI for them.

### Sleep prevention

- `IOPMAssertionCreateWithName(kIOPMAssertionTypePreventUserIdleSystemSleep, kIOPMAssertionLevelOn, "Sleepless: audio playback", ...)` while active.
- `IOPMAssertionRelease` when the hold ends and on quit.
- macOS releases the assertion automatically if the process exits or crashes.
- SIGTERM is turned into a normal quit (`NSApplication.terminate`), so the assertion is released and the stop is logged.

### Menu

| Item | Behavior |
|-|-|
| Status line | Disabled item. Text depends on status (see Presentation) |
| Separator | |
| Launch at Login | Checkbox backed by `SMAppService.mainApp`. When status is `requiresApproval`, title is "Launch at Login (approve in System Settings)" and clicking opens System Settings > Login Items. Disabled when not running from an app bundle. Register or unregister errors are shown in an alert |
| Separator | |
| Quit Sleepless | Cmd-Q, releases the assertion and quits |

### Presentation

| Status | Symbol | Tint | Status line |
|-|-|-|-|
| `idle` | `moon.zzz` | none (template) | No audio playing, Mac can sleep |
| `playing` | `music.note` | `NSColor.controlAccentColor` | Audio playing, keeping Mac awake |
| `holding` | `music.note` | `NSColor.controlAccentColor` | Audio stopped, keeping Mac awake for a moment |
| `failed(code)` | `moon.zzz` | none (template) | Could not prevent sleep (error 0xE00002C2), with the IOReturn code in hex |

- Accessibility description: "Sleepless: keeping Mac awake" when tinted, "Sleepless: Mac can sleep" otherwise.
- Tooltip: "Sleepless 0.1.0" for the `release` channel, "Sleepless 0.0.0 (dev abc1234)" for other channels (`dev`, `rc`, `local`), "Sleepless (unbundled)" when running without a bundle.
- Version, channel and commit come from Info.plist keys `CFBundleShortVersionString`, `SleeplessBuildChannel`, `SleeplessBuildCommit`.

### Errors and logging

- Assertion creation failure: status `failed(code)`, icon idle, error logged. The next transition to idle clears it; the next activation retries.
- Logging with `os.Logger`, subsystem `io.github.davidferlay.Sleepless`, categories `app`, `playback`, `assertion`. Lifecycle and transition messages use the notice level, which the unified log persists, so `log show` returns them: "Sleepless started", "Sleepless stopped", "Playback detected: YES", "Playback detected: NO", "Assertion acquired", "Assertion released". The smoke test checks "Sleepless started" and "Sleepless stopped".

## Architecture

### Package

- `SleeplessCore` (library): all logic, no AppKit UI.
- `Sleepless` (executable): AppKit status item and app delegate.
- `SleeplessCoreTests` (Swift Testing): unit tests with fakes.
- `SleeplessIntegrationTests` (Swift Testing): real IOKit, CoreAudio, ServiceManagement and Dispatch.

### Components

| File | Type | Responsibility |
|-|-|-|
| `PlaybackDetector.swift` | `protocol PlaybackDetecting`, `final class CoreAudioPlaybackDetector` | Reports `isPlaying` and calls `onChange(Bool)` on the main actor |
| `Scheduler.swift` | `protocol Scheduling`, `protocol Cancellable`, `final class DispatchScheduler` | `schedule(after: TimeInterval, action) -> Cancellable` |
| `ActivationController.swift` | `final class ActivationController`, `enum ActivationPhase { idle, pendingStart, active, holding }` | Pure state machine driven by `playbackChanged(_:)` and the scheduler |
| `SleepAssertion.swift` | `protocol SleepAssertion`, `struct SleepAssertionError { code: Int32 }`, `final class IOPMSleepAssertion` | `acquire() throws`, `release()`, `isHeld` |
| `LoginItem.swift` | `protocol LoginItemManaging`, `enum LoginItemStatus { enabled, requiresApproval, disabled, unavailable }`, `final class SMAppServiceLoginItem` | Status, `setEnabled(_:) throws`, `openSystemSettings()` |
| `AppModel.swift` | `final class AppModel`, `enum AppStatus { idle, playing, holding, failed(code: Int32) }` | Connects detector, controller and assertion; publishes `status` through `onStatusChange` |
| `StatusPresentation.swift` | `struct StatusPresentation`, `struct BuildInfo` | Maps status to symbol, tint, texts; builds the tooltip |
| `Settings.swift` | `struct Settings` | Reads and validates `startDelay` and `stopDelay` |
| `Sleepless/main.swift` | | Starts `NSApplication` with `AppDelegate` |
| `Sleepless/AppDelegate.swift` | `final class AppDelegate` | Builds the model and status item; releases on terminate |
| `Sleepless/StatusItemController.swift` | `final class StatusItemController` | Renders `StatusPresentation` into `NSStatusItem` and `NSMenu` |

All core types are `@MainActor`. CoreAudio listener blocks are registered on `DispatchQueue.main`.

### Data flow

```
CoreAudioPlaybackDetector --isPlaying--> ActivationController --phase--> AppModel --status--> StatusItemController
                                                                            |
                                                                            +--> SleepAssertion acquire / release
LoginItemManaging <-- menu checkbox (StatusItemController)
```

Phase to status: `idle` and `pendingStart` map to `idle`; `active` maps to `playing`; `holding` maps to `holding`; an acquire failure maps to `failed(code)`.

### Build

- `swift build -c release --triple arm64-apple-macosx13.0` and `--triple x86_64-apple-macosx13.0`, merged with `/usr/bin/lipo -create`.
- `Scripts/build-app.sh` assembles `build/Sleepless.app`: Info.plist from `Resources/Info.plist` with version, build number, channel and commit substituted; binary; `AppIcon.icns`; ad-hoc signature.
- `Scripts/make-icon.swift` renders the app icon from the `moon.zzz` symbol once; the `.icns` is committed.
- `Scripts/package.sh` creates `Sleepless-<version>.dmg` (with an `/Applications` link, `hdiutil`), `Sleepless-<version>.zip` (`ditto -c -k --keepParent`) and `SHA256SUMS.txt`.
- Version: from the tag in release workflows, `0.0.0` otherwise. Build number: `GITHUB_RUN_NUMBER` in CI, commit count locally.

## Testing

| Kind | Content | Make target |
|-|-|-|
| Static | `swift format lint --strict`, `shellcheck`, `actionlint`, `plutil -lint` | `make lint` |
| Unit | Controller timings, model acquire and release, failure and recovery, presentation, settings validation, login item mapping | `make test` |
| Integration | Real assertion visible in `IOPMCopyAssertionsByProcess` and gone after release; CoreAudio default device and listeners (skipped without an output device); `DispatchScheduler` fire and cancel; `SMAppService` status read only | `make test-integration` |
| Bundle validation | Info.plist keys and version, `lipo -archs`, `codesign --verify --strict`, icon, `otool -L` system libraries only | `make validate` |
| Smoke | Launch, alive after 5 s, "Sleepless started" logged, exits within 5 s of SIGTERM, no crash report | `make smoke` |
| End-to-end | Launch with short delays, play audio with `/usr/bin/afplay`, assertion appears in `/usr/bin/pmset -g assertions`, still present during the hold, gone after it; skipped with a notice when there is no output device | `make e2e` |
| Pre-commit | `swift format lint` on staged Swift files and `swift build` | `make install-hooks` |

Unit tests use a `ManualScheduler` whose `advance(by:)` fires due actions, and fakes for detector, assertion and login item. Coverage summary from `llvm-cov report` goes to the CI job summary, with no threshold.

## CI and release

| Workflow | Trigger | Jobs |
|-|-|-|
| `ci.yml` | Push to any branch, pull request to `main`, path filtered, or manual; concurrency with cancel in progress | `lint`, `unit-tests` (with coverage summary), `integration-tests`, `app` (universal build, validate, smoke, e2e; also on the oldest available macOS runner; uploads the zip as an artifact for 7 days) |
| `build.yml` | `workflow_call` with `version`, `channel`, or manual with the same inputs (artifacts only, nothing published) | Build, validate, package, upload workflow artifact |
| `release.yml` | Release published, or manual with a version | Unit tests, `build.yml`, upload assets, publish the release (undraft) |
| `prerelease.yml` | Manual with `channel` (`dev` or `rc`) | Recreate `v0.0.0` (dev) or `v0.0.1-rc` (RC) prerelease at the current commit, `build.yml`, upload assets |

- Default permissions `contents: read`; release jobs `contents: write`.
- No caching (no dependencies, full build under a minute).
- Runner default Xcode; `swift --version` logged in each job.
- `.github/dependabot.yml` updates GitHub Actions weekly.

## Repository files

- `README.md`: purpose and background, install from DMG, Gatekeeper step (`/usr/bin/xattr -dr com.apple.quarantine /Applications/Sleepless.app` or Open Anyway in System Settings), icon states, limits, build from source, running tests.
- `LICENSE` (GPL-3.0), `.gitignore`, `.swift-format`.
- `.github/ISSUE_TEMPLATE/feedback.md` and `.github/PULL_REQUEST_TEMPLATE.md`, structured like Octatrack-Manager's.
- `docs/specs/` and `docs/plans/`, copied to `/Users/john/Library/CloudStorage/OneDrive-Personal/Notes/OSX/Plans/`.
- Conventional commit messages (`feat:`, `test:`, `ci:`, `docs:`). Local commits only; no remote is created and nothing is pushed.

## Unknowns to verify first

| Unknown | Fallback |
|-|-|
| `swift test` with Swift Testing works with Command Line Tools only (`Testing.framework` present, XCTest absent) | Tests run in CI only; `make test` explains why locally |
| GitHub macOS runners expose an audio output device | End-to-end test skips in CI with a notice and runs locally |
| `swift build --triple x86_64-apple-macosx13.0` works with Command Line Tools | Local builds arm64 only; CI builds universal |
| Oldest macOS runner label still offered by GitHub | Check GitHub documentation; drop the second runner if none older than `macos-latest` |
| `SMAppService.mainApp.register()` works for an ad-hoc signed app | Document the manual alternative (System Settings > Login Items > add) |

## Acceptance criteria

- Playing a playlist in Brave on battery with the display off and no input for 15 minutes produces no `Entering Sleep state due to 'Idle Sleep'` entry while music plays, and the Sleepless assertion stays held across track gaps (`/usr/bin/pmset -g log`).
- After playback stops, the assertion is released 30 s later and the icon returns to `moon.zzz`.
- A notification sound shorter than 3 s does not change the icon.
- Launch at Login survives a logout and login.
- All CI jobs pass on `main`; a published release has the DMG, zip and checksums attached.
