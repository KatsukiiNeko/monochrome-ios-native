# Streaming feasibility

> **Superseded decision (same day).** The facts below still hold, but the
> conclusion was revisited when the user explicitly asked for streaming to be
> implemented. The app now uses this endpoint as **Path A**, with a
> user-configurable host and no credential bypass. The rights caveat is stated
> in [`ONLINE_STREAMING_AUDIT.md`](ONLINE_STREAMING_AUDIT.md), and that file is
> the current decision record.

Checked live from Linux on 2026-10-22 with `curl`, plus source reading. No account,
no token, no proxy bypass, four requests total, no full download (1 KiB range).

## 1. How the upstream app gets audio

- `js/music-api.js:489-505` → `js/tracks-api.js:788-806` builds one URL:
  **`https://tracks.monochrome.st/track/<trackId>`** — no query, no headers, no token.
- `js/player.js:838` assigns it to `<audio>.src` through `getProxyUrl`, which is the
  identity function (`js/proxy-utils.js:3-6`). So the shipping path is a plain
  progressive file, not HLS, not DASH, not blob-decoded.
- Quality tiers are ignored on this path: the descriptor is hardcoded to
  `LOSSLESS`/`flac` (`js/tracks-api.js:792-805`).
- Failover does not exist on this path: one hard-coded host (`js/tracks-api.js:8`).
  `INSTANCES_URLS` is `[]` (`js/storage.js:8,84,110`), and the instance file is
  unreferenced.
- The official iOS app does something else entirely: Tidal ISRC lookup with a
  hardcoded token, then Qobuz provider instances (`monochrome-ios/.../MonochromeAPI.swift:487-546`).
  Same conclusion, worse mechanism.

## 2. Live contract check

```
GET https://tracks.monochrome.st/search/tracks?q=daft%20punk&limit=2
→ 200 application/json, 918 bytes
  { "tracks": [ { "id": "155102871061270528", "trackId": "...", "title": "One More Time",
                  "artistNames": ["Daft Punk"], "releaseId": "...", "artwork":
                  "https://tracks.monochrome.st/proxy/mi/<releaseId>-1A01.jpg",
                  "duration": 320000, "isrc": "...", "playable": true } ], ... }
```

```
GET https://tracks.monochrome.st/track/155102871061270528
Range: bytes=0-1023
→ 206, content-type: application/octet-stream, content-length: 1024
  content-range: bytes 0-1023/40572194
  accept-ranges: bytes, cache-control: public, max-age=31536000, immutable
  bytes: 66 4C 61 43 = "fLaC" → file(1): FLAC 16-bit stereo 44.1 kHz
```

So: no authentication, no signed URL, no expiry, byte ranges work, one track is
~40 MB of FLAC. `AVPlayer` can play progressive FLAC, so the *technical* contract
is usable (content-type is `application/octet-stream`, which is a known AVPlayer
risk that would need an on-device check — Unverified).

## 3. Classification of the source

This is **an unofficial relay of commercially licensed audio** (Tidal-derived per
`js/HiFi.ts:1446,1497`), operated by the Monochrome project on a single
unauthenticated host. The repository contains no content license and no terms for
the audio; `README.md:107-112` says self-hosting cannot stream, i.e. the backend is
a closed service, and `INSTANCES.md:52-61` disclaims community instances. Neither
the web app's Apache-2.0 license nor the missing license of the iOS project grants
any right to the audio.

That is not a legitimate source for a new client, so Path A is **rejected**: the
app would be a third-party player of a commercial catalog through an
unauthenticated mirror. Streaming stays documented but unimplemented.

## 4. Decision: Path B — local files

- Working playback of user-picked audio files from the Files app via
  `fileImporter` + `AVPlayer`.
- Files are **copied** into the app's Application Support library on import, so the
  player never depends on security-scoped bookmarks and nothing disappears when the
  picker's access ends. Storage cost is the trade-off; documented in the README.
- `MusicService` stays a protocol with `LocalFileService` as its only implementation,
  so a future Path A client is a new conforming type plus a settings switch, not a
  refactor.

## 5. What this rules out (and why it is written down)

No search, no album/artist browsing, no lyrics, no remote artwork: all of those
depend on the rejected backend. The app is a local library player with a queue,
Now Playing and background audio — the parts that work without anyone's catalog.
