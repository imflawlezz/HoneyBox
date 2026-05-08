# HoneyBox

HoneyBox is an iOS app for organizing **image galleries** grouped by **creator (author)** and **album**. Everything lives on-device: a local filesystem layout plus a JSON index—no cloud dependency in the codebase.

## Requirements

- **Xcode** 26.3 or newer (matches the project’s `LastUpgradeCheck`)
- **iOS** 26.2+ deployment target (iPhone and iPad)
- **Swift** 5

## Build and run

1. Open `HoneyBox.xcodeproj` in Xcode.
2. Select the **HoneyBox** scheme and a simulator or device.
3. Build and run (**⌘R**).

Swift Package Manager resolves dependencies on first resolve; [ZIPFoundation](https://github.com/weichsel/ZIPFoundation) (0.9.20) is used for ZIP-based library backup and archive import.

## What it does

- **Home**: Continue reading, latest / favorite / not-yet-viewed galleries, shuffle-all entry, import, and Settings.
- **Albums**: Browse artists (authors), open albums, edit titles and order, favorites, continue-reading bookmarks, thumbnails, and fullscreen / immersive viewers (including GIF playback where supported).
- **Import**: Photos picker, Files, or importing a numbered gallery packaged as `.zip`; you can also append images to existing albums.
- **Settings**: Optional **Face ID / Passcode** app lock, **export** and **restore** the whole library as `.zip`, slideshow interval for immersive playback, and the on-disk **library root path** (for support and backups).

## Project layout (high level)

| Area | Role |
|------|------|
| `HoneyBox/App/` | App entry, environment wiring, app lock, small app-wide utilities |
| `HoneyBox/Domain/` | Models, repository protocols, library listing types |
| `HoneyBox/Infrastructure/` | Storage, indexing, import pipeline, ZIP service, image loading |
| `HoneyBox/Application/` | Cross-cutting queries (e.g. browse helpers) |
| `HoneyBox/Presentation/` | SwiftUI: tabs, home, albums, viewer, shuffle, settings |

On disk, the library uses an `authors/` tree, per-album `images/` and `thumbnails/`, plus a root `index.json` (see `StoragePaths`).