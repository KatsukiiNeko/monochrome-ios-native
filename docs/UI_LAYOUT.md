# UI layout spec

The screen structure and navigation of the app. The visual language section
records what already exists and must not be redesigned; everything after it is
the target composition for each screen. Colors, type, spacing and radii are
always referenced through `Theme`, never written as literals.

## Visual language (existing)

One identity across every screen: a monochrome palette, an accent that is
either a signal color or taken from the current artwork, a 5x7 dot-matrix
motif, technical monospaced metadata, flat surfaces, hairline outlines and
small radii.

### Color tokens (`Theme.swift`)

| Token | Role |
|---|---|
| `background` | Screen and sheet background |
| `surface` | Cards, fields, chips, unselected rows |
| `elevated` | One step above a surface; icon plates, artwork placeholders |
| `sunken` | Fields and selected segments inside a surface |
| `border` | Hairlines around cards and fields |
| `separator` | Quiet dividers and idle progress tracks |
| `primaryText`, `secondaryText`, `tertiaryText` | Text ramp |
| `destructive` | Removal actions only |
| `primaryAction`, `onPrimaryAction` | High-contrast transport fills |
| `onTintPrimary`, `onTintSecondary`, `onTintSeparator` | Text and rules inside the always-dark mini-player card |
| `accentColor(preference:artwork:)` | The one visible accent |
| `accentOnTint(...)` | Accent inside the dark card |

### Spacing and sizes

| Token | Value | Use |
|---|---|---|
| `sectionSpacing` | 28 | Between sections of a scroll screen |
| `screenPadding` | 20 | Horizontal screen inset |
| `rowSpacing` | 12 | Between a row's artwork and text |
| `hairline` | 1 | Every border and rule |
| `cardPadding` | 14 | Inside a card |
| `rowMinHeight` | 52 | List row minimum |
| `iconSize` | 28 | Icon plate |
| `controlSize` | 44 | Every tappable control |
| `miniArtworkSize` | 42 | Mini-player artwork |
| `miniPlayerHeight` | 64 (new) | Minimum height of the mini-player card and of the space it reserves |
| `scrubberHitTarget` | 44 (new) | Vertical touch target of the player scrubber |
| `sectionMarker`, `markerHeight` | 5, 13 | Accent tick before a section title |

### Radii

`corner` 12 (containers), `cardRadius` 10 (cards and fields), `artworkRadius` 2
(rows and mini-player), `albumRadius` 4 (player and detail artwork), `tileRadius`
6 (grid tiles and icon plates), `chipRadius` 5 (chips).

### Type ramp

`screenTitle`, `heroTitle`, `sectionTitle`, `shelfTitle`, `rowTitle`,
`listRowTitle`, `rowSubtitle`, `caption`; and the technical faces `technical`,
`micro`, `time`, `value`, all monospaced. Sizes come from semantic text styles,
so Dynamic Type scales them.

### Motif components

| Component | Appearance | Used on |
|---|---|---|
| `DotMatrixText` / `DotMatrixLabel` | 5x7 dot glyphs, monospaced fallback at accessibility sizes | Greeting, `Now Playing` label, queue position, technical headers |
| `TechnicalSectionHeader` | Accent tick, uppercased mono title, optional mono meta | `List` sections (Library, Settings, downloads) |
| `ShelfHeader` | Accent tick, shelf title, optional mono meta and See all | Scroll shelves (Home, Search) |
| `TechnicalLabel` | Uppercased monospaced micro label | Metadata under titles, counts |
| `TechnicalIcon` | SF Symbol in a square plate, accent or secondary | Row leading icons |
| `QualityBadgeLabel` | Bordered mono badge | Format and quality, on cards and the player |
| `Chip` | Bordered pill, accent border and text when selected | Library filters, search result filters |
| `TrackRow` | 48-52 pt artwork, title, subtitle, favorite and now-playing marker | Every track list |
| `TrackArtwork` | Square artwork with radius and placeholder | Rows, tiles, player |
| `ArtworkTile` | Vertical artwork, title, subtitle | Carousels and grids |
| `RoundPlayButton` | Filled circle with play/pause/loading | Player transport |
| `Scrubber` | 2 pt capsule track, 6 pt while dragging, optional thumb | Player |

### Rules for a new or rebuilt screen

1. Background is `Theme.background`, ignoring the safe area; content is a
   scroll view or `List` with `scrollContentBackground(.hidden)`.
2. Horizontal inset is `Theme.screenPadding`; sections are separated by
   `Theme.sectionSpacing`.
3. Every section has a header: `ShelfHeader` on scroll shelves,
   `TechnicalSectionHeader` in a `List`.
4. Cards use `Theme.surface`, `Theme.cardRadius`, a `Theme.border` hairline and
   `Theme.cardPadding`.
5. Text uses the ramp above. Anything structural or numeric is monospaced and
   uppercased through `TechnicalLabel`.
6. Accents come from `@Environment(\.accentColor)`; never a literal.
7. Every control is at least `Theme.controlSize` and has a VoiceOver label.
8. Motion uses `Theme.quick`, `Theme.standard` or `Theme.artwork`, and is
   skipped when Reduce Motion is on.
9. Glass is used through `glassSurface` and `glassControlStyle` only, so the
   Reduce Transparency fallback stays intact.
10. A new token or motif piece is added to `Theme` in this grammar and recorded
    here. No screen imports a color, font, shape or icon from anywhere else.

## Shell

Three tabs, in this order: Home, Search, Library. Icons `house`,
`magnifyingglass`, `music.note.list`. The tab bar keeps the system appearance
and the accent tint.

