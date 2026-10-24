# Device test checklist

Build under test: the current `development` build on a connected iPhone. The
tagged v0.2.0 release was previously installed with `xtool dev` on an iPhone 12
Pro Max and verified by the maintainer. The accent-color items below describe
the current build and have not been device-verified yet.
Playback and the visual result can only be confirmed by a person, so tick each
item by hand.

## Nothing-inspired visual language

- [ ] The chrome and body text stay monochrome; artwork and the selected accent
      are the only sources of expressive colour.
- [ ] The selected accent appears only on selection, progress, favorites and
      active playback state, never on backgrounds, body text, the play button or
      the logo.
- [ ] The primary play/pause control is the strongest control on Now Playing.
- [ ] Section markers, hairline rules and monospaced time/metadata read as
      structure, not decoration.
- [ ] No fake signal meters, telemetry, recommendations, quality claims or
      unimplemented controls are visible.
- [ ] Tiles, rows and artwork use the tighter radii; no screen reads as a stack
      of large rounded cards.
- [ ] Long titles truncate cleanly and controls keep their alignment.

## Appearance

- [ ] Open Settings and switch Appearance between System, Light and Dark; the
      open sheet changes immediately, without closing or reopening it.
- [ ] The appearance choice survives relaunching the app.
- [ ] System follows the device appearance after changing it in iOS Settings.
- [ ] Light appearance keeps text, separators, chips, fields and the mini-player
      readable; dark appearance keeps the same hierarchy.
- [ ] The mini-player tint and Now Playing background remain legible in both
      appearances.
- [ ] Native tab bars, navigation bars, sheets, alerts and menus stay coherent
      with the selected appearance.
- [ ] The toolbar logo remains visible in light and dark appearance; it is
      rendered as a template from the existing asset.

## Accent color

- [ ] With Settings open, choose each swatch: the ring and check move at once,
      and progress, selected chips and rows, toggles and links update in the open
      sheet without closing it.
- [ ] Open Now Playing and change the accent from the Settings sheet while it
      stays presented: the new accent is already applied when it is shown again.
- [ ] Check every accent, including Monochrome, in light and dark appearance and
      at the largest Dynamic Type size: state marks stay visible and no
      background or body text changes colour.
- [ ] The play button stays black or white and the logo and app icon are
      unchanged for every accent.
- [ ] Choose Match Artwork with a track playing, then change tracks: the accent
      follows the new artwork. With no artwork, it falls back to the Signal
      accent.
- [ ] VoiceOver reads "Accent color: <name>, selected" for the chosen swatch.

## Layout and navigation

- [ ] The mini-player is a floating card above the tab bar on Home, Search and
      Library, including after scrolling to the end of each list.
- [ ] Opening an album or artist detail sheet covers the bar; dismiss the sheet
      and confirm the bar is still in place.
- [ ] The card tint follows the current artwork and remains readable; the
      favorite, play/pause and next controls work.
- [ ] Tapping the card opens Now Playing; swiping down or tapping the chevron
      closes it.
- [ ] Home shows a two-column quick-access grid, Listen again and Your
      favorites; the last row scrolls clear of the mini-player.
- [ ] Search chips appear only for returned types; Top result, songs, albums and
      artists sections open or play the right item.
- [ ] Library chips and sort menu work; the pinned Favorites row and local-file
      rows do not duplicate each other.
- [ ] At the largest Dynamic Type size the quick-access grid becomes one column
      and no control is clipped.
- [ ] With Reduce Motion on, the artwork scale and tint changes do not animate.
- [ ] With Reduce Transparency on, the glass fallback stays solid and readable.
- [ ] VoiceOver order matches the visual order on Home, Search, Library and Now
      Playing.

## Now Playing and queue

- [ ] The chevron and a downward swipe both dismiss Now Playing.
- [ ] The source caption uses the real album when present and “Now playing”
      otherwise.
- [ ] Artwork fits without clipping on a 4.7-inch screen and at large text.
- [ ] The idle scrubber is thin; dragging makes it easier to grab, and seeking
      moves playback to the expected position.
- [ ] Repeat shows a visible marker in addition to the accent colour; repeat-one
      is unambiguous.
- [ ] The queue sheet opens at medium and large detents; jump, reorder and
      remove affect playback order as expected.
- [ ] Format, Cached and AirPlay appear only when their real state exists.
- [ ] Open Now Playing: the action icons for Lyrics, Queue, Download and AirPlay
      sit on one line, share the row evenly and stay 44 pt tall. No label is
      cut off and the word "Downloaded" does not appear in this row.
- [ ] The audio info line under the title shows the format badge and the
      bit-depth/sample-rate summary on one line. Narrow the window or raise the
      text size: the line drops the summary, then the status, instead of
      wrapping mid-word or showing an ellipsis.
