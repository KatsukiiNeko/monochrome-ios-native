# Stream start investigation

Date: 2026-11-18. Branch `development`, started at `74314cc`.

Symptom: the first tap on a catalog track that is not downloaded showed
`Resource Unavailable`, and a manual Retry then played the same track. A
downloaded file played fine.

## What the app does on a tap

Tap → `PlayerController.loadCurrent`: cancel the previous cache download,
clear the cache protection, look up a permanent download, look up the audio
cache, resolve the stream URL, hand it to `AVPlayerEngine.load`, then wait up
to 20 s for the item to become ready. On throw the track is resolved once more
and, if that fails too, `.failed(message)` reaches the Retry button.

`AVPlayerEngine.load` builds a new `AVURLAsset` and `AVPlayerItem` on every
call, with `AVURLAssetOverrideMIMETypeKey = audio/flac` because the host serves
FLAC as `application/octet-stream` on an extensionless path. It reads the
asset's audio tracks before the item is created, then polls `item.status`.

## Measurements from the build host

Thirteen live requests, sequential, at least one second apart: one search and,
for three tracks, a HEAD, two ranged `bytes=0-1` requests and one 256 KB cut.

| Check | Result |
|---|---|
| Search | 200, 1.9 s to first byte |
| HEAD /track/id | 200, 1.2-1.5 s, `content-length` 27-30 MB, `accept-ranges: bytes` |
| Range `bytes=0-1` | 206, 0.63-0.83 s, `content-range: bytes 0-1/N`, 2 bytes |
| Repeat range, same URL | 206, 0.73-0.83 s |
| First 256 KB | FLAC magic present in all three |
| Content type | `application/octet-stream` |
| CDN | `server: cloudflare`, `cf-cache-status: dynamic` |
| Redirects | none |

So the origin is healthy from this network: ranges, lengths and bytes are all
correct, and repeated requests stay fast. The failure was not reproducible
from the host, which matches the earlier note that the host once answered
nothing at all while the device was failing.

One detail matters for the cold-start theory: every request still pays
0.6-1.5 s to first byte even on a repeat. A first-ever request therefore
carries DNS, TLS and CDN warm-up on top of that, inside a readiness window.

## Hypotheses

| # | Hypothesis | Result | Evidence |
|---|---|---|---|
| H1 | The host answers an unwarmed request too slowly or not at all | **Best remaining explanation** | 0.6-1.5 s to first byte on a warm repeat; no failure reproducible from the host, so it can only be observed at the device |
| H2 | Two consumers request the same URL during the initial load | **Rejected for the first play** | The cache download starts only after `.readyToPlay`; downloads never touch the network. Only the pre-item `loadTracks` call is an extra request |
| H3 | The request identity is rejected | **Not proven, not needed** | AVFoundation still uses its own identity. Requests carrying the app's identity succeed from the host, so the origin does not reject our user agent |
| H4 | The MIME override is wrong | **Not proven** | The bytes are FLAC and the override is the documented fix for an extensionless path; measured content type is still `application/octet-stream` |
| H5 | Redirects or expiring URLs | **Rejected** | No redirect, and the URL is `{host}/track/{id}` with no token |
| H6 | A stale asset or item is reused | **Rejected** | `load` builds a new asset and item every time; Retry also resolves again |
| H7 | Download or cache lookup delays the first frame | **Rejected** | Both are a dictionary lookup plus a file-size check, and a miss falls through to the network |

## What changed

- One attempt now logs its phases: lookup, resolve, preflight, asset, ready or
  failed, plus durations, a short track hash, request counts and the error
  domain/code. No URL, title, host path or description is logged.
- Before AVPlayer sees a catalog URL, the controller sends one ranged request
  with the app identity. Podcast, radio and companion-server URLs are exempt:
  they can be live chunked streams with no length, where a range check would
  fail a stream that plays fine. If the reply is not 200 or 206 with a usable length,
  it waits 0.4, 0.8, 1.6 and 3.2 s and asks again, at most five requests in
  eight seconds. A newer load cancels the wait. When the ladder is exhausted
  the attempt fails with the app's own sentence, and the existing single retry
  starts a completely fresh attempt.
- AVPlayer access-log and error-log entries are logged with the host and a
  path hash, so a device log shows what the player itself requested.

This turns an unwarmed answer into a longer `loading` state instead of a
`Resource Unavailable` alert, and it bounds the work per tap. It does not prove
the device side is fixed: the preflight warms DNS and the edge, but AVPlayer
still opens its own connection.

## Still unverified

- The build installed and verified on the connected iPhone on 2026-11-18
  (`xtool dev run`), but nothing tapped a track afterwards. The four checks in
  the "First play of a stream" section of `DEVICE_TEST_CHECKLIST.md` still
  need a person.
- The cold-start theory can only be confirmed from a device log: look for
  `preflight=... status=... requests=...` followed by
  `item ready seconds=... `. If preflight is ready on the first request and the
  item still fails, H1 is wrong and the next suspect is the AVFoundation
  request itself (H3/H4), which would need the asset-level user agent and its
  own measured run.
