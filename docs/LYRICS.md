# Lyrics

Lyrics are fetched on demand from [LRCLIB](https://lrclib.net), a community
lyrics database with a public, token-free API.

## Why LRCLIB

The upstream web client already resolves lyrics with LRCLIB. In
`upstream/main`, `js/lyrics.js:464-512` builds `track_name` and `artist_name`
(with optional `album_name` and `duration`), calls `https://lrclib.net/api/get`
and treats a missing record as "no lyrics". The Monochrome host the app already
uses for the catalog has no lyrics route, so there is no first-party endpoint to
prefer.

LRCLIB is used directly because its official documentation describes the
endpoints, record shape and rate-limit behavior, requires no API key, and does
not need a spoofed client. The app identifies itself truthfully with
`User-Agent: Monochrome/<version> (+https://github.com/KatsukiiNeko/monochrome-ios-native)`.
Only HTTPS is used.

## What is sent

For a track the user opens, the app sends only:

- title
- artist
- album, when the track has one
- duration in whole seconds, when known

The app's internal track id is not sent; it is used only as the cache key. No
account, device identifier, listening history or library contents are sent.
As with any HTTP request, LRCLIB sees the client's IP address and request
metadata. There is no token, no cookie jar and no embedded credential.

## On-demand only

Lyrics are requested only when the Lyrics sheet is opened. Playing or queueing a
track never fetches lyrics in the background. Closing the sheet or changing
tracks cancels the request.

## Matching

A wrong lyric is worse than no lyric. Before a record is shown, the app compares
the provider's title and artist with the track using comparison-only
normalization: case, Unicode NFC/NFD, diacritics, punctuation, `&`/`and`, and
version suffixes such as `(feat. …)`, `- Remastered`, `- Live` and
`- Radio Edit`. Durations must be within 3 seconds when both are known. Anything
below the match threshold is treated as not found. The normalized strings are
never displayed; the provider's original text is.

The first request is `/api/get` with title, artist, album and duration. If that
returns 404 or a record that does not match, `/api/search` is used and its
candidates are scored the same way. Synced lyrics are preferred over plain
lyrics, and a candidate with content is preferred over an instrumental record at
the same score. A track without a title or artist is never queried.

## Caching

- Location: the app's private `Caches/Lyrics` directory, one JSON record per
  provider and track id.
- Positive results: valid for about 30 days.
- Not-found results: valid for about 7 days so a missing song does not hit the
  network every time the sheet opens.
- Bound: at most 500 records, least recently used removed first.
- Offline: a cached record is shown; if none exists the sheet says lyrics are
  not available offline. Stale records may answer while offline rather than
  showing nothing.
- Rate limits: a 429 is not retried; `Retry-After` is surfaced to the sheet.
  Other transient failures get one retry with a short backoff.

The cache is disposable and is cleared with the rest of the app's cache when the
system or the user removes it; it is not a lyrics library.

## Parsing and display

Synced lyrics support `[mm:ss]`, `[mm:ss.xx]`, `[mm:ss.xxx]`, several timestamps
on one line, `[offset:±ms]`, metadata tags, blank gap lines, enhanced-LRC word
tags (removed from the display), CRLF and a BOM. Malformed lines are skipped.
Lines are sorted by time, and the active line is found by binary search with a
small lead. Tapping a line seeks to its timestamp. Manual scrolling pauses
auto-follow until Follow is tapped.

### Gaps and timing

A timed line with no text marks an instrumental gap. It keeps its space in the
list but never takes the active highlight, so the last sung line stays lit until
the next line starts instead of changing when the silence begins.

Some provider files are shifted early or late across the whole song. The timer
menu in the Lyrics sheet moves the highlight 0.25 s per step, up to 5 s either
way, without changing the audio. The offset is stored on the device per track;
Reset timing returns that track to the provider's timing. The offset is local
only and is never sent to the provider.

## Copyright

Lyrics belong to their authors and rights holders. The app displays provider
text for personal reading and does not sell, redistribute or bundle it. Lyrics
are never stored in this repository, its documentation, commit messages, logs
or test fixtures. Tests use invented lines with synthetic timestamps.

## Live check (2026-10-24, from Linux)

Read-only checks against `lrclib.net`, using the truthful User-Agent. Only field
names, flags and counts were recorded; no lyric text was saved or pasted.

| lookup | observed |
|---|---|
| `Too Little Too Late` / JoJo, search | 200, 20 records, fields `albumName`, `artistName`, `duration`, `hasWordSync`, `id`, `instrumental`, `lyricsfile`, `name`, `plainLyrics`, `syncedLyrics`, `trackName`; first four non-instrumental records had synced lyrics (71 lines each), one instrumental record had none |
| `Too Little Too Late` / JoJo, exact lookup with album and duration 215 | 200, synced present, 71 lines, plain present, `hasWordSync` false, instrumental false |
| `Anh Là Thằng Tồi`, search | 200, 6 records, all non-instrumental, all with synced and plain lyrics; synced line counts 37, 46, 46, 46, 46 |
| repeated Vietnamese search | one 503; the client backs off and shows an honest error state instead of retrying in a loop |

Vietnamese coverage was present for this title, but LRCLIB coverage varies by
release and region. There is no fallback to another source.

## Known limits

- Word-level timing is stripped; only line-level sync is displayed.
- Provider text quality, coverage and timing vary between records.
- A track whose metadata differs from the provider record may show "not found";
  the matcher deliberately rejects uncertain candidates.
- No translation, transliteration, sharing or editing is included.
- Timing that the provider gets wrong can only be corrected per track with the
  manual 0.25 s nudge; there is no automatic alignment.
- The sheet cannot be judged visually from the build host; appearance, gestures
  and VoiceOver need a device.
