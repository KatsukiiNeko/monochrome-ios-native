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

## Queue

- [ ] Play an album so several songs are queued, then tap shuffle on Now
      Playing: the current song keeps playing, the rest play in a different
      order, and the shuffle mark is visible.
- [ ] With shuffle on, let the queue run to the end and check that every song
      played exactly once.
- [ ] Turn shuffle off: the queue returns to its original order with the current
      song still selected, and playback does not restart.
- [ ] Long-press a search result and choose Play next: it plays right after the
      current song. Choose Add to queue: it goes to the end.
- [ ] Open the queue sheet, use the ellipsis menu and Clear queue: playback
      stops, the sheet shows the empty state and Now Playing closes to the mini
      player.
- [ ] Reorder and remove songs in the queue sheet; the changes survive opening
      and closing the sheet.

## Playlists

- [ ] Library shows a Playlists section. Tap New playlist, name it, and confirm the
      row appears with its song count.
- [ ] Open the playlist: the header shows the name and song count, and Play is
      disabled while it is empty.
- [ ] From a Library row's long-press menu, add the song to the playlist; the
      count increases and the playlist detail lists it.
- [ ] Add the same song again: the menu offers "Add anyway to <name>" instead of
      silently duplicating.
- [ ] From Search and from Now Playing's overflow menu, add a song to the same
      playlist.
- [ ] Drag to reorder songs with Edit; close and reopen the playlist and the
      order is unchanged.
- [ ] Swipe a song to remove it; Play starts from the first song and the queue
      fills with the rest.
- [ ] Rename, Duplicate and Delete from the ellipsis menu. Delete asks first and
      the songs remain in the library.
- [ ] Force-quit and relaunch: playlists and their order survive.
- [ ] VoiceOver: playlist rows read the name and song count; the Add to playlist
      menu names each playlist.

## Themes

- [ ] Settings → Theme: switch between Monochrome, OLED Black, Paper and
      Graphite. Every screen updates without relaunching, and the choice survives
      a relaunch.
- [ ] With Appearance set to System, switch the device between light and dark:
      each theme shows its light and dark palette.
- [ ] OLED Black in dark appearance: the Home, Search, Library, Now Playing and
      Settings backgrounds are fully black while text stays readable.
- [ ] Export Current Theme and open the file: it is readable JSON with
      `schemaVersion`, `light` and `dark` tokens.
- [ ] Import that file from the Files app: it appears as the selected theme and
      the colours match the exported one.
- [ ] Import a hand-edited theme whose primary text is faint: an error names the
      contrast problem, the previous theme stays selected and the app stays
      usable.
- [ ] Check the largest Dynamic Type size and VoiceOver: each preset row reads
      its name and selected state.

## Catalog hosts

- [ ] Settings → Catalog Hosts: add an HTTPS host and confirm it appears in
      the list; adding the same host twice is refused, and an http:// address
      shows the validation message instead of being saved.
- [ ] Add two hosts, reorder them with Edit, force-quit and reopen: the order
      is unchanged.
- [ ] Swipe a host away and tap Reset Hosts: the list empties and search keeps
      working through the default endpoint.
- [ ] With a deliberately unreachable extra host first in the list, search:
      results still appear (served by the endpoint after the retry) and the app
      does not hang on the dead host.
- [ ] Remove the unreachable host: search returns to its usual speed.

## Catalog cache

- [ ] Search for a term that returns results, then repeat the same search: the
      second result set appears immediately.
- [ ] Wait ten minutes (or relaunch the app) and repeat the same search: the
      previous results appear immediately while the app refreshes them.
- [ ] With the previous results cached, turn on airplane mode, force-quit the app
      and reopen it, then repeat the same search: the saved results still appear.
- [ ] In airplane mode, search for something new: an error with Retry appears
      and the app stays responsive.
- [ ] Stream URLs are never served from the cache: playing a cached-result track
      in airplane mode fails with Retry rather than playing stale audio.

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

## First play of a stream

- [ ] Fresh launch, search, tap a track that is not downloaded: no "Resource
      Unavailable" alert appears, and audio starts.
- [ ] Tap the same track again in a new session: it starts without a visible
      error or a manual Retry.
- [ ] Put the phone in airplane mode, tap a catalog track: after the bounded
      attempt the app shows "The stream did not answer. Check the connection,
      then retry.", and Retry with the network back starts playback.
- [ ] Skip through three catalog tracks quickly: each one starts, no
      overlapping audio, no error alert between them.

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
- [ ] With the equalizer on, the Audio sheet lists an Equalizer row naming the
      preset; for HLS or an item without audio it reads "On · unavailable".

