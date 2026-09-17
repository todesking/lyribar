# Changelog

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and
the project uses [semantic versioning](https://semver.org/spec/v2.0.0.html).

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
