# Upstream web-app audit (Monochrome PWA)

Static reading of tracked source on 2026-10-22; no network, build, or execution.
Claims are file:line only; remote-host behavior is **Unverified**. Describes the
upstream app, not the native rebuild.

## 1. Stack & entry points

Vanilla ES modules + Vite 7, PWA via `vite-plugin-pwa` (`package.json:7`, `vite.config.ts:97`).
`index.html:150` loads `/js/app.js` as the only module entry; `index.html:155-156` define the
single `<audio id="audio-player">` and `<video id="video-player">` used for playback;
`index.html:114-148` is a blocking theme script only.

Boot (`js/app.js:360`): `HiFiClient.initialize` (`:406`) → `MusicAPI.initialize` (`:425`) → read
`playback-quality`, default `HI_RES_LOSSLESS` (`:430`) → `Player.initialize` (`:433`) →
`UIRenderer.initialize` (`:438`) → settings (`:571`) → event wiring (`:584-595`). Service worker
registers at `js/app.js:2644` (`registerType: 'prompt'`, `vite.config.ts:98`).

Modules: `js/music-api.js` facade, `js/tracks-api.js` catalog+stream API, `js/api.js` legacy
Tidal/HiFi client (metadata, downloads), `js/player.js` audio engine, `js/events.js` media
bindings, `js/ui.js` rendering, `js/db.js` IndexedDB, `js/storage.js` localStorage settings,
`js/accounts/*` auth+sync. `src/main.tsx` is a Preact shell not referenced by any HTML/config, so
it is not a boot path. `functions/*` are Cloudflare Pages Functions for OG-tag HTML
(`functions/track/[id].js:206-255`), not client API routes.

## 2. Search

UI search → `MusicAPI.search` (`js/ui.js:5015`, `js/commandPalette.js:850`).

- Host `https://tracks.monochrome.st` (`js/tracks-api.js:8`); `GET /search?q=<query>` (`:467`);
  scoped `/search/tracks?q=&limit=` (`:517`), `/search/releases?q=&limit=` (`:557`),
  `/search/artists?q=&limit=` (`:596`).
- Headers: `Accept: application/json` only, no auth/cookies (`js/tracks-api.js:418-424`);
  2 retries on 502/503/504 (`:426-441`).
- Response: top-level `{tracks, releases, artists, playlists}` arrays (`js/tracks-api.js:256-293`);
  paging wrappers are synthesized client-side, server paging ignored.
- Fallback order (`js/music-api.js:111-137`): tracks API → Apple Music
  `https://api.music.apple.com/v1/catalog/<storefront>/search` (`js/apple-music-api.js:751`; token
  from `https://am-mint.binimum.org/token`, `:2,122`) → legacy HiFi `/search/?q=|s=|a=|al=|p=|v=`
  (`js/api.js:687,769,825,851,876,900`).
- Suggestions = tracks search `limit=8` (`js/tracks-api.js:624-643`).

## 3. Track / album / artist metadata mapping

- Track (`js/tracks-api.js:101-127`): `trackId|id`→id, `title`, `duration` (ms if >1000, `:94-99`),
  `explicit`, `isrc`, `artists[].{artistId,id,name,avatar}`→artist(s),
  `releaseId|release.id`→album.id, `albumTitle|releaseTitle|release.title`→album.title,
  `artwork|cover`→cover/image/imageId, `releaseDate`, `trackNumber`, `discNumber`,
  `playable===false`→isUnavailable; quality hardcoded `LOSSLESS` (`:123-124`).
- Album (`:173-193`): `releaseId`, `title`, `artists`, `cover`, `releaseDate`, `trackCount`,
  `releaseType`, `label`, `copyrights[0].text`.
- Artist (`:207-223`): `artistId`, `displayName|name`, `avatar|picture`, `bio|biography`,
  `username`, `banner`.
- Playlist (`:236-248`): `playlistId`, `title`, `description`, `thumbnail` (only absolute http),
  `trackCount`, `ownerId`.
- Detail: album `GET /releases/{id}` → `{...release, tracks[]}` (`js/tracks-api.js:662-679`);
  artist `GET /artists/{id}` → `{...artist, albums, singles, compilations, topTracks}`
  (`js/tracks-api.js:716-767`).
