# Nw

Nw is an Android TV-first manga reader built on a Mihon-compatible foundation.

## Current state

The repository is currently a clean Android project scaffold with a focused TV UX prototype:

- Leanback launcher support and landscape-first layout
- D-pad-friendly navigation rail with clear focus states
- Continue reading and popular manga shelves
- Manga detail screen with Read and Add to library actions
- Reader preview with remote-friendly controls
- TV-safe dark theme, large type, and high-contrast surfaces

The current data is intentionally local demo data. The next milestone is wiring Mihon's data layer and extension compatibility behind this UI without changing the TV interaction model.

## Build

Open the repository in Android Studio Ladybug or newer and run the `app` configuration on an Android TV emulator/device. The app targets Android 8.0+ (`minSdk 26`) and Android TV (`leanback` feature).

## UX principles

1. Every action must be reachable with a D-pad or keyboard.
2. Focus is always visible; touch is optional rather than required.
3. Reading should take no more than two clicks from Continue reading.
4. Download and sync state should be visible without opening settings.
5. Mobile and TV presentation should share the same data, downloads, and reading progress.
