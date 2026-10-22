# Native UI audit and plan

Date: 2026-10-22. Audit of the SwiftUI layer as imported, plus what the installed
SDK actually offers. Nothing here was rendered; visual results are L1 at most.

## What exists today

| screen | file | state |
|---|---|---|
| Library | `Sources/Monochrome/ContentView.swift` | one flat `List` of imported files, favorites-only toggle, import/delete, queue button |
| Mini player | `MiniPlayerView.swift` | title + play/pause + next above the list, no artwork, no progress |
| Now Playing | `PlayerView.swift` | sheet with a fixed 280-pt artwork block, transport and seek |
| Queue | `QueueView.swift` | sheet listing the queue with reorder/jump/remove |
| Artwork | `ArtworkView.swift` | embedded-artwork reader for local files |

Gaps against the brief:

- No tab shell, no Home, no Search. Everything is one library list.
- No online content anywhere: rows show file-imported tracks only.
- Mini player has no artwork, no progress, no glass, and lives in a
  `safeAreaInset` on the single screen — it disappears with navigation changes.
- Now Playing uses a fixed 280-pt frame instead of `containerRelativeFrame` and
  breaks on small phones and with large Dynamic Type.
- No design tokens: paddings, radii and type are inline and inconsistent.
- No app icon (`the local xtool manifest` has no `iconPath`, no asset catalog), no logo
  anywhere in the UI.
- No empty/error state for anything online, because nothing online exists.

## What the installed SDK actually provides

Checked in
`…/iPhoneOS27.1.sdk/System/Library/Frameworks/SwiftUI.framework/Modules/SwiftUI.swiftmodule/arm64e-apple-ios.swiftinterface`.

| API | found | availability |
|---|---|---|
| `glassEffect` | **no** | not in this SDK |
| `GlassEffectContainer` | **no** | not in this SDK |
| `glassEffectID` | **no** | not in this SDK |
| `.buttonStyle(.glass)` / `GlassButtonStyle` | yes | iOS 26.0 |
| `tabViewBottomAccessory` | yes | iOS 26.0, iOS-only |
| `tabViewBottomAccessoryPlacement` | yes | iOS 26.0 |
| `tabBarMinimizeBehavior` | yes | iOS 26.0 |
| `Tab(_:image:value:)` typed tabs | yes | **iOS 18.0** |
| `TabRole.search` | yes | iOS 18.0 |
| `matchedTransitionSource` | yes | iOS 18.0 |
| `navigationTransition` | yes | iOS 18.0 |

Package deployment target is **iOS 17.0** and stays there. Consequences:

1. `glassEffect`, `GlassEffectContainer` and `glassEffectID` cannot be used at
   all — they do not exist in this SDK. No guessing, no shim under those names.
2. Typed `Tab` and `TabRole.search` need iOS 18, so the tab shell uses the
   classic `TabView` + `.tabItem`, which works on 17 and renders with Liquid
   Glass on 26 (system components adopt the new design when built with this
   SDK).
3. `tabViewBottomAccessory` is iOS 26-only. The mini player uses it behind
   `#available(iOS 26, *)`, and an `overlay(alignment: .bottom)` fallback
   above the tab bar otherwise.
4. `.buttonStyle(.glass)` is iOS 26-only. It is applied through **one**
   `glassControlStyle()` helper with a `.bordered` fallback, honoring
   `accessibilityReduceTransparency`.

So the honest Liquid Glass story for this repo: glass arrives through the
system tab bar, navigation bars, toolbars and sheets on iOS 26, plus one
`.glass` button style on the Now Playing transport. Everything else uses
system materials. We never paint opaque backgrounds over system chrome.

## Design decisions

- **Palette:** near-black background (`Color(white: 0.05)`), primary text white,
  secondary `white.opacity(0.6)`, one accent derived from the artwork. No
  gradients, no neon, no Spotify green.
- **Type:** SF Pro via semantic styles only (`.largeTitle`, `.headline`,
  `.subheadline`, `.caption`), so Dynamic Type works. Durations use
  `.monospacedDigit()`.
- **Spacing scale:** 4 / 8 / 12 / 16 / 24 / 32 as `CGFloat` constants in one
  `Theme` enum.
- **Artwork:** `AsyncImage` for remote URLs, existing `ArtworkView` for local
  files, and a single missing-artwork placeholder (SF Symbol on a neutral
  fill). Artwork never gets a glass overlay.
- **Navigation:** `TabView` with Home, Search, Library. Each tab owns a
  `NavigationStack`. Navigating never touches `PlayerController`, which stays
  the single source of truth.
- **Now Playing:** full-screen cover (not a sheet) from the mini player.
  Artwork sized with `containerRelativeFrame`, controls in one glass cluster on
  iOS 26, materials below.
- **Queue:** sheet from Now Playing; reorder/remove only where the player
  supports it (it does: `Queue` has move/remove).
- **Logo:** the web app's own icon/logo, unchanged, in the Home header.

## Needs eyes on a device (cannot be verified here)

1. Does `AVPlayer` accept `application/octet-stream` FLAC from the tracks host?
   This is the single biggest unknown; if it refuses, playback needs a
   different tier or a server that sets `audio/flac`.
2. Mini player placement on iOS 26 devices with `tabViewBottomAccessory`, and
   that it does not cover list content on iOS 17 (fallback path).
3. Glass legibility over bright artwork, and with Reduce Transparency enabled.
4. Artwork layout at the largest accessibility text sizes and on a 4.7" screen.
5. Safe areas during scrolling, especially the mini player over a tab bar that
   minimizes on scroll.
6. Remote artwork loading over a slow connection (placeholder then fade).
7. Haptics/animations timing — none were added beyond system defaults.
8. Background audio + lock-screen controls after the navigation rewrite.