- UI consumes `album.cover`, `album.releaseDate`, `artist.name`, `title`, `duration`, `explicit`
  (`js/ui.js:928-957,1442,4480`). Covers are Tidal CDN templates
  `https://resources.tidal.com/images/<slug>/<size>x<size>.jpg` (`js/api.js:3305-3306`); absolute
  `artwork` URLs pass through (`js/tracks-api.js:81,115`; `js/api.js:3301-3303`).

## 4. Stream / URL retrieval (most important)

**Shipping path: one unauthenticated progressive HTTP file.**

1. `Player.playTrackFromQueue` calls `api.getStreamUrl(trackId, quality)` (`js/player.js:1506`;
   preload `:670`).
2. `MusicAPI.getStreamUrl` calls `TracksStreamerAPI.resolveTrackStream`, then
   `TracksStreamerAPI.getStreamUrl` (`js/music-api.js:489-505`).
3. `getStreamUrl` returns `https://tracks.monochrome.st/track/<id>` (`js/tracks-api.js:788-806`):
   no query params, no headers, no token.
4. Player assigns it directly: `element.src = getProxyUrl(streamUrl)` (`js/player.js:838`);
   `getProxyUrl` is the identity function (`js/proxy-utils.js:3-6`). Result: progressive FLAC —
   not HLS, not DASH, not blob-decoded.
Endpoint: GET, no body, `cache: 'no-store'` on download (`js/api.js:3196-3199`). The client has no
`Range`/`bytes=` handling; seeking is the browser's. Response is raw audio bytes parsed as a
`Blob` with `audio/flac` assumed (`js/api.js:3220-3221`), magic-byte sniffed for the filename
(`js/utils.js:236-255`). The descriptor always claims `quality:'LOSSLESS'`, `qualityDisplay:'FLAC'`,
`codec:'flac'`, `mediaMimeType:'audio/flac'`, `lossless:true`, `playbackType:'direct'`
(`js/tracks-api.js:792-805`); the requested tier is only echoed as `qualityRequested` (`:797`).
**Quality tiers are not honored on the stream path.** The UI still offers
`HI_RES_LOSSLESS|LOSSLESS|HIGH|LOW|DOLBY_ATMOS_*` (`js/utils.js:34-56`), so the player's
`HI_RES_LOSSLESS`→`LOSSLESS` retry is a no-op (`js/player.js:1670-1673`).
ID resolution (`js/tracks-api.js:818-894`): `tracksTrackId|recordingId` direct (`:823-826`);
`tracks:`/`mono:` prefix stripped (`:828-831`); 17-20 digit snowflake direct (`:834-836`);
otherwise `GET /search/tracks?q=<artist title>&limit=6` (`:856-860`) with fuzzy score (ISRC=200,
exact title=100, artist=50, duration ±3 s=25; `:348-395`), threshold ≥85 (`:879`). Misses are
negatively cached (`:863,888`).
Failover: tracks API has none — single hard-coded host, transient retries only
(`js/tracks-api.js:8,414-445`). Legacy HiFi `fetchWithRetry` rotates instances and advances on 429,
401 `subStatus 11002`, 5xx, and network errors, max `instances.length*2` attempts
(`js/api.js:188-247`), rewriting Tidal URLs through `tidal-proxy.monochrome.tf`
(`js/proxy-utils.js:8-14`). Instance loading is effectively dead: `apiSettings.INSTANCES_URLS`
is `[]` (`js/storage.js:8`), so the fallback is always `https://tracks.monochrome.st` (`:84,110`).
`public/instances.json` has no consumer (repo-wide grep); `INSTANCES.md:1-2` says it is outdated.
Dev mode redirects all legacy calls to `{devBaseUrl}/…`, default `http://127.0.0.1:8000`
(`js/storage.js:3392-3397`; `js/api.js:250-262`), streaming via
`GET {devBaseUrl}/trackManifests/?id=&quality=&adaptive=false&formats=…` (`js/api.js:1832-1853`).
Present but not on the shipping stream path:

- Legacy `LosslessAPI.getStreamUrl` also delegates to the tracks API (`js/api.js:2791-2846`), so
  the same FLAC URL wins.
