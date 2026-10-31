# Streaming investigation

Date: 2026-10-31. Branch `development`, starting point `35aaed2` (v0.3.0).
Scope: catalog tracks that are not downloaded fail to stream with
`Resource Unavailable` and then the app's own
`The stream did not start. Check the connection, then retry.`

## Executive summary

Search, metadata and downloads work; a downloaded FLAC plays. Only the
`AVPlayer` path for a remote track fails. The two messages are distinct:
`Resource Unavailable` is the localized description of an AVFoundation
`NSURLError` (`-1008`, `NSURLErrorResourceUnavailable`), and the second line is
this app's 20-second readiness timeout text, not a separate network diagnosis.

The request-identity hypothesis is the strongest available explanation: the
catalog API and the downloader send the app's own user agent, while
`AVPlayer` sent the system CoreMedia identity. The failing request is the only
one that used a different identity. The fix sets
`AVURLAssetHTTPUserAgentKey` to the same truthful user agent the API client
uses.

This pass could not confirm the root cause on a device. The build host could
not receive any HTTP response from `tracks.monochrome.st`, and the iPhone was
only briefly visible to `usbmuxd`; no `xtool dev run` was possible. The fix is
therefore **L1 + L2 verified, L3/L4 unverified**. The permanent diagnostics
added here make the next device attempt self-explaining.

## Actual playback pipeline

1. A catalog `Track` has `provider != "local"` and therefore
   `isStreaming == true` (`Sources/MonochromeCore/Track.swift:84`).
2. `PlayerController.loadCurrent` tries, in order: a permanent download, the
   rolling cache, then the network (`Sources/MonochromeCore/PlayerController.swift:349`).
3. The network path asks `DefaultTrackResolver` for the URL and the
   out-of-band MIME type. The URL is `/{base}/track/{streamID}` built at play
   time and never persisted; the type is `audio/flac`
   (`Sources/MonochromeCore/TrackURLResolver.swift:47-58`).
4. `AVPlayerEngine.load` creates `AVURLAsset(url:options:)`, wraps it in
   `AVPlayerItem`, installs observers, replaces the current item, and waits up
   to 20 seconds for `.readyToPlay`
   (`Sources/Monochrome/AVPlayerEngine.swift:52-149`).
5. Only after `.readyToPlay` does the engine read the audio format, and only
   then does the controller start the background cache download
   (`AVPlayerEngine.swift:174-196`,
   `PlayerController.swift:283-301`).

Consequence: before readiness there is exactly one consumer of the stream URL,
the `AVPlayerItem`. The cache downloader and the audio-format probe cannot
explain an initial `-1008`; they can only affect a stream that has already
started.

## Verified contract

Last live verification was 2026-10-22, recorded in
[`ONLINE_STREAMING_AUDIT.md`](ONLINE_STREAMING_AUDIT.md). It is historical, not
a current measurement.

| Request | Last verified result |
|---|---|
| `GET {base}/search/tracks?q=&limit=` | 200, JSON |
| `GET {base}/track/{id}` with `Range: bytes=0-1023` | 206, `content-type: application/octet-stream`, `content-range: bytes 0-1023/<size>`, `accept-ranges: bytes`, body begins `fLaC` |
| Redirects | none observed |
| Authentication | none; no cookie, token, `Origin` or `Referer` |
| URL expiry | no signature or expiry observed; URL still built at play time |

The endpoint is a single progressive FLAC file, not HLS or DASH.

## Experiments

### S0: baseline and regression window

- `swift test`: 309 tests in 35 suites passed.
- `./scripts/build.sh`: iOS arm64 compile-only build passed.
- The last streaming-specific change is `a36ccb4 fix(player): use the public
  MIME override key for streams` (2026-10-23). It replaced the private
  `AVURLAssetOutOfBandMIMETypeKey` with `AVURLAssetOverrideMIMETypeKey` because
  the private key was ignored and `AVPlayer` reported the resource as
  unavailable. The public key is still present in the current tree.
- The cache (`b9f90a0`, 2026-10-22) and audio-format measurement (`30984c0`,
  2026-10-24) both run after readiness and do not change the initial request.
- No playback-touching change after `a36ccb4` removes the MIME override or
  changes the stream URL construction.

### S2: build-host HTTP probes

All probes were bounded: no full track, no body larger than a range, and no
authentication bypass. Only headers and the first four bytes were inspected.
They did not reach the origin:

| Probe | Result |
|---|---|
| DNS for `tracks.monochrome.st` | A `172.67.183.143`, `104.21.67.253`; AAAA present |
| TCP + TLS 1.3 to the edge | completed; HTTP/1.1 and HTTP/2 negotiated |
| `GET /search/tracks` (app user agent) | request sent, **0 bytes received**, timeout after 8–15 s |
| `GET /track/{id}` with `Range: bytes=0-1`, `Accept-Encoding: identity` | **0 bytes received**, timeout |
| `GET /` on `tracks.monochrome.st` | **0 bytes received**, timeout |
| `GET /` on `monochrome.st` (same edge IP) | 200 |
| HTTP/3 to `tracks.monochrome.st` | **0 bytes received**, timeout |

The edge accepts the connection but the tracks host returns no response to
this build host. This is therefore an L3 blocker, not evidence that the phone
cannot reach the host (search and downloads do work there).

### S4: device probe

