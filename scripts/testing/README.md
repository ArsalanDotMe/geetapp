# Native interaction checks

The optional Accessibility helper drives only Geet builds inside this checkout. Obtain the Mac owner's permission before enabling Accessibility or injected input. The helper verifies the bundle identifier and executable location and checks Geet's focus before each injected keyboard event. It skips system-wide Apple menu items.

```sh
xcrun swiftc -module-cache-path .build/AXModuleCache \
  scripts/testing/accessibility.swift -o build/geet-ax
mkdir -p build/interactive-evidence
GEET_DATA_DIR="$PWD/build/interactive-data" \
GEET_VALIDATION_DIR="$PWD/build/interactive-evidence" \
build/Geet.app/Contents/MacOS/Geet --interactive-validation --show
```

The debug app prints its PID. In another terminal, replace `PID` below with it:

```sh
build/geet-ax PID snapshot
build/geet-ax PID press add-playlist
build/geet-ax PID type youtube-link 'https://www.youtube.com/watch?v=jNQXAC9IVRw'
build/geet-ax PID key 36
build/geet-ax PID capture
```

`snapshot` returns the current accessible tree. Actions accept an identifier, a fresh snapshot index, or an exact `label:` or `title:` selector. `press` invokes an Accessibility action directly, so it does not verify the mouse hit area, activation click, or pressed appearance. Use `click` for those checks. It sends a real mouse move, down, and up, checking that the press hits the requested control or one of its descendants. The release must stay in geet; native menus may replace their button's hit target during the press. A clipped, covered, or offscreen target causes a refusal. Use `reveal` on a scrollable control, then take a fresh snapshot before clicking it.

`click` and `right-click` default to the center. Two optional fractions select a point within the current control bounds. For example, these test the left and right sides of a playback circle while staying inside it:

```sh
build/geet-ax PID click transport-play 0.12 0.5
build/geet-ax PID snapshot
build/geet-ax PID click transport-play 0.88 0.5
build/geet-ax PID snapshot
```

Use `right-click geet-status-item` to check the menu bar Quit menu. An ordinary `click geet-status-item` must still open and close the panel.

For a first-click regression check, use an isolated library and test the center and four cardinal edges of the Library hero, Library row, track-view and transport play controls. Confirm the action changes to loading, playing, or paused after each individual click. Also check Discover play/add and cancellation, Back, search, add/close, playlist menus, queue, previous/next, shuffle/repeat, volume/mute, and Settings navigation. A disabled control should remain disabled. Reopen the panel and repeat playback checks after a fresh launch. Do not treat a successful Accessibility `press` as a mouse pass.

`type` injects actual text events; AX value assignment alone does not exercise SwiftUI input binding. `key` takes a macOS key code, such as 36 for Return, 49 for Space, or 53 for Escape. `capture` sends SIGUSR1 and must only target an app launched with `--interactive-validation`. Normal and release launches have no capture signal handler.

The interactive harness records app-local key events and isolated state alongside captures. Keep all raw output in ignored `build/`; it can include pasted links or private titles. Commit only inspected public screenshots and deliberately sanitized result fields. The harness and preview modes are excluded from release builds. Hardware media keys require direct device acceptance.
