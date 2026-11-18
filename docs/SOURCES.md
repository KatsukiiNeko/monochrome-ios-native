# Sources and capabilities

The app models a source as an identity plus capabilities. Capabilities are not
marketing labels: a feature is shown only when the source can really do it.

| Source | Search | Stream | Permanent downloads | Status in this build |
|---|---|---|---|---|
| `monochrome` (Monochrome HiFi) | yes | progressive FLAC | yes | configured by default |
| `youTubeMusic` | companion server only | companion server only | no | no server configured |

## Monochrome

- Search, release and artist endpoints: `https://tracks.monochrome.st` (the
  host the upstream web client uses).
- Playback URL: `{base}/track/{trackId}`, a progressive FLAC file. It is not
  HLS or DASH.
- Download evidence: the upstream web client's `downloadTrack` resolves the
  same FLAC URL and saves the body (`js/api.js:3050,3196-3231`;
  `js/downloads.js:348`). The native app stores a user-chosen copy under
  `Application Support/Downloads` and plays it before cache or network.
- This is capability evidence, not a content licence. The catalog is
  Tidal-derived and relayed by a third party. See
  [`ONLINE_STREAMING_AUDIT.md`](ONLINE_STREAMING_AUDIT.md).

## YouTube Music companion

- The app never extracts YouTube audio, uses cookies, scrapes, or calls a
  direct YouTube API.
- The only permitted integration is a user-run HTTPS companion server that
  exposes search, stream resolution and downloads. No default URL is shipped.
- `youTubeMusic` has `search` and `stream` capabilities but **not**
  `downloads`. A source-detail screen must show that limitation instead of
  offering a download button.
- Companion integration is not configured in this build; the source row shows
  `Needs setup`. The source-detail screen (`SourceDetailView`) shows the
  capability matrix and the missing server without offering a fake setup
  control.

### Companion contract

The companion server is the only way the app reaches YouTube Music. The app
speaks this small JSON contract over HTTPS; it sends its truthful `User-Agent`,
no credentials, cookies or signature parameters, and it never parses HTML.
The base URL is entered by the user, and until one is configured the source
stays `Needs setup`.

```
GET {base}/v1/search?q={query}&limit={count}

200 {"tracks": [
  {"id": "<opaque>", "title": "<text>", "artist": "<text>",
   "album": "<text>", "duration": <seconds, number or null>,
   "artworkUrl": "<https url, optional>"}
]}
```

```
GET {base}/v1/stream/{id}

200 {"url": "<https url>", "contentType": "<mime, optional>",
     "duration": <seconds, number or null>}
```

`id` is opaque to the app; it is only used in the stream path. The stream URL
is progressive audio served by the companion or its upstream; the app does not
download it for a source without the downloads capability.

## Rules

- Download eligibility is checked in the core before a transfer starts:
  source capability, progressive format, and non-empty file. HLS, DASH and
  encrypted formats are refused.
- A progressive stream URL is not treated as a download grant for a source
  whose own client does not offer downloads.
- The temporary cache and permanent downloads never share a directory, a
  record file, or a cleanup path.
