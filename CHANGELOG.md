# Changelog

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and
the project uses [semantic versioning](https://semver.org/spec/v2.0.0.html).

## Unreleased

### Fixed

- Opening the settings from another desktop (Space) than the one they were last
  closed on now shows the window on the current desktop, instead of switching
  back to the old one.
- A failing read of the playback state no longer clears the lyrics. The app used
  to fall back to "Not playing" whenever the AppleScript it resyncs with failed,
  for instance when Automation for Spotify is denied or the Apple Event times
  out, and it stayed that way until the next track change. It now keeps what it
  knows and tries again a second later; Spotify quitting still empties the bar.
- The lyrics cache is keyed by track id instead of artist, title, and duration,
  so tracks that share those (explicit/clean, re-recordings) no longer collide
  and Spotify's provisional duration right after a track change no longer
  splits one track's lyrics across two cache entries. The cache is rebuilt as
  tracks are looked up again; existing cache files are unused going forward but
  are still cleaned up by "Clear lyrics cache".
- Saving or removing the Spotify cookie while a lyrics fetch had failed no
  longer lets the retry that was waiting for the old conditions fire afterwards,
  which made the bar flicker back to "Loading lyrics…" and sent a needless
  request. A fetch that fails right after the cookie changed now gets an
  automatic retry of its own, even if the previous conditions had used theirs up.
- LRCLIB's search fallback now only considers results whose duration is close
  to the playing track's, picking the closest match. It used to take the first
  result with synced lyrics regardless of duration, so a Live, Remix, or
  Extended version that missed the exact match could pull a mistimed original
  version's lyrics from search and cache them.

## 0.2.0 - 2026-09-21

### Changed

- The scrolling lyrics ribbon eases from the pace of one line into the next
  instead of changing speed where two lines meet. Every line still reaches the
  middle of the lyric area exactly at its own time.
- The ribbon reacts to play, pause and seeks at once instead of on the next
  tick, glides over small corrections instead of jumping, and no longer shows a
  stale position after switching Spaces while paused.
- The status item is drawn with Core Animation layers, and the ribbon scrolls
  with a single animation over the whole track. This removes the CPU load the
  app caused while lyrics were shown, including while paused.
- Saving or removing the Spotify cookie fetches the lyrics of the playing track
  again right away, so it switches sources without waiting for the next track.
  Lyrics cached for other tracks stay as they are.
- A debug build keeps the Spotify cookie in a Keychain item of its own
  (`com.todesking.lyribar.debug`).
- With only the current line shown, a line that does not fit now scrolls along
  with the playback: it starts at its beginning when the line starts and reaches
  its end just as the next line starts, instead of looping at a fixed speed. It
  rests for 300 ms at both ends, stops while the track is paused and follows
  seeks. The scrolling is a Core
  Animation instead of a 30 fps timer, which takes the load off the CPU.
- The timer that follows the current line now runs only while a playing track
  has lyrics, so the app no longer wakes the main thread ten times a second
  while Spotify is closed or paused.
- The Settings window now shows the app version at the bottom.

## 0.1.0 - 2026-09-18

First release.

### Added

- Menu bar item that shows the lyrics of the song playing in the Spotify desktop
  app, followed by the track and artist and the app icon.
- Scrolling lyrics (the default display): the lines are laid out on one ribbon
  that scrolls with the playback position, with the line being sung in the
  middle of the lyric area and in the full text color, and the lines around it
  dimmed.
- Current line only, as the other display: one line at a time, which scrolls
  when it does not fit.
- Playback tracking through the `com.spotify.client.PlaybackStateChanged`
  distributed notification, with the position interpolated between AppleScript
  resyncs once a second while playing.
- Synced lyrics from LRCLIB (`/api/get`, falling back to `/api/search`), cached
  as one JSON file per track under `~/Library/Caches/com.todesking.lyribar/lyrics/`.
- Optional, unofficial Spotify lyrics: with the `sp_dc` cookie of a Spotify web
  session stored in the macOS Keychain, lyrics are looked up by track ID at
  Spotify first, then at LRCLIB. Off by default.
- Status menu with the current track, the state of the lyrics, Settings… and
  Quit.
- Settings window: maximum width, the lyrics display, whether to show the track
  and artist, launch at login, the Spotify cookie, and clearing the lyrics cache.
- `Scripts/build-app.sh` for the `.app` bundle (`--universal` for arm64 +
  x86_64), `Scripts/release.sh` for the release zip, and
  `Scripts/generate-icon.sh` for the app icon.
