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

`snapshot` returns the current accessible tree. Actions accept an identifier or a fresh snapshot index. `type` injects actual text events; AX value assignment alone does not exercise SwiftUI input binding. `key` takes a macOS key code, such as 36 for Return, 49 for Space, or 53 for Escape. `capture` sends SIGUSR1 and must only target an app launched with `--interactive-validation`. Normal and release launches have no capture signal handler.

The interactive harness records app-local key events and isolated state alongside captures. Keep all raw output in ignored `build/`; it can include pasted links or private titles. Commit only inspected public screenshots and deliberately sanitized result fields. The harness and preview modes are excluded from release builds. Hardware media keys require direct device acceptance.
