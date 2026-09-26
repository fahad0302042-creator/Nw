# Kurayomi

A **manga and anime** reader for Android, built with Flutter, with a
**JavaScript extension runtime** — in the spirit of Tachiyomi / Mihon /
Aniyomi / Kotatsu.

The app ships with **no content sources at all**. You add repositories, and
repositories provide extensions. What you point it at is up to you.

---

## Status

| Area | State |
|---|---|
| Domain models (manga + anime unified) | ✅ |
| JS extension runtime (QuickJS bridge, HTTP, HTML/CSS selection) | ✅ |
| Extension repos: add / install / update / uninstall | ✅ |
| Browse: popular / latest / search, infinite scroll | ✅ |
| Details + chapter/episode list with cache-first loading | ✅ |
| Manga reader: webtoon + paged LTR/RTL, zoom, progress | ✅ |
| Anime player: HLS + MP4, quality switch, resume | ✅ |
| Library, history, read state | ✅ |
| Downloads / offline | ⬜ planned |
| Trackers (AniList, MAL) | ⬜ planned |
| Backup & restore | ⬜ planned |

---

## Why JavaScript extensions (and not Aniyomi `.apk` extensions)

Tachiyomi/Mihon/Aniyomi extensions are **Android APKs containing compiled
Kotlin classes**, loaded at runtime with `PathClassLoader`. A Flutter/Dart
app cannot load them — there is no JVM in the process to run them in.

So Kurayomi defines its own extension format: a **single JavaScript file**
executed in a sandboxed QuickJS runtime. The API is deliberately shaped like
Tachiyomi's `HttpSource`, so porting an existing extension is a mechanical
translation (`popular`, `latest`, `search`, `details`, `chapters`/`episodes`,
`pages`/`videos`) rather than a redesign.

Trade-offs, stated plainly:

* ✅ One codebase, one extension format for both manga and anime.
* ✅ Extensions are plain text — inspectable, hot-swappable, no APK install prompts.
* ✅ Each extension runs in its own isolated JS runtime.
* ❌ The thousands of existing Keiyoushi/Aniyomi extensions do **not** work as-is.
* ❌ No Cloudflare-bypass WebView step yet (planned).

---

## Getting started

```bash
# 1. Generate the Android platform folder (this repo only holds Dart + assets)
flutter create . --platforms=android --org com.example --project-name kurayomi

# 2. Restore the pieces flutter create overwrites
bash tool/setup_android.sh

# 3. Run
flutter pub get
flutter run
```

Requires Flutter **3.24+** / Dart 3.4+.

### Try it immediately

Serve the bundled demo repo and add it in-app:

```bash
cd extensions_repo && python3 -m http.server 8080
```

Then in the app: **Browse → Extensions → Repositories → +** and add
`http://10.0.2.2:8080/index.json` (emulator) or
`http://<your-lan-ip>:8080/index.json` (physical device).

Install *Sample Manga (Demo)* and *Sample Anime (Demo)*. The manga source is
fully offline; the anime source plays real public test streams. Together they
exercise every path in the app.

---

## Project layout

```
lib/
├── main.dart                     bootstrap (db, media_kit, ProviderScope)
├── app.dart                      MaterialApp + bottom-nav shell
├── core/
│   ├── providers.dart            Riverpod graph
│   └── theme.dart                dark-first Material 3 theme
├── domain/
│   ├── models/media.dart         MediaItem / MediaUnit / ReaderPage / VideoStream
│   └── source/                   MediaSource contract + filter model
├── extensions/
│   ├── js_prelude.dart           the JS stdlib injected into every extension
│   ├── js_runtime.dart           QuickJS host: http, HTML parsing, storage
│   ├── js_source.dart            MediaSource backed by a JS extension
│   ├── extension_repository.dart repo index.json fetching
│   └── extension_manager.dart    install / update / uninstall / load
├── data/db/app_database.dart     sqflite: items, units, read state
└── features/                     library · browse · details · reader · player · settings
extensions_repo/                  a working example repository
docs/EXTENSIONS.md                how to write an extension
```

---

## Writing an extension

See **[docs/EXTENSIONS.md](docs/EXTENSIONS.md)**. The short version:

```js
class MySource {
  constructor() {
    this.id = 'en.mysite'; this.name = 'MySite';
    this.lang = 'en'; this.baseUrl = 'https://mysite.example';
    this.type = 'manga';               // or 'anime'
  }
  async popular(page) {
    const doc = await http.getDoc(`${this.baseUrl}/popular/${page}`);
    const cards = await doc.select('div.card');
    const items = [];
    for (const c of cards) {
      const a = await c.selectFirst('a');
      const img = await c.selectFirst('img');
      items.push({
        url: await a.absUrl('href'),
        title: a.attr('title'),
        thumbnailUrl: await img.absUrl('src'),
      });
    }
    return { items, hasNext: cards.length > 0 };
  }
  async details(item) { /* ... */ }
  async chapters(item) { /* ... */ }
  async pages(chapter) { /* ... */ }
}
registerSource(new MySource());
```

---

## Legal

Kurayomi is a **client**. It bundles no sources, no catalogue, and no content,
and it makes no network requests until you add a repository yourself. You are
responsible for what you point it at, and for complying with the law and with
the terms of service of any site you access. Please support official releases.