- "Unified Playback": `GET {base}/api/v2/track/?track=&artist=&album=&isrc=&duration=&intent=&quality=`
  with `Authorization: Bearer` + `X-Turnstile-JWT` (`js/api.js:2442-2471,2503-2518`). Envelope:
  `schema_version` 1/2 plus `playback[]` `{url, kind: audio|manifest, delivery: direct|dash|hls,
  source, quality, codec, mime_type, encryption.key_id, replay_gain, waveform}`
  (`js/api.js:2561-2769`). Disabled: `isEnabled()` returns `false`, `getApiToken()` returns `''`
  (`js/storage.js:3193-3231`).
- Tidal native: OAuth `POST https://auth.tidal.com/v1/oauth2/token` (`js/HiFi.ts:1237`); manifest
  `GET https://openapi.tidal.com/v2/trackManifests/{id}?adaptive=&manifestType=MPEG_DASH&uriScheme=HTTPS&usage=PLAYBACK&formats=…`
  (`js/HiFi.ts:1486-1510`); fallback `https://api.tidal.com/v1/tracks/{id}/playbackinfo`
  (`:1466-1475`). `attributes.uri` is fetched then base64-encoded as `info.manifest`
  (`js/api.js:1713-1742`), reachable only via `fetchWithRetry`'s native branch and never for
  `type:'streaming'` except `/track`/`/trackManifests` (`js/api.js:265-277`).
- Dead Deezer fallback `GET https://dzr.tabs-vs-spaces.wtf/stream/?isrc=&format=`
  (`js/api.js:1900-1927`, `js/storage.js:3244-3267`); `getDeezerStreamUrl` has no callers.
- Client HLS/DASH code exists for descriptors that request it — Shaka `js/player.js:212-228`, HLS
  `js/player.js:1009-1027` — but descriptors are currently always `playbackType:'direct'`
  (`js/tracks-api.js:801`).
Headers/expiry: the stream GET sends no auth or cookies (`js/api.js:3196`) and no client
signature. Comments claim "single-use"/"short-lived signed" URLs (`js/api.js:3179`;
`js/player.js:1626-1628`), while `usesSingleUsePlaybackUrls()` returns `false`
(`js/api.js:135-137`). Actual server expiry/CORS is **Unverified**. Both media elements use
`crossorigin="anonymous"` (`index.html:155-156`), so CORS on stream/art hosts is required for
Web Audio.

## 5. Playback & queue

`Player` wraps the `<audio>` element plus a second `Audio` for crossfade/preload
(`js/player.js:50-61`); the Web Audio EQ/binaural graph is `js/audio-context.js:98,475-499`.
Playback starts in `playTrackFromQueue` (`js/player.js:1139`), skips unavailable/blocked tracks
(`:1152-1164`), then branches native vs Shaka (`:1646-1659`). Preload fetches exactly one next
track when ≤45 s remain (`:623-642,644-701`). Track end: media `ended` →
`playNext(0,{preserveGestureToken:true})` (`js/events.js:583-596`); `playNext` handles repeat-one,
advance, radio/autoplay append, repeat-all (`js/player.js:2054-2151`); `playPrev` mirrors it
(`:2418`). Queue/shuffle/repeat live in memory (`:2561-2601`) and persist under localStorage
`monochrome-queue` (`js/storage.js:2209-2236`; restore `js/player.js:438-448`). Media Session uses
`@capgo/capacitor-media-session` (`js/player.js:534-590`); browser behavior is Unverified.

## 6. Library / favorites / playlists

Local-first IndexedDB `MonochromeDB` v11: `favorites_tracks|videos|albums|artists|playlists|mixes`,
`history_tracks`, `user_playlists`, `user_folders`, `settings`, `pinned_items`
(`js/db.js:12-14,55-97`); favorite toggle `js/db.js:225-250`; playlists `js/db.js:661-890`. Cloud
sync is opt-in: `syncManager` runs after local writes (`js/events.js:490,675,1612`), using
`better-auth` at `https://auth.monochrome.st` (`js/accounts/config.js:4-25`) and bearer/cookie auth
(`js/accounts/authApi.js:7-17`). Data host `https://data.monochrome.st`
(`js/accounts/pocketbase.js:7`); endpoints `GET/POST /api/sync` (`:35,123`),
`GET /api/public/playlists/{uuid}` (`:450`), `GET /api/users/{username}` (`:516`),
`POST /api/me/profile` (`:549`). A PocketBase SDK client is constructed (`:13`) but sync traffic
uses the fetch wrappers. Collections: `app_users`, `profiles`, `library_items`, `history_items`
(`database/pb_schema.json:9,97,305,413`; `database/README.md:5-7`).