## Equalizer

The tap path has only been host-tested and compile-checked. Everything below
needs a person with headphones, because a curve that is computed correctly can
still be audible as a click, a gap or no change at all.

- [ ] Open Now Playing and tap the equalizer control: the sheet opens at the
      large detent and Done dismisses it. The control reads as active only while
      a curve is shaping the signal.
- [ ] Enable the equalizer with a flat curve: the audio is unchanged, the
      control stays inactive, and nothing clicks.
- [ ] Pick Monochrome presets and Classic presets in turn: each applies without a
      click or a dropout, and the curve, the peak/preamp sentence and the fader
      positions agree.
- [ ] Drag a graphic band: the sound and the curve change as the finger moves,
      the gain snaps to 0.5 dB, and double-tapping the band returns it to 0 dB.
- [ ] In parametric mode, add a band, change its type, frequency, gain and Q, and
      remove it: every change is audible and no change cuts the audio out.
- [ ] With Auto preamp on, raising a boost does not make playback louder or
      quieter overall; switching to Manual and lowering the preamp makes it
      quieter.
- [ ] Push the curve until the clip light comes on: it appears within about a
      second, and clears when the level drops or the preamp is lowered.
- [ ] Dynamic Boost at 6 dB on quiet material: it gets louder, and the loudest
      passages do not distort. It cannot make loud material louder.
- [ ] Stereo width at 0% collapses to mono and at 200% widens; no channel swap.
- [ ] Turn the equalizer off while playing: the audio returns to unmodified and
      the change does not click or drop out.
- [ ] Play a track while the equalizer is on, lock the screen, and change tracks
      from the Lock Screen: playback continues with the curve still applied. The
      tap is rebuilt per item; the equalizer must survive that.
- [ ] Skip through five or more tracks with the equalizer on: no clicks, no
      silence after a track change, and no track plays with the previous track's
      curve on a different sample rate.
- [ ] Let one track end and the next start on its own: the same applies.
- [ ] Repeat with a permanent download and with a cached track, not only a
      stream.
- [ ] Play an HLS or other unprocessable item: the sheet shows the unavailable
      banner, the controls stay readable but the audio is untouched, and no row
      claims the equalizer is acting.
- [ ] Import a text file from Files with an AutoEQ profile: the bands replace the
      curve, the summary reports ignored or clamped lines, and the sound changes.
- [ ] Export the current curve, then import that file: the curve returns
      unchanged.
- [ ] Save the current curve as a preset, relaunch the app, and confirm it is
      still there and still selected; delete it and confirm the selection falls
      back to Flat.
- [ ] Kill the app mid-playback with the equalizer on and relaunch: the saved
      state is restored and the first track plays with it.
- [ ] VoiceOver: each fader reads its frequency and gain in decibels, adjusts in
      0.5 dB steps, and the curve is skipped rather than read as an image.
- [ ] Layout at the largest Dynamic Type size and on the smallest supported
      iPhone: the ten faders, the parametric rows, the value labels and the
      import/export buttons stay on screen or scroll without overlap.

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
`AVPlayerItemErrorLog` events under subsystem `com.katsukiineko.monochrome`,
categories `player` and `audio-session`. A failed start now shows an error with
a Retry action instead of staying in the loading state.

Cache decisions are logged under the same subsystem with `cache hit`,
`cache miss`, `cache download start`, `cache download finish`,
`cache download failed`, `cache skip reason=…`, `cache cancel reason=…`,
`cache clear removed=…`, `cache slot released`, and the loop logs
`loop source=cache` or `loop source=network`. Each line carries the track id or
cache key, so it can be matched to what was on screen.

The equalizer logs `eq unavailable reason=…` (HLS, no audio track), `eq state
enabled=true|false filters=… sampleRate=…` on every change, `eq tap prepare
sr=… ch=… interleaved=… float=…` once per item, and `eq tap frames=…` once a
second. A curve that appears to do nothing while `frames` stays at zero means
the tap is not receiving audio; a curve that does nothing on a track that logged
`eq unavailable` is expected.

## Download metadata and export

- [ ] Download a FLAC track; then, on a Mac or PC, confirm the file carries
      TITLE, ARTIST and ALBUM in its Vorbis comments and a front-cover picture
      (a tags viewer or `metaflac --list` shows it).
- [ ] Open the artwork on the Lock Screen or in Files' preview: the embedded
      cover matches the track, not a previous one.
