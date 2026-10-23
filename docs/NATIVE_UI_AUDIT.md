# Native UI audit and redesign direction

Date: 2026-10-23. Source audit before the Nothing-inspired visual pass. No
screen was rendered; visual results remain L1 unless a person inspects them.

## Actual current state

| screen / component | file | state |
|---|---|---|
| App entry | `Sources/Monochrome/App.swift` | `@main`; appearance comes from `AppearanceSettings`, not a forced scheme |
| Shell | `Sources/Monochrome/ContentView.swift` | `AppTab` (no `Tab` shadowing); player is a large sheet; one mini-player inset on the `TabView` |
| Mini player | `Sources/Monochrome/MiniPlayerView.swift` | floating artwork-tinted card, favorite, play/pause, next, progress, retry |
| Now Playing | `Sources/Monochrome/PlayerView.swift` | tinted background, chevron, artwork, favorite, scrubber, transport, queue, badge, AirPlay |
| Queue | `Sources/Monochrome/QueueView.swift` | medium/large sheet; now playing and upcoming; jump, reorder, remove |
| Home | `Sources/Monochrome/HomeView.swift` | greeting, logo, quick-access grid, Listen again, Your favorites, empty state |
| Search | `Sources/Monochrome/SearchView.swift` | pinned field, persisted recents, result-type chips, top result, rows, menus |
| Library | `Sources/Monochrome/LibraryView.swift` | All/Favorites/Downloaded/Local chips, sort menu, pinned Favorites, import, download and local delete |
| Album and artist | `Sources/Monochrome/CatalogDetailViews.swift` | detail sheets with real catalog data |
| Settings | `Sources/Monochrome/SettingsView.swift` | appearance, host, downloads, five-slot cache meter, cached-song list, Done only |
| Shared row | `Sources/Monochrome/TrackRow.swift` | artwork, title, artist, badge, favorite marker, duration |
| Shared artwork | `Sources/Monochrome/TrackArtwork.swift` | remote image, local embedded image, placeholder |
| Tokens | `Sources/Monochrome/Theme.swift` | adaptive palette from `ThemePalette`, spacing, radii, type, glass helper |
| Downloads | `Sources/Monochrome/DownloadsView.swift` | permanent offline files, play, remove with confirmation |
| Source detail | `Sources/Monochrome/SourceDetailView.swift` | real capability matrix, configuration and companion limitation |
| Dot matrix | `Sources/Monochrome/DotMatrixView.swift` | 5×7 numerals and five-slot cache meter |
| Bar model | `Sources/MonochromeCore/NowPlayingBar.swift` | derived title, subtitle, badge, progress, loading/failure |

## Confirmed findings

1. The old `Tab` shadowing and `.fullScreenCover` presentation are already fixed.
2. The mini-player inset is applied once to the `TabView`, but the card can
   visually sit over tab content because the inset is not propagated reliably to
   the child scroll views. The inset needs to live with each tab's root while
   sharing one mini-player definition.
3. `App.swift` forces dark appearance. The custom `Theme` colors are also
   dark-only, so light appearance is not a real variant yet.
4. The palette has no semantic accent token beyond white. Nothing-inspired
   hierarchy needs one restrained accent for selection, progress and active
   playback state.
5. The shared components use large radii and soft card treatment. The visual
   language should move to tighter geometry, hairline rules, technical labels
   and monospaced metadata.
6. `HomeView` no longer hardcodes its background and no longer accepts an unused
   player closure.
7. The existing core helpers for tint, quick access, search partitioning and
   library filtering/sorting are already tested and should be reused.

## Design rules for this pass

- Monochrome chrome, one restrained red accent for state and progress.
- Near-black or off-white backgrounds; one or two neutral surface levels.
- Tight artwork radii, 10–12 pt cards, hairline dividers, no pill-heavy UI.
- System typography with monospaced numerals and compact uppercase micro-labels.
- Small red square/dot markers and short rules communicate structure and state.
- Artwork color stays limited to the mini-player and Now Playing background.
- Native tab bars, navigation bars, sheets and safe areas remain intact.
- Motion is short and disabled or reduced under Reduce Motion.
- No fake telemetry, recommendations, quality claims or unimplemented controls.

## Target per screen

