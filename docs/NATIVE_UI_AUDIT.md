# Native UI audit and redesign direction

Date: 2026-10-23. Source audit before the Nothing-inspired visual pass. No
screen was rendered; visual results remain L1 unless a person inspects them.

## Actual current state

| screen / component | file | state |
|---|---|---|
| App entry | `Sources/Monochrome/App.swift` | `@main`; currently forces `.dark` |
| Shell | `Sources/Monochrome/ContentView.swift` | `AppTab` (no `Tab` shadowing); player is a large sheet; one mini-player inset on the `TabView` |
| Mini player | `Sources/Monochrome/MiniPlayerView.swift` | floating artwork-tinted card, favorite, play/pause, next, progress, retry |
| Now Playing | `Sources/Monochrome/PlayerView.swift` | tinted background, chevron, artwork, favorite, scrubber, transport, queue, badge, AirPlay |
| Queue | `Sources/Monochrome/QueueView.swift` | medium/large sheet; now playing and upcoming; jump, reorder, remove |
| Home | `Sources/Monochrome/HomeView.swift` | greeting, logo, quick-access grid, Listen again, Your favorites, empty state |
| Search | `Sources/Monochrome/SearchView.swift` | pinned field, persisted recents, result-type chips, top result, rows, menus |
| Library | `Sources/Monochrome/LibraryView.swift` | All/Favorites/Local chips, sort menu, pinned Favorites, import, local delete |
| Album and artist | `Sources/Monochrome/CatalogDetailViews.swift` | detail sheets with real catalog data |
| Settings | `Sources/Monochrome/SettingsView.swift` | host, cache summary, cached-song list |
| Shared row | `Sources/Monochrome/TrackRow.swift` | artwork, title, artist, badge, favorite marker, duration |
| Shared artwork | `Sources/Monochrome/TrackArtwork.swift` | remote image, local embedded image, placeholder |
| Tokens | `Sources/Monochrome/Theme.swift` | dark-only colors, spacing, radii, type, glass helper |
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
| Settings | preserve host and cache behavior; add the appearance selector only where it fits |
| Shared | `Chip`, `ShelfHeader`, `ArtworkTile`, `TrackRow`, `RoundPlayButton`, `Scrubber`, badge |

## Needs eyes on a device

Every screen below is L1 until a person looks at it. The visual result cannot be
verified from a Linux build.

1. Shell: the mini-player stays above the tab bar on every tab and pushed screen,
   and the last scroll row clears it.
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