Every tab root is a `NavigationStack` whose scroll content sits inside
`nowPlayingBarInset`, so the mini-player never covers the last row. Screens
pushed inside a tab inherit that inset. Settings is a sheet with its own
`NavigationStack` and needs no inset.

Sheets: full player (`.large`, swipe down to dismiss), Settings, queue, audio
specification, lyrics, equalizer, album and artist details, playlist import and
export, and the download file picker. All use `Theme.background` and the
accent.

## Home

1. Header: dot-matrix `Monochrome`, greeting, one line of orientation, hairline.
2. Quick access: two-column grid of up to six recently played or favorite
   tracks; one column at accessibility text sizes.
3. For You: the recommendation shelf, or its own empty line when the profile is
   too small to recommend.
4. Listen again: horizontal artwork carousel of recent plays.
5. Recently downloaded: up to six completed downloads, as rows. Hidden when
   nothing is downloaded.
6. Stations: radio seeds taken from the most played artists in favorites and
   recents; each button starts a real radio. Hidden when there is no seed.
7. Favorites: up to five rows with a See all link into Library.
8. Empty state for a new listener: one search action and one import hint.

States: `RecommendationShelf` shows its own loading line and its own error with
Retry; the rest of Home is local data, so it renders immediately. Pull to
refresh re-runs recommendations and downloads.

## Library

1. Filter chips: All, Favorites, Downloaded, Local.
2. Pinned Favorites row (count and link into the favorites filter).
3. Browse: `List` section with Playlists, Podcasts and Downloads. These links
   exist in every filter, not only the downloaded one.
4. Tracks: the current filter and sort, one `TrackRow` per track with the
   existing context menu, swipe-to-favorite and swipe-to-download or delete.
5. Sort menu in the leading toolbar slot, import in the trailing slot.

States: the tracks section shows one empty state per filter (all, favorites,
downloaded, local), each with the action that fills it. Playlists show their own
error alert. Importing shows a glass progress card.

## Detail screens

- Album: close action, large artwork with title, artist and year, then
  `Play`, `Shuffle`, favorite and download (when the source supports it), then
  the track list as `TrackRow`s.
- Artist: close action, avatar, name, `Start radio`, top tracks, then the
  releases carousel and the full release list.
- Playlist: header with title, count and duration, transport actions, then the
  rows with reorder, remove and play-next, plus rename, duplicate, export and
  delete in the toolbar.
- Downloads: in-progress section above the completed section, a total-size
  label, per-row progress and a remove action, plus the same empty state as the
  Library download filter.
- Podcasts: search field, show results, then episodes of the selected show as
  rows with duration.

Every detail screen shows one loading state, one error state with Retry, and
never an empty result before a request has finished.

## Search

1. Pinned search field, always visible. No pull-down.
2. With an empty query: recent searches, or one quiet hint.
3. With a query: filter chips (All, Songs, Albums, Artists) only for kinds that
   have results, then Top result, Songs, Albums, Artists.
4. Loading: skeleton rows built from `Theme.surface` after a 150 ms grace, kept
   for at least 300 ms, static under Reduce Motion.
5. Empty: "no results" only for a finished request with the current query.
6. Failed: error text with Retry, never "no results".
7. Disabled catalog: one explanatory state with a link to Settings.

## Full player

Sheet with a dismiss chevron and a dot-matrix `Now Playing` label, one column,
top to bottom:

1. Artwork, square, at most 360 pt wide, `albumRadius`, hairline and shadow;
   scaled down on short screens rather than shrinking the controls.
2. Title (hero), artist, album as a technical label, favorite on the trailing
   edge.
3. One source/quality line: format chips through `QualityBadgeLabel`, the
   source word through `TechnicalLabel`, queue position as a dot-matrix label.
   Chips that do not fit drop off from the end, never wrap.
4. Error block with Retry when the state is failed.
5. Sleep timer row when armed.
6. Scrubber with elapsed and remaining times and a 44 pt touch target.
7. Transport: shuffle, previous, play/pause (72 pt circle), next, repeat.
8. Secondary actions as icon-only cells of equal width: lyrics, equalizer,
   queue, download (when eligible), AirPlay. The ellipsis menu holds queue,
   shuffle, add to playlist, sleep timer and download.

## Mini-player

Floating card with `Theme.surface` derived from the artwork tint, hairline,
shadow, `miniArtworkSize` artwork, one-line title with quality badge, subtitle
or failure text, favorite, play/pause or retry, next, and a 2 pt progress bar.
Minimum height `Theme.miniPlayerHeight`; it grows with Dynamic Type and the
reserved space grows with it.

## States

| Screen | Loading | Empty | Error |
|---|---|---|---|
| Home | Recommendation shelf line | Search action plus import hint | Recommendation error with Retry |
| Search | Skeleton rows, 150/300 ms rule | "No results" after a finished request | Message with Retry |
| Library | Glass import card while importing | One per filter, with its action | Playlist alert |
| Album, Artist | Progress view in the hero | Not applicable (a release always has tracks) | Message with Retry |
| Playlist | None (local data) | "No tracks yet" with an add action | Playlist alert |
| Downloads | In-progress section | "No downloads yet" | Metadata error label |
| Player | Play button shows a spinner | "Nothing playing" title | Error block with Retry |

## Testing hooks

- `LayoutSpec` in `MonochromeCore` holds the numbers tests assert:
  `miniPlayerHeight`, `scrubberHitTarget`, the skeleton grace and minimum, the
  player artwork width and compact breakpoint.
- `PlayerLayout` picks the player variant from a size.
- `SearchQueryState` is the pure search reducer; `SearchSkeletonState` is its
  timing.
- A source scan test fails when a feature view adds a literal color or a raw
  font size outside `Theme`.
