# Native UI audit and redesign plan

Date: 2026-10-23. Audit of the SwiftUI layer before the redesign. Nothing here was
rendered; visual results are L1 at most.

## Current inventory

| screen / component | file | state |
|---|---|---|
| App entry | `Sources/Monochrome/App.swift` | `@main`; forces dark appearance |
| Shell | `Sources/Monochrome/ContentView.swift` | three classic tabs; player in a full-screen cover; mini player inset applied to each tab |
| Mini player | `Sources/Monochrome/MiniPlayerView.swift` | flat bar; artwork, title, badge, play/pause, next, progress |
| Now Playing | `Sources/Monochrome/PlayerView.swift` | artwork, title, favorite, seek, previous/play/next, repeat, queue |
| Queue | `Sources/Monochrome/QueueView.swift` | list with jump, reorder and remove |
| Home | `Sources/Monochrome/HomeView.swift` | greeting, recents shelf, favorites list, empty state |
| Search | `Sources/Monochrome/SearchView.swift` | pinned field, persisted recents, songs/albums/artists sections, debounced search |
| Library | `Sources/Monochrome/LibraryView.swift` | imported/favorites segments, import, swipe favorite/delete |
| Album and artist | `Sources/Monochrome/CatalogDetailViews.swift` | detail sheets with real catalog data |
| Settings | `Sources/Monochrome/SettingsView.swift` | host, cache summary, cached-song list |
| Shared row | `Sources/Monochrome/TrackRow.swift` | artwork, title, artist, badge, favorite marker, duration |
| Shared artwork | `Sources/Monochrome/TrackArtwork.swift` | remote image, local embedded image, placeholder |
| Tokens | `Sources/Monochrome/Theme.swift` | spacing, corner radius, screen padding, glass helpers |
| Bar model | `Sources/MonochromeCore/NowPlayingBar.swift` | derived title, subtitle, badge, progress, loading/failure |

## Findings to address

1. `ContentView` declares a private `enum Tab` that shadows `SwiftUI.Tab`. It is
   renamed before any typed-tab API is considered.
2. The player uses `.fullScreenCover`, so a downward swipe cannot dismiss it. It
   becomes a large sheet with interactive dismissal and keeps the chevron.
3. `.nowPlayingBarInset` is attached to each tab, so three `MiniPlayerView`
   instances exist and each supplies its own `.bar` background. The shell owns
   one inset above the tab bar instead.
4. `MiniPlayerView` is a flat bar with no card, tint, favorite control or
   artwork-derived color. The core `NowPlayingBar` model is kept and extended
   only with presentation values.
5. `HomeView` hardcodes `Color(white: 0.05)` and accepts an unused
   `onOpenPlayer` closure. Both are removed.
6. Colors, radii and spacing are inline in several views. `Theme` becomes the
   single source of tokens.
7. There is no artwork tint and no quick-access merge, search partitioning,
   library sort/filter or shared chip/scrubber logic. Each lands in
   `MonochromeCore` with host tests.

## Target per screen

| screen | target |
|---|---|
| Shell | Home/Search/Library tabs; one mini-player inset; player opens as a large sheet |
| Mini player | floating tinted card, 40–44 pt artwork, title/artist, badge, favorite, play/pause, next, 2 pt progress, loading and retry states |
| Now Playing | tint fading into near-black, chevron and source caption, large artwork, favorite, scrubber with elapsed/remaining, previous/play/next/repeat, queue sheet, cached badge, AirPlay route picker |
| Queue | medium/large sheet; current track then upcoming tracks; jump, reorder and remove only |
| Home | greeting and logo; two-column quick-access grid; “Listen again”; “Your favorites” with See all; empty state |
| Search | pinned field; recent searches; chips only for returned types; top result; shared rows with supported actions |
| Library | title and sort menu; All/Favorites/Local files chips; pinned Favorites row; import action; shared rows |
| Shared | `Chip`, `ShelfHeader`, `ArtworkTile`, upgraded `TrackRow`, `RoundPlayButton`, `Scrubber` |

## What shipped (L1, not rendered)

| area | file | state |
|---|---|---|
| Tokens | `Theme.swift` | colors, spacing, radii, sizes and type; glass fallback |
| Artwork tint | `ArtworkTint.swift`, `ArtworkTintStore.swift` | average color sampled once per track, cached, darkened by tested core math |
| Shared UI | `Chip`, `ShelfHeader`, `ArtworkTile`, `RoundPlayButton`, `Scrubber`, `TrackRow` | one responsibility each |
| Shell | `ContentView.swift` | `AppTab`, one mini-player inset, large player sheet |
| Mini player | `MiniPlayerView.swift` | floating tinted card, favorite, play/pause, next, progress, retry |
| Now Playing | `PlayerView.swift`, `AirPlayRoutePicker.swift` | tinted background, top bar, large artwork, scrubber, transport, queue, badge, AirPlay |
| Queue | `QueueView.swift` | current track and upcoming section; jump, reorder, remove |
| Home | `HomeView.swift`, `QuickAccess.swift` | quick-access grid, Listen again, Your favorites, empty state |
| Search | `SearchView.swift`, `SearchResults.swift` | pinned field, recents, result-type chips, top result, row actions |
| Library | `LibraryView.swift`, `LibraryQuery.swift` | filter chips, sort, pinned Favorites, import, local delete |
| Tests | `Tests/MonochromeCoreTests` | tint, quick-access merge, search partitioning, library query |

## Constraints confirmed in the SDK

The installed SDK is newer than the deployment target. The package stays on iOS
17. APIs used by the redesign are checked in the installed SwiftUI interfaces;
newer conveniences are used only behind availability checks. System tab bars,
navigation bars and sheets keep their own material instead of being painted
over.

## Needs eyes on a device

Every screen below is L1 until a person looks at it. No device was attached during
this work (`idevice_id -l` returned `ERROR: Unable to retrieve device list!`), so no
deploy or device log was produced.

1. Shell: mini player sits above the tab bar on every tab and pushed screen, and
   does not cover the last row.
2. Mini player: tint changes with artwork, stays readable over bright artwork,
   and its controls remain 44 pt.
3. Now Playing: sheet swipes down, artwork fits a 4.7-inch screen, scrubber
   seeks, tint fades cleanly.
4. Queue: medium detent is usable, reorder handles work.
5. Home: grid tiles and shelves align; long titles truncate without pushing
   controls.
6. Search: chips fit on one line, top result and rows share spacing, keyboard
   does not cover results.
7. Library: chips and sort menu fit, pinned Favorites row does not duplicate
   rows below.
8. All screens at the largest Dynamic Type size, with Reduce Motion and Reduce
   Transparency enabled.
