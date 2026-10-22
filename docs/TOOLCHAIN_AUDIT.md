# Toolchain audit & spike

Verified on 2026-10-22 on x86_64 Linux. Every claim below is a command result or a
source citation. Nothing was installed, signed, or written to a device.

## 1. Tool inventory

| Tool | Status | Evidence |
|---|---|---|
| git | 1 installed & verified | `/usr/bin/git`; commits made locally |
| swift / swiftc | 1 installed & verified | `Swift version 6.4.1 (swift-6.4.1-RELEASE)`, target `x86_64-unknown-linux-gnu` |
| swiftly | 1 installed & verified | `swiftly list` → `6.4.1 (in use) (default)` |
| Darwin Swift SDK | 1 installed & verified | `swift sdk list` → `darwin`; `xtool sdk status` → installed, slim, `iPhoneOS27.1.sdk` |
| xtool | 2 installed, deliberately unverified | `xtool 1.22.2`; only `--version`, `--help`, `sdk status` run (its build path installs) |
| swift format | 1 installed & verified | `swift format --version` → `6.4.1` |
| sourcekit-lsp | 4 optional | `--help` works; no editor integration used |
| curl, jq, rg, timeout, file, readelf, ldd | 1 installed & verified | used throughout |
| idevice_id | 4 optional | `/usr/bin/idevice_id`; `idevice_id -l` → `ERROR: Unable to retrieve device list!` (no device, expected) |
| SwiftUI / AVFoundation / MediaPlayer | 1 verified for compile | imported in the spike, iOS build green (§3) |

ncurses workaround: `APPIMAGELAUNCHER_DISABLE` and `LD_LIBRARY_PATH` are both unset
in this shell, and `env -u LD_LIBRARY_PATH ldd $(command -v swiftc)` reports no
`ncurses` / `not found` lines. **The existing RUNPATH setup is sufficient; no build
script needs to export anything.**

## 2. Build-only command

```bash
swift build --build-system native --swift-sdk darwin --triple arm64-apple-ios
```

- `swift sdk list` prints `darwin`; the SDK's `swift-sdk.json` lists
  `arm64-apple-ios` (no OS version suffix), so that exact triple is required.
- Without `--build-system native`, SwiftPM 6.4.1 defaults to the new `swiftbuild`
  engine and fails with `unable to find platform for 'iphoneos'` (also
  `unable to resolve run destination platform: 'iphoneos'` when a destination file
  is used). `native` is deprecated but works and emits a warning.
- `--swift-sdk darwin` alone fails: `The query for 'darwin' ... has multiple
  target triples`.
- Output verified as real iOS objects: `file .build/arm64-apple-ios/debug/...o` →
  `Mach-O 64-bit arm64 object`.
- This is a **compile check only**; no `.app` is produced and nothing is installed.

## 3. Spike results (`/tmp/monochrome-spike`, copy of `~/xtool-test/test`)

| Question | Result |
|---|---|
| Does the template compile for iOS? | yes — `Build complete!`, Mach-O arm64 objects |
| `import SwiftUI`, `AVFoundation`, `MediaPlayer`? | yes — all three compiled, including `AVAudioSession` and `AVPlayer` |
| `@Observable` macro? | yes — `Observation` + `@Observable` class compiled in Swift 6 mode |
| Resources? | yes for SwiftPM: `.process("Resources")` produced `Monochrome_Monochrome.bundle` with the file inside, for the iOS triple |
| Asset catalogs? | not attempted — `actool` is an Xcode tool and is not present; the app uses SF Symbols and no `.xcassets` |
| Portable core + host tests? | yes — `swift test` built `MonochromeCore`, ran one `@Test`, passed, while the iOS-only target compiled to an empty module through `#if canImport(SwiftUI)` |
| Swift 6 vs 5? | Swift 6 mode (`swiftLanguageModes: [.v6]`) compiles both targets; kept |

## 4. App packaging knobs

Read from xtool source (`Sources/PackLib/PackSchema.swift`, current `main`), not guessed:

```
version: 1            # required enum, only 1
bundleID: <id>        # or orgID; one is required
product: <name>       # optional product name
infoPath: <path>      # custom Info.plist
entitlementsPath: <path>
iconPath: <png path>  # must end in .png
resources: [<paths>]  # extra resources copied into the bundle
extensions: [...]     # app extensions, unused here
```

So `UIBackgroundModes: [audio]` goes in an `Info.plist` referenced by `infoPath`
(alongside `UILaunchScreen`), and loose resources go under `resources`.
Caveat: **unverified end to end** — the only xtool command that packs an app
(`xtool dev`) also installs it, which this project forbids. SwiftPM resource
bundles are proven to build (§3); whether xtool copies them into the `.app` is
not proven here.

## 5. Consequences for the project

- Two targets, as planned: `MonochromeCore` (Foundation only, host-tested) and
  `Monochrome` (everything Apple-only, guarded by `#if canImport(SwiftUI)`).
- `swift test` must stay green: any new Apple-only file in `Monochrome/` inherits
  the existing file-level guard.
- No asset catalogs, no Xcode project, no third-party packages.
- App icon: PNG via `iconPath` — not attempted here (no icon assets, and it has
  no bearing on the compile check). Unverified.
