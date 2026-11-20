# Playback pipeline investigation

Scope: what touches a stream URL or writes audio bytes, how playback state is
published, and which failure modes explain the reported symptoms. Every
hypothesis below is marked from evidence found in this repository; anything
that needs a phone is marked explicitly.

## Pipeline map

| Component | Role | Runs where | Can overlap with |
| --- | --- | --- | --- |
| `TrackURLResolver` (`DefaultTrackResolver`) | Turns a `Track` into a playable URL and content type | Actor | Any other resolution; one per attempt and per download |
| `AVPlayerEngine` | Owns the `AVPlayer` item and its observers | Main actor | Network streaming for the current track |
| `AudioCache` | Temporary cache store, integrity index, eviction | Actor | Its own downloads; next-track preparation |
| `DownloadStore` | Permanent user downloads | Actor | Cache, streaming, next-track preparation |
| `URLSessionFileDownloader` / `ProgressTransfer` | One URLSession download task per file | Background session per transfer | Up to `maxConcurrentDownloads` (downloads) plus one per cache store |
| `NextTrackPreparation` + `AppModel.prepareNextTrack` | Pre-stages the next track after the current one is past halfway | Actor task | Streaming, downloads, cache |
| `NowPlayingController` | Publishes metadata and commands | Main actor | Nothing (it reads state) |

At play start the app resolves the URL, reads the content type, checks for a
download, then checks for a cache entry, then loads the network URL, and only
after the item is ready starts the cache store. All of those are sequential
awaits, so a slow resolve delays silence of the previous item.

Requests that can be in flight at the same time: the current stream (AVPlayer),
one cache store, one permanent download (two when queued), and one next-track
preparation. `URLSessionConfiguration` did not limit connections per host, so
five or more connections to the same origin were possible.

## Hypotheses

| ID | Status | Evidence | Cause / plan |
| --- | --- | --- | --- |
| H-C1 | Refuted | `PlayerController.handleReady` started `cache.store` as soon as the item was ready, not on `.finished` | The cache is not end-of-track only; it is ready-time. Policy is still wrong (writes for skipped songs) |
| H-C2 | Confirmed | `AVPlayerEngine` loads the network URL directly; no `AVAssetResourceLoaderDelegate` exists | Playback has no progressive path. Fallback is network streaming plus a staged download after the half-heard point |
| H-C3 | Confirmed | Cache store was cancelled only inside a 10 s skip window; after that the task kept downloading a skipped song | Replace the time window with "cancel unless half was heard" |
| H-S1 | Confirmed | `loadCurrent` resolved, preflighted and loaded before replacing the item; `seek` called `engine.seek` unconditionally | Old item is silenced at attempt start (`halt()`), positions reset, seeks during loading are pending until ready |
| H-D1 | Confirmed | `ProgressTransfer` mapped any non-2xx response to `URLError(.badServerResponse)` (`-1011`) with no status, classification or retry | Classify status (`TransferFailure`), retry transient classes with backoff, re-resolve once on 401/403 |
| H-D2 | Partly confirmed | No `httpMaximumConnectionsPerHost` limit, five possible consumers | Set 4 connections per host; downloads still bounded by `maxConcurrentDownloads`; next-track work is bounded by the half-heard check |
| H-D3 | Not testable here | Every consumer resolves its own URL through `TrackURLResolver`; no evidence of a shared single-use URL | Resolver is called per consumer, so no shared URL. Expiry is handled by the re-resolve path |
| H-R1 | Confirmed | No observer of `AVPlayerItemPlaybackStalled`, `timeControlStatus` was logged but never acted on | Add engine facts and a one-second reconcile loop implementing `StallPolicy` |
| H-R2 | Confirmed | `NowPlayingProjection` published `isPlaying: true` for any `state == .playing`; `.loading(autoPlay: true)` also projected playing | Rate now comes from engine facts; buffering publishes 0.0 with identity kept |
| H-R3 | Refuted | `AudioSessionController` handles interruption end and route changes and reactivates the session | Left as is; the recovery policy now covers the "silently paused" case |
| H-R4 | Confirmed | A failed item was handled, but only as a `.failed` event; `AVPlayerItemFailedToPlayToEndTime` had no observer. Item status is now part of the facts | `StallPolicy` reloads a failed item up to two times, then fails |
| H-L1 | Not measured | Cache index writes happen on the cache actor, not the main thread; no signposts existed | Index writes are unchanged; signposts and tags were added so a device pass can measure |
| H-L2 | Not measured | `PlayerView` observes `player.position`, which changes once per tick | One tick per second is not a storm; needs device measurement |
| H-L3 | Confirmed | Request timeout was 60 s (URLSession default), no retry, single host with failover only in the API client | 20 s request timeout, 2 retries with backoff, honour `Retry-After` |
| H-L4 | Confirmed | Resolve, content type, download lookup, cache lookup and load were sequential | Cache lookup and content type are independent but resolve must come first; the signposts were added to measure. No parallel rewrite without device data |
| H-M1 | Confirmed | `TracksAPIClient` wrapped every network error into `.unavailable(error.localizedDescription)` and the UI prefixed "The music service is unreachable." | Corrupted errors are the cause; typed transfer errors now carry the real reason and are shown verbatim |

## Symptom causes

- **S1 cache.** Store started at item ready regardless of listening, and a skip
  after 10 s did not cancel it. New policy: `ListenAccumulator` counts real
  playing ticks, the staged store starts only at 50%, a superseded attempt
  cancels it.
- **S2 wrong song.** The previous item stayed attached and playing while the
  new attempt resolved. Seeks always went to the attached item. Fixed by
  `halt()` and attempt-scoped pending seeks.
- **S3 -1011.** Any non-2xx status (expired signed URL, limit, 5xx) became
  `badServerResponse`; the message hid the status. Fixed by
  `TransferFailure` classification and retry.
- **S4 stops.** Facts were never consulted after `play()`; a stall or a silently
  paused item left the UI and Now Playing running. Fixed by facts-driven state
  and bounded recovery.
- **S5 lag.** Sequential awaits at play start and unthrottled connections;
  measured with tags and signposts, no parallel rewrite yet.
- **S6 message.** Generic wrapping in `TracksAPIClient`; the raw description is
  now surfaced and the transfer layer supplies class-specific text.

## Not reproducible without a device

The loader proof (playing a FLAC through a custom scheme on a physical phone)
was not attempted: no iPhone was connected during this work. The documented
fallback is used instead — network streaming, staged download at 50% heard.
True play-while-downloading is therefore absent and the second half is fetched
twice; this needs an on-device decision.
