# Device test checklist

Build under test: `development`, installed with `xtool dev` on the connected iPhone.
Playback and the visual result can only be confirmed by a person, so tick each
item by hand.

## Playback

- [ ] Search for a track and open the results list.
- [ ] Tap a track: audio starts within a couple of seconds.
- [ ] The Now Playing screen shows the track title, artist and artwork.
- [ ] Pause, then resume: audio stops and continues at the same position.
- [ ] Seek to the middle: audio continues from there, and the timer agrees.
- [ ] Let one track reach the end: the next queued track starts.
- [ ] Tap a track while another is playing: the new one replaces it cleanly.

## Format badge

- [ ] Each catalog row shows a small `FLAC` badge next to the title.
- [ ] Now Playing shows the badge under the title, with the parsed sample
      format (for example `FLAC 16/44.1`).
- [ ] VoiceOver reads the badge (for example "Lossless, FLAC 16/44.1").
- [ ] A local imported file shows no badge.

## Now-playing bar

- [ ] With a track loaded, the bar is visible on Home, Search and Library,
      above the tab bar.
- [ ] Open an album or artist detail screen: the bar stays visible.
- [ ] The bar shows artwork, title, artist, the format badge, play/pause and a
      thin progress line.
- [ ] Tapping the bar opens Now Playing.
- [ ] With a long list, the last row can be scrolled clear of the bar.
- [ ] VoiceOver names the play/pause, next, retry and open-player controls.

## Search field

- [ ] Open the Search tab: the search field is visible immediately, without
      pulling down.
- [ ] Dismiss the keyboard and return to the tab: the field is still reachable.
- [ ] The field stays visible on a small and a large device.

## Cache and loop

- [ ] Play song A for a few seconds, then song B, then A again and B again.
      Settings shows 2 songs, and both start instantly.
- [ ] Tap Clear cache: Settings shows 0 songs. Play a song, then open
      Settings again: it shows 1 song.
- [ ] Play a catalog track once and wait for it to start; after a few seconds,
      Settings shows a non-zero cached size.
- [ ] Keep Settings open while a track finishes downloading: the song count and
      size update without closing the sheet.
- [ ] Play the same track again: Now Playing shows `Cached` beside the badge.
- [ ] Turn repeat-one on and let the track end: the next pass starts
      immediately and still shows `Cached`.
- [ ] Turn on airplane mode, then let that cached track end with repeat-one on:
      it restarts and keeps playing.
- [ ] With airplane mode still on, tap a track that is not cached: playback
      fails with a message and Retry, and the app stays responsive.
- [ ] Skip a track within 10 seconds: its download stops. Skip after 10 seconds:
      the download finishes and the track is cached.
- [ ] With Cache over cellular off, playback on cellular still works but the
      cached size does not grow.
- [ ] Turn Cache over cellular on, play an uncached track on cellular: the
      cached size grows.

## System integration

- [ ] Lock the screen: playback continues and the Lock Screen shows the track.
- [ ] Lock Screen play/pause and next/previous work.
- [ ] Switch to another app: playback continues (the audio session is
      `.playback`).
- [ ] Pull down Control Center: the Now Playing tile shows the same track.

## If something fails

Capture the app's log while reproducing, then attach the lines:

```bash
timeout 60 idevicesyslog -u <device-udid> -m monochrome
```

The player logs its URL, item status, the AVFoundation error domain/code and
`AVPlayerItemErrorLog` events under subsystem `com.neko-ngtran.monochrome`,
categories `player` and `audio-session`. A failed start now shows an error with
a Retry action instead of staying in the loading state.

Cache decisions are logged under the same subsystem with `cache hit`,
`cache miss`, `cache download start`, `cache download finish`,
`cache download failed`, `cache skip reason=…`, `cache cancel reason=…`,
`cache clear removed=…`, `cache slot released`, and the loop logs
`loop source=cache` or `loop source=network`. Each line carries the track id or
cache key, so it can be matched to what was on screen.
