# Online streaming audit

Date: 2026-10-22. Read from `upstream/main` at `86dc77aa…` extracted to
`/tmp/monochrome-upstream` (never checked out into this tree). Live checks ran
from Linux with a truthful `User-Agent: MonochromeNative/1.0 (iOS; independent
client)` and no `Origin`/`Referer` header.

## How the web app actually gets audio

1. **Catalog and search** go to a dedicated tracks host:
   `js/tracks-api.js:8` defines `TRACKS_API_BASE_URL = 'https://tracks.monochrome.st'`.
   The client calls `/search/tracks`, `/search/releases`, `/search/artists`,
   `/releases/{id}` and `/artists/{id}` on it.
2. **Playback** builds a direct URL: `TracksAPI.getStreamUrl`
   (`js/tracks-api.js:786`) returns `{base}/track/{trackId}` with
   `quality: 'LOSSLESS'`, `codec: 'flac'` and `playbackType: 'direct'`
   (`js/tracks-api.js:790`–`801`). That is a progressive file, not a manifest.
   The quality argument is ignored; the tier is hardcoded.
3. **The token path is off.** A newer “unified playback” client exists
   (`js/api.js:2474`–`2512`, `GET {base}/api/v2/track/?…` with an API token), but
   `unifiedPlaybackSettings.isEnabled()` returns the literal `false`
   (`js/storage.js:3193`–`3202`) and its default base URL and token are empty
   strings. It cannot be enabled from the UI, and the token is an access
   control this client must not try to obtain.
4. **Multi-instance failover** in `js/api.js:195`–`241` belongs to the official
   hifi-api instance path, not to the tracks host. The tracks API uses one host
   and has no documented failover list.

## Live contract check

| request | result |
|---|---|
| `GET /search/tracks?q=daft%20punk&limit=2` | 200, JSON keys `tracks, artists, releases, playlists, topResults, users`; track: `id, trackId, title, artistNames[], releaseId, artwork, duration, isrc, playable, explicit` |
| `GET /search/releases?q=discovery&limit=2` | 200, `{releases:[…]}`; `id, releaseId, title, artistNames[], releaseDate, releaseType, label, artwork` |
| `GET /search/artists?q=daft%20punk&limit=2` | 200, `{artists:[…]}`; `id, name, avatar, bio` |
| `GET /releases/155102851176075264` | 200, 7.7 KB, includes `tracks[14]`; each track has `trackId, title, duration, artists[], artwork, trackNumber, discNumber, playable, recordingId` |
| `GET /artists/153542153123926016` | 200, 262 KB, includes `topTracks[4]`, `releases[]`, `albums[]`, `singles[]`, `bio` |
| `GET /track/155142491052445696` with `Range: bytes=0-1023` | 206, `content-type: application/octet-stream`, `accept-ranges: bytes`, body begins `66 4C 61 43` (`fLaC`) |
| `GET /proxy/mi/155102851176075264-1A01.jpg` | 200, `image/jpeg`, 640×640 |

Facts that shape the client:

- Durations are **milliseconds** (`337560` → 337.56 s).
- Search is a plain query parameter search; no cursor or pagination token was
  observed, only `limit`.
- Artwork is a plain JPEG URL; no auth, no referer required.
- The stream URL carries no signature and no expiry field, but it is still
  resolved at play time and never persisted (requirement, not necessity).

## Access assessment

- Nothing here is a bypass: no token, no cookie, no session, no `Origin` or
  `Referer` header, no official-client impersonation. These are the same
  unauthenticated requests the website makes, with this app's own UA.
- `README.md:112` says their *app API* only accepts official instances, so a
  self-hosted copy on a domain cannot stream. That is origin gating on the app
  API; the tracks host answered an independent client directly and is not part
  of that gate. We do not self-host and we do not claim to be an instance.
- The token-gated `/api/v2/track/` endpoint is not used and must stay unused.

## Rights picture — read this before distributing

- The catalog is Tidal-derived: the id shapes, `isrc`, `recordingId` and the
  `*-1A01.jpg` artwork naming match Tidal's public objects. Audio is relayed by
  `tracks.monochrome.st`, a third-party host.
- The repository carries **no terms of service, no content licence and no
  rights statement**. Its `license` file covers the source code (Apache-2.0)
  only, which says nothing about the audio.
- No permanent-download endpoint or download entitlement is documented. A
  progressive stream URL is not a download grant, so the app does not offer
  permanent catalog downloads or treat temporary cache entries as downloads.
- Keeping this as a personal build and distributing an app that streams the
  catalog are different acts. Do not publish it to TestFlight, the App Store or
  a public release without resolving that yourself.
- `INSTANCES.md` starts by saying it is outdated, so it is not a reliable
  contract for any host.

## Decision: Path A, with the base URL configurable (covers A′)

- Default base `https://tracks.monochrome.st`, the endpoint the shipping web
  client uses.
- Settings lets the user point at another base URL (for example their own paid
  HiFi endpoint, as the README's Dev Mode description allows) or clear it, in
  which case the app shows an explicit “streaming not configured” state.
- No credentials are shipped, none are stored, and no secret handling is added.
- Failover: an ordered list (user base URL first, default second), 10 s
  timeouts, in-session health memory. The upstream has no failover list for
  this host; the mechanism avoids inventing any host.

## Native playback limits and quality ceiling

- The only tier available on this path is **FLAC 16-bit / 44.1 kHz**
  (`LOSSLESS`), forced in the upstream code. The website's `HI_RES_LOSSLESS`
  tier is not exposed by the tracks API, so the native app's ceiling is CD
  quality.
- A progressive FLAC file is within `AVPlayer`'s ability; no HLS or DASH
  stitching is needed (and `AVPlayer` cannot play DASH).
- **Unverified risk:** the stream is served as `application/octet-stream`.
  AVFoundation normally sniffs container bytes, but only a device can prove it.
  Until then this is the top “needs eyes on a device” item.
- Malformed or error responses surface as a playback failure. The player
  re-resolves once, then shows an error with Retry.

## Endpoints the app will call

| purpose | method + path |
|---|---|
| track search | `GET {base}/search/tracks?q=&limit=` |
| album search | `GET {base}/search/releases?q=&limit=` |
| artist search | `GET {base}/search/artists?q=&limit=` |
| album detail | `GET {base}/releases/{releaseId}` |
| artist detail | `GET {base}/artists/{artistId}` |
| audio | `GET {base}/track/{trackId}` |
| artwork | `artwork` URL returned by the API |

All HTTPS only; no ATS exception is added.
