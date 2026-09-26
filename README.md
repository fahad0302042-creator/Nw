# Kuroyomi

A minimal, **extension-driven manga reader and anime player** for Android, written in Flutter.

The app ships with **no sources and no content**. You add an *extension repository url*, install the
sources you want, and the app fetches everything from there — the same idea behind Tachiyomi/Mihon
style readers, but the extensions here are plain JSON files instead of APKs, so no code is executed
and nothing extra needs to be side-loaded.

> **Build without a PC:** every push triggers a GitHub Actions run that analyzes, tests and builds a
> release APK. Grab it from the **[nightly release](../../releases/tag/nightly)** on your phone.

---

## Features

| Area | What works |
| --- | --- |
| Extensions | Add/remove repositories by url, browse the catalogue, install/uninstall individual sources |
| Sources | HTML (CSS selectors), JSON (dotted paths) and raw-regex scraping, per-source headers |
| Browsing | Popular / Latest tabs, search, infinite scroll, cover grid |
| Details | Description, author, status, genres, chapter or episode list, read markers |
| Reader | Webtoon (continuous vertical) and paged modes, RTL toggle, pinch zoom, resume position |
| Player | ExoPlayer based video playback, MP4 + HLS, quality switcher, next/previous episode |
| Library | Favourites, persisted locally, reading progress per chapter |

Everything is stored locally on device (`SharedPreferences`); there is no account and no backend.

---

## Getting the APK

1. Open the **Actions** tab (or the [nightly release](../../releases/tag/nightly)) on your phone.
2. Download `kuroyomi-<sha>.apk`.
3. Android will ask to allow installs from your browser — accept, then install.

## Trying it out

1. Open the app → **Extensions** tab.
2. Tap **Load demo repository**. This installs two self-contained demo sources served from this very
   repo (`example_repo/`), using generic placeholder artwork and freely licensed sample videos.
3. Install *Demo Manga* and/or *Demo Anime*, then switch to **Browse**.

The demo repo exists so you can confirm the whole pipeline — listing, details, chapters, reader,
player — works on your device before pointing the app at any real site.

---

## Writing extensions

See **[docs/EXTENSIONS.md](docs/EXTENSIONS.md)** for the full schema, plus HTML and JSON examples.

A repository is one JSON file:

```json
{
  "name": "My repo",
  "sources": [ { "id": "my-site", "name": "My Site", "type": "manga", "baseUrl": "https://example.com", "endpoints": { } } ]
}
```

Paste its **raw** url (e.g. `https://raw.githubusercontent.com/user/repo/main/index.json`) into the
Extensions tab. GitHub `blob` links and bare folder urls are normalised automatically.

---

## Project layout

```
lib/
  core/            http client, url helpers
  models/          media, chapter, video data classes
  extensions/      rule → extractor → engine → repo service   (the scraping core)
  data/            app state + local persistence
  ui/              library, browse, details, reader, player, extensions, settings
example_repo/      self-contained demo repository
test/              unit tests for the engine + widget smoke tests
tool/              prepare_android.sh (generates the native android project)
.github/workflows/ CI: analyze → test → build APK → publish nightly
```

The `android/` folder is **not** committed — `tool/prepare_android.sh` regenerates it with
`flutter create` and patches the app id, label, `INTERNET` permission and `minSdk`. This keeps the
repo small and avoids checking in the Gradle wrapper binary.

## Building locally (optional)

```bash
flutter pub get
flutter test
bash tool/prepare_android.sh
flutter build apk --release
```

## Legal

Kuroyomi is a generic content reader. It bundles no sources, no links and no copyrighted material —
only the demo repository, which uses placeholder images and openly licensed sample videos. Whatever
repositories you add, and whether you have the right to access that content, is entirely your
responsibility.
