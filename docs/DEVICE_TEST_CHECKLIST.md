# Device test checklist

Build under test: `dev` at `1b008d5`, installed with `xtool dev` on the
connected iPhone. Playback and the visual result can only be confirmed by a
person, so tick each item by hand.

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
