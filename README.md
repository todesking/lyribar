# Lyribar

Lyribar is a macOS menu bar app that shows the lyrics of the song currently
playing in Spotify. It lives in the status bar only, with no Dock icon or
window of its own.

## Usage

Run from the command line during development:

```sh
swift run
```

Build a signed `Lyribar.app` into `build/`:

```sh
Scripts/build-app.sh            # host architecture only
Scripts/build-app.sh --universal  # arm64 + x86_64
```

## License

MIT. See [LICENSE](LICENSE).
