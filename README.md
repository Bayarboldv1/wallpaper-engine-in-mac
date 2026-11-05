# wallpaper-engine-in-mac

Luma is a native macOS live wallpaper app, built with SwiftUI, AppKit, AVFoundation, and WebKit. Requires macOS 14 or later. No external dependencies.

## Run

```sh
./scripts/build-app.sh
open dist/Luma.app
```

The script builds a release app and signs it locally. Xcode Command Line Tools with Swift 6 or later are sufficient. To run directly during development, use `swift run Luma`.

## Use

- Select Aurora, Ember, or Tide to preview a bundled animated scene.
- Choose a display and click **Set wallpaper**. The display menu also offers apply-to-all and restore controls.
- Use **Add wallpaper** (⌘O) to import an MP4, MOV, M4V, HTML file, or web folder with a top-level `index.html`.
- Favorite scenes with the heart button; right-click imported items to reveal or remove them.
- Pause or mute from the library or Luma's menu bar icon. Closing the library keeps desktop playback running; quitting Luma restores the underlying macOS wallpaper.

Videos are validated with AVFoundation and copied into `~/Library/Application Support/Luma/Wallpapers/`. Web wallpaper folders are referenced in place, with read access restricted to the selected HTML file's directory. Keep these folders at their original location. Library preferences and per-display assignments are saved in `~/Library/Application Support/Luma/library.json` and restored on launch.

## Playback

Each connected display gets a click-through desktop-level window. Desktop icons remain interactive. Playback pauses for system sleep, display sleep, inactive desktop sessions, and optionally Low Power Mode. The library preview pauses when Luma is inactive, minimized, or closed. Built-in scenes cap rendering at 30 fps and limit canvas resolution.

Local web scenes run in an ephemeral WebKit data store with no native bridge. Top-level navigation stays within the scene folder. Web resources can still make network requests. Only import web code you intend to run. For efficient custom scenes, implement:

```js
window.wallpaperSetPaused = paused => { /* suspend/resume your animation loop */ };
window.wallpaperSetMuted = muted => { /* optionally control Web Audio */ };
```

Luma also suspends media, CSS animations, and `requestAnimationFrame` callbacks when paused. Arbitrary web timers, workers, and Web Audio require cooperation from the scene.

## Tests

```sh
./scripts/test.sh
```

The test suite checks import validation, asset roots, library persistence, and stable bundled wallpaper identifiers. Desktop window behavior needs manual checks on macOS, especially after changing Spaces, display arrangements, and system wallpaper settings.

## MVP scope

This version supports video and local web wallpapers. Wallpaper Engine scene packages, Steam Workshop integration, a scene editor, audio-reactive system capture, login auto-start, and lock-screen wallpapers are future work. Fullscreen and Spaces behavior can vary with macOS and Stage Manager settings. Distribution outside this Mac requires Developer ID signing and notarization.
