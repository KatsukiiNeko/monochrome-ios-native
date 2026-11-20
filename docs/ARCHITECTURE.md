# Architecture

## Layers

- `MonochromeCore`: portable models, services, persistence and pure logic. It does
  not import SwiftUI, UIKit or AppKit (enforced by `LayeringImportTests`).
- `Monochrome` (app target): SwiftUI views, AVFoundation playback, network
  clients, system integration (audio session, Now Playing), and the composition
  root in `AppModel`.

## Recording, candidate, playback source

- A `Track` is what the listener asked for.
- A `SourceCandidate` is a provider's possible representation of that recording.
- A `PlaybackSource` (local file, download, cache, remote stream, live stream)
  is the concrete media source that actually plays. The resolver returns this,
  never a bare URL, so the player and audio-spec UI can make correct decisions.

Matching happens before quality ranking: a higher-quality candidate for a
different recording is rejected first.

## Provider abstraction

`MusicSourceProvider` exposes id, display name, capabilities, search and
resolve. Failures are normalized to `ProviderError`. `ProviderRegistry` stores
the enabled set and priority order in the shared JSON store, with safe migration
for unknown or missing providers.

## Search, selection, resolution

- `SourceSearchService` fans a query out to every enabled provider concurrently,
  with a per-provider budget. One failure does not block the others; empty is
  final only when all have completed.
- `SourceSelectionService` rejects wrong recordings using `TrackMatcher`, then
  ranks by quality tier and provider priority.
- `SourceResolutionService` resolves the best candidate and falls back to the
  next on failure, with a per-play budget and cancellation on skip.

## Composition root

`AppModel.init` constructs the playback stack, cache, downloads, resolver,
session store and system integration with initializer injection. Services do not
reach into global state to find their dependencies.

## Playback

`PlayerController` owns state, queue, position and duration. `AVPlayerEngine`
implements `PlaybackEngine`. The resolver returns a `PlaybackSource`; the engine
switches on the case for headers and seekability. Cache integrity is checked by
file existence and size; invalid entries are evicted and the network path runs
in the same attempt.

## Reliability

- Session restoration persists queue, index, position, shuffle and repeat
  through `PlaybackSessionStore`; restore is paused, never auto-play.
- Route changes pause on device loss; interruptions resume only when playback
  was active before and the system allows it.
- `PlayerController` starts each attempt with a new ownership token, halts the
  old engine item, and applies loading-time seeks only after the new item is
  ready.
- `AVPlayerEngine` reports item status, time control, buffer state and keep-up
  facts. `StallPolicy` gives bounded recovery actions; intent alone never means
  that audio is playing.
- `ListenAccumulator` counts forward playback time, not seek position. Cache
  staging begins after 50 percent was heard. Permanent downloads remain owned
  by `DownloadStore`.
- `TransferFailure` preserves HTTP status and transport cause. File transfers
  use a 20-second request timeout, a 120-second resource timeout, four host
  connections and bounded retry backoff.
- Next-track preparation still stages the following network track on unmetered
  Wi-Fi, at most one outstanding. True play-while-downloading remains a device
  loader decision; current playback uses AVPlayer network streaming.

## Layering rule

Core and service code must not import SwiftUI, UIKit or AppKit. The layering
host test enforces this.
