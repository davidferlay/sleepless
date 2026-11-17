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
| CI | Push, pull request, or manual | Lint, unit, integration, and app tests on macOS 26 and 15 (Apple silicon and Intel) |
| Build | Manual (version, channel), or called by Release and Prerelease | DMG, zip and checksums as workflow artifacts; publishes nothing |
| Release | Publishing a GitHub release `vX.Y.Z`, or manual (version) | DMG, zip and checksums attached to the release; a manual run only keeps them as workflow artifacts |
| Prerelease | Manual, channel `dev` or `rc` | Recreates the `v0.0.0` or `v0.0.1-rc` prerelease from the current commit |

Every workflow can be started by hand from the Actions tab (Run workflow).

## License

GPL-3.0, see [LICENSE](LICENSE).