- [ ] Change the download state: the row icon moves through not downloaded,
      downloading (progress ring) and downloaded (accent checkmark). Tapping the
      downloaded icon asks before removing the offline copy.
- [ ] Enter a long title and artist, then the largest text size: the action row
      stays even and the info line stays on one line.

Layout and feel can only be judged by a person; the host tests cover only the
chip variants and the build check covers compilation.

## Sleep timer

- [ ] Open Now Playing, use the `•••` menu, choose Sleep Timer → 5 minutes.
- [ ] A moon countdown row appears under the scrubber and updates every second.
- [ ] Cancel removes the countdown and playback keeps running.
- [ ] Arming a second duration replaces the first; only the newest expires.
- [ ] Change tracks while armed: the timer keeps counting down.
- [ ] At expiry playback pauses in the app and on the Lock Screen/Control Center,
      and reopening Now Playing keeps the position.

## Lyrics

- [ ] Open Lyrics on a synced track: lines follow, scroll and tap-to-seek.
- [ ] Pair Bluetooth headphones or AirPods, reopen Lyrics and confirm the timer
      menu shows "Auto delay …" and the highlight sits on the sung line instead
      of ahead of it.
- [ ] Switch back to the phone speaker: the auto delay drops to the speaker value
      within a few seconds and the highlight stays aligned.
- [ ] Use Earlier/Later ±0.25 s on a provider file that is shifted; the change
      applies on top of the auto delay and survives reopening the sheet.
- [ ] Reset timing clears only the manual offset; the auto delay stays visible.
- [ ] VoiceOver reads the timing value, including the output delay.

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

## Audio specification

- [ ] Tap the format badge on Now Playing; the Audio sheet opens at the medium
      detent and Done dismisses it.
- [ ] Open the sheet for a streamed track, a cached track and a permanent
      download; Format, sample rate, bit depth, channels and bitrate match what
      the app is actually playing, and Source reads Stream, Cache or Download.
- [ ] Values the app cannot measure are absent; no row shows a guessed number.
- [ ] Switch the output to Bluetooth or wired headphones while the sheet is
      open: the Output row changes and shows the hardware sample rate.
- [ ] Quality shows the requested tier; a fallback is shown only when the app
      knows the played tier differs.
- [ ] Provenance labels read measured or reported and stay legible in Light and
      Dark appearance.
- [ ] VoiceOver reads each row as a sentence, for example "Sample rate, 44.1
      kilohertz", and the sheet works at the largest text size.

## Lyrics

- [ ] Open Now Playing for a track with a title and artist: the Lyrics control
      is enabled. Open it; the sheet takes the large detent and shows a loading
      placeholder before any text.
- [ ] For a synced track, the active line is emphasized and follows playback;
      the rest of the list stays dimmed.
- [ ] Tap a line: playback seeks to that timestamp.
- [ ] Scroll the lyrics by hand: auto-follow stops and a Follow button appears.
      Tap Follow: the sheet returns to the active line and follow resumes.
- [ ] With Reduce Motion on, following still moves the list but without an
      animated scroll.
- [ ] On a track whose file has timed blank lines, the last sung line stays
      highlighted through the instrumental gap and the next line lights up when
      it starts.
- [ ] Open the timer menu: moving the highlight 0.25 s earlier or later updates
      the lyric immediately, stays set after closing and reopening the sheet,
      and Reset timing returns it to the provider timing.
- [ ] Open a track with only plain lyrics, an instrumental track, and a track
      the provider does not know. Each state reads distinctly; not found and
      error states offer Retry.
- [ ] Enable airplane mode. A track opened before shows its cached lyrics; a
      track that was never opened says lyrics are not available offline.
- [ ] Try a Vietnamese track with diacritics; a wrong-language or wrong-version
      match must not appear.
- [ ] The footer names the source. No lyric text appears anywhere outside the
      sheet.
- [ ] Both appearances, the largest text size and VoiceOver line navigation are
      usable.

## Now-playing bar

- [ ] With a track loaded, the bar is visible on Home, Search and Library,
      above the tab bar.
- [ ] Open an album or artist detail sheet: it covers the bar; dismiss it and
      confirm the bar returns.
- [ ] The bar shows artwork, title, artist, the format badge, play/pause and a
      thin progress line.
- [ ] Tapping the bar opens Now Playing.
- [ ] With a long list, the last row can be scrolled clear of the bar.
- [ ] VoiceOver names the play/pause, next, retry and open-player controls.

## Search field

- [ ] Open the Search tab: the search field is visible immediately, without
      pulling down.
- [ ] Scroll the results: the search field stays pinned at the top.
- [ ] Dismiss the keyboard and return to the tab: the field is still reachable.
- [ ] The field stays visible on a small and a large device.
- [ ] Search for a song, tap it, then clear the field: the song appears under
      Recent searches with its title, artist and artwork.