`usbmuxd` connected the known iPhone (`00008101-000868E222E9001E`) at
12:31 and removed it at 12:37; `idevice_id -l` returned the UDID once in that
window and then returned `Unable to retrieve device list!` again. The gate in
the deployment rules therefore blocked `xtool dev run`: no build was
installed, no log was captured, and no probe ran. A `#if DEBUG` probe matrix
(URLSession identities and `AVPlayer` MIME/UA variants) was written but is not
committed, because an unverified probe is not product code.

## Hypothesis results

| # | Hypothesis | Result | Evidence |
|---|---|---|---|
| H1 | The server response is not AVFoundation-compatible (length, ranges, status, body) | **Unverified** | The last contract was range-capable; the host returned nothing to the build host now. No device log. |
| H2 | Two consumers hit the same URL while the item loads | **Rejected as the cause of the initial failure** | The cache download and the audio-format probe both start only after `.readyToPlay`. A mid-playback collision remains possible but cannot produce an initial `-1008`/timeout. |
| H3 | User-Agent / request identity | **Strongly supported, not confirmed** | API and download requests send `MonochromeNative/1.0 (iOS; independent client)`; `AVPlayer` sent CoreMedia. The failing path is the only one with a different identity. The interrupted change in the working tree was exactly `AVURLAssetHTTPUserAgentKey`. |
| H4 | MIME override mismatch | **Partially addressed, unverified** | `AVURLAssetOverrideMIMETypeKey = audio/flac` is present and is the documented way to declare an extensionless resource. It is the same symptom `a36ccb4` fixed, so a regression or a server change cannot be ruled out. |
| H5 | Redirects or expiry | **Unverified, unlikely** | The last contract showed no redirect and no signed URL. The host was unreachable, so redirects could not be replayed. |
| H6 | A recent regression in source routing, cache order, or the audio-spec probe | **No code regression found** | The network path, resolver output and MIME options are unchanged since `a36ccb4`; the later consumers run after readiness. |
| H7 | Application-level races (duplicate items, timeout not cancelling) | **No evidence; hardened** | The readiness flag was set after the first observation; it is now set before. A timeout now cancels the asset load and replaces the item. Diagnostics record item identity state, buffer and time-control state. |
| H8 | The server or upstream changed | **Unverified** | The build host could not reach the tracks host; the last contract is eight days old. |

## Fix

Files changed:

- `Sources/Monochrome/AVPlayerEngine.swift`
  - Sets `AVURLAssetHTTPUserAgentKey` to
    `TracksAPIClient.userAgent` for every asset. The app thus presents the same
    truthful identity for API, download and playback requests.
  - Keeps `AVURLAssetOverrideMIMETypeKey = audio/flac` for the extensionless
    resource.
  - Sets `isWaitingForReadiness` before the initial status observation, so a
    failed item is thrown from `load` exactly once.
  - On timeout: logs the item snapshot, access log and error log, cancels the
    asset load, replaces the item with `nil`, and throws
    `EngineError.timedOut(underlying:)`. The original `NSError` chain is
    attached through `NSUnderlyingErrorKey`; the user-facing text stays the
    friendly timeout sentence.
  - Adds `accessLog` and expanded `errorLog` diagnostics with redacted query
    strings, plus `isPlaybackLikelyToKeepUp` / `isPlaybackBufferEmpty`
    transitions.
- `Sources/MonochromeCore/PlayerController.swift`
  - Logs one `play start id=… source=… via=download|cache|network host=… path=… hasQuery=…`
    line per attempt, and the failure chain for each path.
  - The timeout no longer hides the underlying failure: the engine logs it, and
    the controller logs the final state.

Why this is the smallest step: the request-identity difference is the only
observed difference between the working download and the failing playback.
The change only adds a header identity that the same host already accepts from
the API and downloader. It does not add a fallback download, a custom resource
loader, or a new playback engine; those would hide the cause before the device
logs can show it.

## Verification

| Level | Result |
|---|---|
| L0 | Code written |
| L1 | `./scripts/build.sh` passed for arm64 iOS |
| L2 | `swift test` passed: 309 tests in 35 suites |
| L3 | Not reached; `tracks.monochrome.st` returned no HTTP response to the build host |
| L4 | Not reached; the iPhone disconnected before a deployment |
| Human | Not reached |

The fix's effect is **unverified**. The host-side tests cannot exercise
`AVPlayer` asset options.

## Remaining limits and next experiment

- If the stream still fails, capture the app log while tapping a
  non-downloaded track. The relevant lines are `play start … via=network`,
  `item.status`, `errorLog status=… domain=… comment=…`,
  `accessLog bytes=…`, and `item not ready after timeout … error=…`. The
  access/error status distinguishes a rejected request (H3/H1) from a parser
  failure (H4).
- If the log shows a non-2xx status or a missing `Content-Range`, the next
  rung is download-then-play with the existing downloader and an honest
  `Preparing` state. That fallback is deliberately not added yet: no evidence
  shows the server is incapable of serving `AVPlayer` once the identity is
  correct.
- If the log shows a valid 206 and `fLaC` bytes but the item still fails to
  become ready, the problem is in AVFoundation's parsing of the extensionless
  FLAC resource, not the HTTP contract.
- The 20-second readiness timeout is unchanged. A slow network can still hit
  it; the log now shows what the item was doing.
- The server contract must be re-measured from a network that can reach
  `tracks.monochrome.st` before treating the 2026-10-22 table as current.
