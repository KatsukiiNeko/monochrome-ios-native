# Implementation plan (R3–R9)

Constraints that shape every step: iOS 17 deployment target, no third-party
packages, `MonochromeCore` stays Foundation-only and Linux-testable, one
`PlayerController` remains the source of truth, every commit validated before
it is made.

## R3 — streaming vertical slice

Deliver, in separate commits:

1. **HTTP and models** (`feat(api): add tracks API client`): `HTTPClient`
   protocol + `URLSession` implementation; typed models (`RemoteTrack`,
   `RemoteRelease`, `RemoteArtist`) with tolerant decoding for missing or
   mistyped fields; `TracksAPIClient` for `/search/tracks`,
   `/search/releases`, `/search/artists`, `/releases/{id}`, `/artists/{id}` and
   the `/track/{id}` URL; duration in milliseconds converted to seconds.
2. **Stream resolution and failover** (`feat(api): resolve online track
   streams`): `TrackURLResolver` protocol; local file resolver keeps current
   behaviour; remote resolver builds the stream URL at play time, never
   persists it, tries base URLs in order with a 10 s timeout and marks a host
   unhealthy for the session after a transport failure.
3. **Player integration** (`fix(player): re-resolve expired stream URLs`):
   `PlayerController` resolves asynchronously on every load, retries once on a
   failed load, exposes `retry()`, and calls `onTrackStarted` for history.
   Tests cover success, retry, and the error state.
4. **Settings** (`feat(settings): make the streaming host configurable`):
   base URL stored in `UserDefaults`, empty value = “streaming not configured”.

Acceptance: `swift test` green with fake-HTTP fixtures (failover, malformed
JSON, unavailable track, expiry); one live `L3` check recorded; build green.

## R4 — icon

Take the largest original icon/logo from the archive branch, store it untouched
under `Branding/` with `SOURCE.md`, derive only what the platform requires, and
wire `iconPath` in `the local xtool manifest` after checking xtool's own documentation. If the
toolchain rejects it, keep the asset and document the blocker.

## R5 — UI foundation

`Theme` (spacing, radii, colors), one `glassControlStyle()` helper gated on
iOS 26 with a material fallback and Reduce Transparency support, tab shell with
Home / Search / Library. No view owns playback state.

## R6 — mini player, Now Playing, queue

Mini player with artwork, title, artist, progress and play/pause; iOS 26 uses
`tabViewBottomAccessory`, older OS uses a bottom overlay. Now Playing as a
full-screen cover with `containerRelativeFrame` artwork, one control cluster,
seek, next/previous, queue access. Queue reorder/remove uses the existing
player API. Background audio and Now Playing info must still work.

## R7 — Search, Home, Library

Search: debounced (300 ms), cancellable, stale results dropped, tracks /
albums / artists with artwork; album and artist detail sheets with playable
track lists from the API. Home: greeting, recently played from the history
store, quick access to saved albums/tracks, logo in the header; loading, empty
and error states. Library: local imports plus saved online tracks, favorites
persisted as full tracks (legacy id-only file migrated on first load).

## R8 — regression pass

Rerun `scripts/build.sh` and `swift test`; compare with the R0 baseline (green
build, 44 tests before new ones). Fix regressions before moving on. Update the
README feature/verification table.

## R9 — integrate

Fast-forward `main`, push it, verify `git ls-remote origin refs/heads/main`.
Never push `upstream`; never force.
