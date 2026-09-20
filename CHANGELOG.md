# Changelog

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and
the project uses [semantic versioning](https://semver.org/spec/v2.0.0.html).

## Unreleased

### Changed

- With only the current line shown, a line that does not fit now scrolls along
  with the playback: it starts at its beginning when the line starts and reaches
  its end just as the next line starts, instead of looping at a fixed speed. It
  rests for 300 ms at both ends, stops while the track is paused and follows
  seeks. The scrolling is a Core
  Animation instead of a 30 fps timer, which takes the load off the CPU.
- The timer that follows the current line now runs only while a playing track
  has lyrics, so the app no longer wakes the main thread ten times a second
  while Spotify is closed or paused.

## 0.1.0 - 2026-09-18

First release.

### Added

- Menu bar item that shows the current lyric line of the song playing in the
  Spotify desktop app, followed by the track and artist and the app icon. The
  line scrolls when it does not fit.
- Playback tracking through the `com.spotify.client.PlaybackStateChanged`
  distributed notification, with the position interpolated between AppleScript
  resyncs once a second while playing.
- Synced lyrics from LRCLIB (`/api/get`, falling back to `/api/search`), cached
  as one JSON file per track under `~/Library/Caches/com.todesking.lyribar/lyrics/`.
- Status menu with the current track, the state of the lyrics, Settings… and
  Quit.
- Settings window: maximum width, whether to show the track and artist, launch at
  login, and clearing the lyrics cache.
- `Scripts/build-app.sh` for the `.app` bundle (`--universal` for arm64 +
  x86_64), `Scripts/release.sh` for the release zip, and
  `Scripts/generate-icon.sh` for the app icon.