- [ ] Relaunch the app: recent searches are still listed.
- [ ] Tap the trash button on one recent search: only that row disappears, and
      it stays gone after relaunching.
- [ ] Tap Clear all: the Recent searches section disappears, and it stays empty
      after relaunching.

## Search results

- [ ] Chips appear only for result types the service returned, and the selected
      chip is visibly distinct without relying on colour alone.
- [ ] Top result plays a song or opens the album/artist it names.
- [ ] Song, album and artist sections use the shared rows and artwork, with no
      invented metadata.
- [ ] Rows with menus expose only actions the app implements.
- [ ] The pinned field keeps focus styling and remains usable while results
      load, fail or are empty.
- [ ] At large text sizes the chips scroll horizontally and rows do not clip.

## Library

- [ ] All, Favorites and Local chips filter the real collection.
- [ ] The sort menu changes the visible order and keeps the selection.
- [ ] The pinned Favorites row shows the actual count and opens the filtered
      list.
- [ ] Import audio files opens the Files picker and imported tracks appear.
- [ ] Local rows offer deletion; catalog rows do not.
- [ ] Empty states are explicit for each filter.
- [ ] The mini-player does not cover the last library row.

## Accessibility

- [ ] Largest Dynamic Type: Home, Search, Library, Now Playing, queue and
      Settings remain usable without clipped controls.
- [ ] VoiceOver traversal follows visual order; chips announce selected state;
      active playback, favorite and repeat states are spoken.
- [ ] Reduce Motion disables the artwork scale, tint and scrubber transitions.
- [ ] Reduce Transparency keeps floating surfaces solid and readable.
- [ ] Interactive targets are at least 44 pt where practical.
- [ ] Controls are not obscured by the mini-player, tab bar or safe areas.

## Permanent downloads

- [ ] Search for a catalog track and choose Download from its menu. Settings
      shows the downloaded-song count; the row opens a list of completed
      downloads with artwork, title, artist and size.
- [ ] Play the downloaded track, enable airplane mode, then play it again: it
      starts and Now Playing shows `Downloaded`.
- [ ] Delete the app's temporary cache: the downloaded song still plays offline.
- [ ] Swipe to delete one download, and remove another from Library or Search:
      each row disappears, its file is gone, and the song streams again when
      online.
- [ ] Use Edit and Delete All: the confirmation appears, and confirming removes
      every download while cache and imported files remain.
- [ ] Start three downloads quickly: no more than two transfer at once and the
      third waits rather than failing.
- [ ] Interrupt a download by force-quitting the app; reopen it: no partial file
      appears as a completed download and the record is repaired.
- [ ] With the YouTube Music companion source unconfigured, no download action
      is offered for it.
- [ ] Check a downloaded track after relaunching the app: it is still listed and
      still plays offline.
- [ ] The Settings Downloads row and the manage screen show the same song count.

## Cache and loop

- [ ] Play song A for a few seconds, then song B, then A again and B again:
      both start instantly on the later plays.
- [ ] Tap Clear Cache: the row briefly shows `Cleared`. Settings has no cache
      meter, song count, byte total, cached-song list, confirmation dialog or
      cache footer.
- [ ] Play a catalog track after clearing: it caches again, and Now Playing shows
      `Cached` beside the badge on the next play.
- [ ] Play songs 1, 2, 3, 4, 5 in order. Play song 6: the cache still holds five,
      song 1 is gone, and songs 2–6 start from cache without re-streaming.
- [ ] With airplane mode on, play song 2 through song 6: all five start.
- [ ] Clear the temporary cache: permanent downloads and imported files in
      Library still play offline.
- [ ] Relaunch the app with cached songs: valid entries survive. Settings offers
      no Clear-on-launch or cellular-cache switch.
- [ ] With cellular data on, play an uncached track: playback works and the
      cache does not fill.
- [ ] Turn repeat-one on and let the track end: the next pass starts
      immediately and still shows `Cached`.
- [ ] Turn on airplane mode, then let that cached track end with repeat-one on:
      it restarts and keeps playing.
- [ ] With airplane mode still on, tap a track that is not cached: playback
      fails with a message and Retry, and the app stays responsive.
- [ ] Skip a track within 10 seconds: its download stops. Skip after 10 seconds:
      the download finishes and the track is cached.

## System integration

- [ ] Lock the screen: playback continues and the Lock Screen shows the track,
      album and artwork when the track has artwork.
- [ ] Lock Screen play/pause, seek and next/previous work.
- [ ] Switch to another app: playback continues (the audio session is
      `.playback`).
- [ ] Pull down Control Center: the Now Playing tile shows the same track and
      playback state.
- [ ] An interruption (for example a call) resumes only if audio was playing
      before it began.

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