## 7. Cross-cutting

**Lyrics — implemented.** LRCLIB `GET https://lrclib.net/api/get?track_name=&artist_name=&album_name=&duration=`
(`js/lyrics.js:468-510`); Genius annotations through `https://api.allorigins.win/raw?url=` +
`api.genius.com/search|/referents` (`js/lyrics.js:115,139`). Genius tokens are hard-coded in client
JS (`js/lyrics.js:100-107`; values not reproduced). Rendering via `am-lyrics` (`js/lyrics.js:28`).
**Downloads — implemented.** `downloadTrack` resolves the same FLAC URL, reads the body to a Blob,
post-processes with ffmpeg, embeds tags via TagLib, then saves to browser download or a File System
Access folder handle (`js/api.js:3050,3196-3231,3257`; `js/downloads.js:348,564-655,1151`).
DASH/HLS download branches exist for manifest URLs (`js/api.js:3135-3175`), but all MP3/AAC options
are client-side transcodes of FLAC (`js/ffmpegFormats.ts:1-40`).
**Auth/persistence — implemented, official hosts only.** Self-hosting breaks accounts and streaming
per README (`README.md:107-112`). Local state = localStorage feature singletons (~289 calls in
`js/storage.js`) plus queue and IndexedDB stores; export/import `js/db.js:481-560`.
**Settings — implemented.** `js/storage.js:6,485-3403`; folder handles and speaker profiles in the
IndexedDB `settings` store (`js/db.js:91-92`, `js/app.js:459`).
**Caching — implemented.** `APICache`: 200-entry memory map + IndexedDB `monochrome-cache/responses`,
30-min TTL (`js/cache.js:2-8,13-50`), pruned every 5 min (`js/api.js:119-124`). Tracks API keeps
only in-memory maps (`js/tracks-api.js:403-408`), lost on reload.
**Error handling — mixed.** HiFi failover and auth/rate-limit distinction
(`js/api.js:188-247,302-321`); tracks API throws status text and retries only 502-504
(`js/tracks-api.js:414-445,469-471`). Player swallows generic failures (`console.error`) and
notifies only for `UNSUPPORTED_PLAYBACK_CODEC`/`STRICT_QUALITY_UNAVAILABLE`
(`js/player.js:1689-1694`). Sentry has a hard-coded DSN (`js/sentry.js:6`); offline banner
`js/app.js:286-300`.
**Docs-only / broken.** README's "Multiple API instance support with failover" (`README.md:85`)
does not apply to the shipping search/stream path (single host, `js/tracks-api.js:8`).
`INSTANCES.md:1-2` self-declares outdated; `public/instances.json` is unreferenced;
`src/main.tsx` and `functions/` are not part of the client.

## 8. License & data source

Apache License 2.0 (`license:2-4`; `package.json:34`), copyright `Copyright 2026 Monochrome Team`
(`license:190`). No `NOTICE` file exists. §4 obligations (`license:93-115`): give recipients the
License, mark modified files, retain copyright/patent/trademark/attribution notices, reproduce any
NOTICE file; derivative distributions must stay Apache-2.0 compliant with the patent grant (§3) and
warranty disclaimer (§7).

Data source/terms: no content license or ToS is stated in README or INSTANCES.md. README says the
streaming API accepts only official instances and self-hosting cannot stream (`README.md:107-112`),
and documents the third-party Apple token minter (`README.md:158-162`). `INSTANCES.md:56-61`
disclaims community instances ("use at your own risk"). Audio is Tidal-derived
(`js/HiFi.ts:1446,1497`) with no in-repo rights statement; the upstream data source's
legality/terms are **Unverified**.
