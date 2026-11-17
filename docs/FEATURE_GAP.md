# Feature gap with the web app

Comparison against `monochrome-music/monochrome` (`upstream/main`). The table
covers every feature named in the upstream README plus the features this run
planned to add. "Native" is the state of this repository before the run.

Status values: **Exists**, **Partial**, **Missing**, **Out of scope**,
**Not applicable**.

## Audio quality

| Feature | Native | Evidence | Gate |
|---|---|---|---|
| Lossless streaming | Exists | `TrackURLResolver`, `TracksAPIClient.streamURL`; progressive FLAC from `track/{id}` | Allowed (same public host the app already uses) |
| Local files | Exists | `LocalFileService`, `LibraryStore`, `MetadataReader` | Not applicable |
| API response caching | Missing | No catalog response cache; audio cache only (`AudioCache`) | Not applicable |
| Quality tiers above 16-bit/44.1 kHz | Missing | Catalog serves one lossless FLAC per track; no tier parameter in `TracksAPIClient` | No data: upstream's higher tiers use the TIDAL token in `js/HiFi.ts:1208-1269`; the public tracks host has no tier parameter |

## Interface

| Feature | Native | Evidence | Gate |
|---|---|---|---|
| Dark, minimalist interface | Exists | `Theme`, `ThemePalette`, appearance setting | Not applicable |
| Animated album covers | Missing | No video cover code in the app | Blocked by policy: `functions/api/apple-video-cover.js` forwards an `Authorization` header to `amp-api.music.apple.com` |
| Custom themes + community store | Partial | Accent palettes (`AccentPreference`), System/Light/Dark; no theme presets or import/export. Store needs a backend | Store out of scope; presets/import/export in scope |
| Audio visualizer | Missing | No visualizer; equalizer tap exists (`EQTap`) | Blocked by proof: the tap cannot be shown to run for remote progressive items without a device; see D1 note below |
| Offline-capable app | Exists | Downloads (`DownloadStore`), audio cache, offline local files | PWA is not applicable to a native app |
| System media controls | Exists | `NowPlayingController`, `AudioSessionController`, `MPRemoteCommandCenter` | Not applicable |

## Library and organization

| Feature | Native | Evidence | Gate |
|---|---|---|---|
| Recently played | Exists | `HistoryStore`, `AppModel.recents` | Not applicable |
| Favorites library | Exists | `FavoritesStore`, Library favorites filter | Not applicable |
| Queue: shuffle, repeat, reorder, remove | Partial | Repeat (`RepeatMode`), reorder (`Queue.move`), remove, jump. No shuffle, play next, clear | Not applicable |
| Local playlists | Missing | No playlist model or store | Not applicable |
| Playlist import from other platforms | Missing | No file import beyond audio files | File import only: no platform URLs (out of scope) |
| Public playlists | Out of scope | — | Needs accounts and a backend |
| Smart recommendations | Missing | No event log or ranking | Partly: similar/radio data is token-gated (`js/HiFi.ts`); on-device ranking is in scope |
| Infinite radio | Missing | No radio queue | Partly: seed from on-device ranking; similar data blocked |
| Explore (Hot & New, genres) | Missing | No explore entry point | No data: `https://hot.monochrome.tf/` does not resolve from this host; `js/ui.js:3138` is the only source |
| Artist biography and links | Partial | Artist page shows name, top tracks, releases; ignores `bio`/`biography` fields | Allowed: `GET /artists/{id}` on the existing public host returns `bio`/`biography`, `externalLink`. No token needed |

## Lyrics and metadata

| Feature | Native | Evidence | Gate |
|---|---|---|---|
| Synced lyrics | Exists | `LyricsService`, `LRCLIBClient`, `LRCParser`, `LyricsTimeline` | Allowed (existing LRCLIB route) |
| Karaoke word-level lyrics | Missing | Line-level only | No data: LRCLIB returns line timings (`js/lyrics.js:491-499`); upstream builds TTML from those lines (`js/lyrics.js:570-618`), so there are no real word timings |
| Genius lyrics | Out of scope | — | Needs a token and scraping; lyric text is copyrighted |
| Downloads with metadata embedding | Partial | Downloads store the original FLAC (`DownloadStore`); no tag/cover writing or export | Not applicable |

## Integrations

| Feature | Native | Evidence | Gate |
|---|---|---|---|
| Account system, OAuth, sync, profiles | Out of scope | — | Needs accounts and a backend |
| Listening parties | Out of scope | — | Needs accounts and a realtime backend |
| Last.fm / ListenBrainz | Out of scope | — | Needs a third-party login |
| Unreleased music (ArtistGrid) | Out of scope | — | Unlicensed or leaked recordings |
| Discord embeds | Out of scope | — | Web-only |
| Multiple API instances with failover | Partial | `TracksAPIClient.get` rotates hosts but has no cooldown, no `Retry-After` handling and no user host list | Not applicable |
| Podcasts | Missing | No podcast code | Upstream route blocked (PodcastIndex key/secret in `js/podcasts-api.js:7-21`); a token-free Apple Search API + RSS route is allowed but not built in this run |
| Music videos | Missing | No video playback | Blocked by policy: upstream resolves TIDAL streams through the token in `js/HiFi.ts` |
| Keyboard shortcuts, command palette | Not applicable | — | Web-only |

## Source gate notes

- **Allowed and used:** `tracks.monochrome.st` catalog, stream resolution,
  artwork, lyrics; artist biography from the same host; user-supplied catalog
  hosts for failover.
- **Blocked by policy:** TIDAL API token paths (`js/HiFi.ts`,
  `functions/artist/[id].js`), Apple Music amplification with an
  `Authorization` header (`functions/api/apple-video-cover.js`), PodcastIndex
  signed requests, Genius and scraping.
- **No data:** explore host does not resolve; no word-level lyric source; no
  hi-res tier on the allowed host.
- **Not built because proof is missing:** the audio visualizer. The equalizer
  tap exists, but whether it runs for progressive remote playback can only be
  shown on a device, which this run does not have. Shipping a visualizer that
  stays flat for streamed music would be a fake feature.

Live checks were limited to the truthful app User-Agent, no credentials and no
custom headers. Only response shape was retained.