| screen | target |
|---|---|
| Shell | Home/Search/Library tabs; one mini-player definition; reliable bottom inset on each tab; large player sheet |
| Mini player | compact tinted surface, 42 pt artwork, title/artist, real badge, favorite, play/pause, next, 2 pt progress |
| Now Playing | tinted dark or intentional light treatment, chevron, technical source caption, large artwork, scrubber, transport, queue, badge, AirPlay |
| Queue | medium/large sheet; current then upcoming; jump, reorder and remove only |
| Home | technical greeting, two-column quick access, Listen again, Your favorites, real empty state |
| Search | pinned field, recent searches, returned-type chips, top result, shared rows, real menus |
| Library | filter chips, sort menu, pinned Favorites, import, shared rows, real empty states |
| Settings | host, appearance, downloads and cache controls; one Done action; no Save |
| Shared | `Chip`, `ShelfHeader`, `ArtworkTile`, `TrackRow`, `RoundPlayButton`, `Scrubber`, badge |

## Needs eyes on a device

Every screen below is L1 until a person looks at it. The visual result cannot be
verified from a Linux build.

1. Shell: the mini-player stays above the tab bar on every tab and after
   dismissing a modal detail sheet, and the last scroll row clears it.
2. Mini player: tint changes with artwork, text stays readable over bright
   artwork, and controls remain 44 pt.
3. Now Playing: sheet swipes down, artwork fits a 4.7-inch screen, scrubber seeks,
   tint fades cleanly in dark and light.
4. Queue: medium detent is usable, reorder handles work.
5. Home: grid tiles and shelves align; long titles truncate without pushing
   controls.
6. Search: chips fit on one line, top result and rows share spacing, keyboard
   does not cover results.
7. Library: chips and sort menu fit, pinned Favorites does not duplicate rows.
8. All screens at the largest Dynamic Type size, with Reduce Motion and Reduce
   Transparency enabled.
9. System, Light and Dark appearances remain legible across sheets, alerts,
   navigation bars and the mini-player.

## Implementation status

The baseline table above records the state before this pass. The following
changes are now on `development`:

| area | change | verification |
|---|---|---|
| Theme | adaptive light/dark colors, red state accent, high-contrast transport tokens, tight radii, technical type and motion tokens | L1 |
| Appearance | persisted System/Light/Dark preference in Settings, applied at the app boundary | L1 + host tests |
| Shared components | rectangular chips, marked section headers, bordered artwork, red active-state rows, high-contrast play button, thin scrubber, technical badges | L1 |
| Shell | one mini-player definition applied to each tab root so scroll content is inset on every tab | L1 |
| Mini player | dark artwork-tinted surface with white text, 44 pt controls, red progress and favorite state | L1 |
| Now Playing | artwork-derived background with an intentional light treatment, technical source caption, bordered artwork, accent repeat marker, queue, badge, cache and AirPlay | L1 |
| Queue | medium/large sheet, marked section headers, real jump/reorder/remove | L1 |
| Home | technical greeting, two-column quick access, marked shelves, active-track marker, separators | L1 |
| Search | focused-field accent, marked top result, result-type chips, separated rows and recents | L1 |
| Library | marked favorites row, accent heart, filter chips, download swipe, sort and separators | L1 |
| Downloads | permanent store under Application Support, explicit removal, no cache overlap | L1 + host tests |
| Source detail | Monochrome and YouTube Music capability screens; no fake setup controls | L1 |
| Cache | five-song rolling LRU, protected loaded entry, clear-on-launch opt-in, five-dot meter and dot-matrix numerals | L1 + host tests |
| Theme | `ThemePalette` light/dark tokens, WCAG contrast tests, 20 pt cards, 56 pt rows, 16 pt screen padding, 24 pt sections | L1 + host tests |
| Now Playing | core snapshot and remote-command routing, download/cache source badges | L1 + host tests |

Host tests: 198 tests in 26 suites passed at the last recorded run. The iOS
arm64 build-only check passed after every commit. No device is attached, so no
screen reached L4 or Human verification.

### What still needs a person

1. The mini-player inset must be checked on each tab and on pushed detail
   screens; SwiftUI safe-area behavior cannot be observed from the build host.
2. The light appearance is new. Check every surface, sheet, toolbar, alert and
   the artwork tint for contrast in both appearances.
3. Check the red accent is limited to selection, progress and active state, and
   that the primary play button still reads as the strongest control.
4. Check large Dynamic Type and VoiceOver traversal on the shared rows, chips,
   top result, transport controls and queue.
5. Check the mini-player text against bright artwork; the tint is clamped but
   only a device can confirm the final contrast.