- [ ] Downloads row context menu shows "Export to Files"; the share sheet opens
      and saving to Files produces a playable FLAC with the same tags.
- [ ] Export an AAC download: the file is shared unchanged and no error appears.
- [ ] With no network, exporting still works; a download that finished offline
      has tags but no cover, and playback is unaffected either way.

## Artist biography and links

- [ ] Open an artist page for an artist with a biography: the About section
      shows the text, collapsed to four lines with Show More / Show Less.
- [ ] Long biographies expand and collapse without breaking the list layout.
- [ ] The outbound link row opens Safari with the artist's link; the row reads
      correctly under VoiceOver.
- [ ] An artist with no biography shows no About section at all.

## Playlist import and export

- [ ] Library → Playlists → Import playlist: pick a CSV with a header row; the
      import sheet shows the format, the progress and how many entries matched.
- [ ] An entry with no close match appears under "Needs review"; tapping a
      candidate chooses it, "Skip this track" drops it, and the counts update.
- [ ] Save the import: a new playlist appears in the Library with the matched
      songs and the name typed in the sheet.
- [ ] Pause an import with many entries, leave the app, come back and continue:
      the run resumes without matching the same entries twice.
- [ ] Import a file with more than 500 entries: the sheet reports the drop and
      the playlist holds at most 500 songs.
- [ ] Playlist menu → Export as JSON and Export as CSV: the share sheet opens
      and the saved file re-imports into the same playlist.
- [ ] VoiceOver reads the import rows, the candidate buttons and the save
      button; Dynamic Type at the largest size does not hide the save button.

## For You shelf and taste profile

- [ ] Fresh install: the Home screen shows "For you — LEARNING" with the line
      "Play a few tracks and your picks will show up here."
- [ ] Play about 20 tracks over more than one artist, then reopen the app: the
      "For you" shelf lists tracks and every row names the reason, for example
      "Because you play <artist>".
- [ ] The first ten rows hold at most two tracks per artist; the Rediscover
      shelf below lists tracks from the own library.
- [ ] Skip a track after a few seconds, play another one to the end: the next
      refresh no longer offers the skipped artist.
- [ ] Tap a track row → "More like this": the shelf changes after the next
      refresh and the artist of that track appears more often.
- [ ] Tap a track row → "Not for me": the track and its artist disappear from
      the shelf after the next refresh.
- [ ] Settings → Recommendations: switch "Personal Picks" off, the shelf
      disappears from Home and the feedback actions leave the track menus;
      switch it on again and the shelf returns.
- [ ] Settings → Recommendations → "Reset Taste Profile": the log is cleared,
      the shelf falls back to the learning state and the next plays rebuild it.
- [ ] Leave the app for a week and come back: older plays count less, so the
      shelf leans on the recent listens.
- [ ] VoiceOver reads the shelf rows with their reason; Dynamic Type at the
      largest size keeps the reason visible.

## Radio

- [ ] Long-press a search or library track → "Start radio": the track plays and
      the queue fills with tracks of the same artist.
- [ ] Open the queue sheet: the "Next in Queue" header reads RADIO and the
      ellipsis menu offers "Stop radio".
- [ ] Let the queue fall to three remaining tracks: more tracks appear without
      a gap and playback continues.
- [ ] After 50 played tracks, none of them comes back in the radio.
- [ ] Pick a track outside the radio from Search or Library: the radio ends and
      the queue is the new selection only.
- [ ] Artist page → "Start radio": tracks of that artist fill the queue.
- [ ] Play with no network when the queue runs low: playback of the queued
      tracks continues and the radio fills again once the network is back.
- [ ] VoiceOver reads the Start radio action and the Stop radio action.

## Podcasts

- [ ] Library → Podcasts, type a show name: rows appear with artwork, show
      title, author and genre.
- [ ] Open a show: the episode list shows the newest episodes with date,
      duration and a short plain-text summary.
- [ ] Tap an episode: it plays through the player with the show artwork, the
      show title as album and the author as artist; Lock Screen metadata matches.
- [ ] Seek and resume an episode; the position behaves like a song stream.
- [ ] A show whose feed is unreachable shows the error with Retry; Retry loads
      the episodes once the network is back.
- [ ] A show that lists only a non-HTTPS feed shows the HTTPS error instead of
      playing.
- [ ] VoiceOver reads each show row and each episode row with its date and
      duration; Dynamic Type at the largest size keeps the rows readable.
- [ ] Background playback and Control Center controls work on a podcast episode
      exactly as on a song.
