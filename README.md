# Tsundoku

A minimal, open-source manga & anime reader for Android, in the spirit of
**Tachiyomi / Mihon / Komikku / Kotatsu** - but instead of compiled/binary
extensions, sources are plain **JSON manifests** you (or anyone) can host
anywhere and install by pasting a URL. No app update is ever required to
add a new site.

> Built and tested entirely through **GitHub Actions** - no desktop/PC
> required. See [Getting the app onto your phone](#getting-the-app-onto-your-phone)
> below.

## Features

- 📚 Library, Browse, Extensions and Settings tabs.
- 🧩 **No-code extension system**: install a source by pasting a repository
  index URL or a single manifest URL. Manifests describe popular/latest/
  search/detail/chapter/page endpoints with CSS selectors or JSON paths -
  see [`docs/EXTENSION_SPEC.md`](docs/EXTENSION_SPEC.md).
- 📖 Manga reader (continuous vertical scroll, pinch-to-zoom).
- 📺 Anime player (`video_player` + `chewie`), episode list, quality picker.
- 📡 Works against real HTML sites *and* JSON APIs (the bundled MangaDex
  extension uses the official public API end-to-end).
- 💾 Library + read/watch progress persisted locally, no account needed.
- 🚀 Three extensions are bundled and auto-installed on first launch so
  there's always something to try immediately:
  - **MangaDex** - real API, real manga, real reading.
  - **Demo Manga** / **Demo Anime** - fully offline sample content
    (public domain/CC placeholder images & Blender Foundation open movies)
    for a guaranteed-to-work demo of the reader/player pipeline.

## Project structure

```
lib/
  models/           Plain data models + the extension manifest schema
  core/
    parsing/        Tiny JSON-path / template / URL helpers (unit tested)
    source/         The generic fetch+parse engine that executes manifests
    repo/           Fetches repository indexes / single manifests from URLs
    storage/        Local JSON-file persistence (library, progress, repos)
  ui/               Screens: library, browse, extensions, detail, reader, player, settings
assets/extensions/  Bundled default extensions (see above)
docs/               Extension format spec + a runnable example repository
android/            Standard Flutter Android embedding
.github/workflows/  CI: analyze, test, build (and optionally release) APKs
test/               Unit tests for the parsing engine + a widget smoke test
```

## Adding a source

1. Open the **Extensions** tab.
2. Paste a repository index URL (lists many sources) or a direct link to a
   single extension's `*.json` manifest into the text field, then **Add**.
3. Install any extension you want from the list. It now shows up in
   **Browse**.

Want to write your own? Read [`docs/EXTENSION_SPEC.md`](docs/EXTENSION_SPEC.md)
and try `docs/example-repo/` as a starting point - it's a real, working
mini repository you can fork.

## Building & testing (GitHub Actions only - no PC needed)

Every push to any branch runs [`.github/workflows/android.yml`](.github/workflows/android.yml),
which:

1. Sets up JDK 17 + Flutter (stable).
2. Runs `flutter analyze` and `flutter test` (parsing engine unit tests +
   a widget smoke test - all network-free and deterministic).
3. Generates the Gradle wrapper JAR (kept out of git on purpose - see the
   comment in `.gitignore`) and builds:
   - a debug APK,
   - an unsigned release APK,
   - per-ABI split release APKs (smaller downloads).
4. Uploads all APKs as a build **artifact** you can download from the
   **Actions** tab of this repository (open the latest run → *Artifacts*).

### Getting the app onto your phone

- Go to the repo's **Actions** tab → open the latest successful **Android
  CI** run → download the `tsundoku-apks-*` artifact (a zip) → unzip it
  (most Android file managers, or "Files" apps, can unzip directly) → tap
  the `.apk` to install (enable "Install unknown apps" for your
  browser/file manager once, if prompted).
- Or trigger a proper **Release** instead of a plain artifact: go to
  **Actions → Android CI → Run workflow**, tick *"Publish the built APKs as
  a GitHub Release"*, run it, then grab the `.apk` straight from the
  **Releases** page (a direct file, no unzip needed).

The release APK is unsigned-but-debug-signed (uses the default debug
keystore) so it installs fine for personal use/sideloading without any
secrets configured. If you want a properly signed release for the Play
Store later, add your own keystore as `android/key.properties` (see the
comments in `android/app/build.gradle`) and GitHub secrets - not needed for
day-to-day sideloading.

## Why no local build instructions?

This project was built entirely inside a sandboxed agent environment with
no access to a desktop machine, Android SDK, or the Flutter tooling's
binary downloads - by design, everything is validated and produced by CI
instead. If you *do* have a PC later, this is a completely standard
Flutter project: `flutter pub get && flutter run` will work as usual.

## Roadmap / known limitations

- The extension engine is declarative (CSS selectors / JSON paths /
  regex) and cannot execute JavaScript or solve anti-bot challenges - see
  the "Limitations" section of the extension spec.
- No update-checking/"new chapters" badges yet - the Library tab shows
  read/unread state but doesn't background-poll sources.
- No manifest signature/allow-list system yet - only install extensions
  from sources you trust, exactly like Tachiyomi/Mihon repositories.
