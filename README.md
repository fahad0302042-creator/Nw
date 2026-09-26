# Kurayomi

A **manga and anime** reader for Android, built with Flutter, with a
**JavaScript extension runtime** — in the spirit of Tachiyomi / Mihon /
Aniyomi / Kotatsu.

The app ships with **no content sources at all**. You add repositories, and
repositories provide extensions. What you point it at is up to you.

---

[![CI](https://github.com/fahad0302042-creator/Nw/actions/workflows/ci.yml/badge.svg?branch=arena/01a0dc0e-nw)](https://github.com/fahad0302042-creator/Nw/actions/workflows/ci.yml)

Builds green on Flutter 3.47.5 / JDK 17. Every successful CI run attaches an
installable **debug APK** as an artifact.

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
| Cloudflare / DDoS-Guard / Sucuri bypass (WebView) | ✅ |
| Headless JS rendering for client-side sites | ✅ |
| OLED theming, 7 palettes, grid options | ✅ |
| CI: analyze + 78 unit tests + 13 runtime tests + APK build | ✅ |
| Downloads: offline chapters & episodes | ✅ |
| Categories (many-to-many, reorderable) | ✅ |
| Trackers: AniList + MyAnimeList, auto progress sync | ✅ |
| Backup & restore (JSON, merge-based) | ✅ |
| Library update checks + notifications | ✅ |

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
* ✅ Cloudflare/DDoS-Guard checks are solved in a WebView, transparently.

---

## Getting started

```bash
bash tool/bootstrap.sh    # generates android/, patches the manifest, pub get
flutter run
```

Requires **Flutter 3.24+**, **JDK 17** and the Android SDK.
Full instructions and troubleshooting: **[docs/BUILD.md](docs/BUILD.md)**.

The `android/` folder is generated rather than committed, so it always
matches your own Flutter SDK. `bootstrap.sh` is idempotent — re-run it
whenever you like.

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

## A word on Keiyoushi / Aniyomi extensions

**They cannot work here, and never will.** Those extensions ship as Android
APKs containing compiled JVM classes, loaded through Android's
`PathClassLoader`. Flutter has no equivalent — this is a hard platform
limitation, not a missing feature.

Pasting a Keiyoushi repository URL now gives a clear explanation rather than
silently importing hundreds of entries that fail on install.

Kurayomi therefore defines its own **JavaScript** extension format, shaped
deliberately close to the Tachiyomi API so porting a source is mostly a
mechanical rewrite. See [docs/EXTENSIONS.md](docs/EXTENSIONS.md).

---

## Downloads

Tap the download icon on any chapter or episode, or use **Download next
1 / 5 / 10 / all** from the title screen. Queued work is persisted, so an app
killed mid-download resumes rather than forgetting.

- Two units download at once, three pages in parallel within a chapter.
  Sources rate-limit hard, and a 50-way parallel fetch is the fastest route
  to a temporary IP ban.
- Every file is written to `.part` and renamed on success, and the folder
  only gets its `.complete` marker last — so a chapter interrupted by a
  crash can never be mistaken for a finished one and read as truncated.
- Downloads reuse the normal HTTP client, so they carry Cloudflare clearance
  and cookies like any other request.
- Already-downloaded pages are skipped on retry.

**Anime:** progressive MP4 downloads directly. HLS is parsed, the
highest-bandwidth rendition selected, and segments concatenated in order
(including `EXT-X-MAP` init segments). **Encrypted HLS is refused up front**
with a clear message rather than writing a file you would only discover is
unplayable once offline.

Once downloaded, the reader and player read straight from disk — no network,
and not even a source lookup. Manage everything in **More → Downloads**:
queue, progress, space used, and per-item deletion.

---

## Library, categories and updates

Titles can sit in several categories at once (Mihon-style many-to-many), and
the Library shows a chip strip to filter by one. Categories are reorderable.

**Check for new chapters** from the Library toolbar walks your library
sequentially with a short delay between titles — 200 series fetched in
parallel looks like an attack, and the resulting ban hurts you, not the
site. It runs the HTTP client in non-interactive mode so a background check
can never pop a Cloudflare WebView in your face; challenged titles are
skipped until you open them. New-chapter counts appear as a badge on covers,
and a local notification summarises the run.

---

## Tracking

Link titles to **AniList** or **MyAnimeList** and progress is pushed as you
read.

Both need a **client ID you register yourself** (More → Tracking explains
where). That is deliberate: a client ID baked into open-source code can be
impersonated by anyone, and both services tie rate limits and bans to it.

- AniList uses the implicit grant — no client secret, which a public client
  could not keep anyway.
- MyAnimeList uses OAuth2 with PKCE, and refreshes its token silently.
- Progress only ever moves **forwards**, so re-reading chapter 3 of a series
  you finished cannot tell AniList you regressed.
- Reaching the final chapter marks the entry completed.
- A tracker failure never interrupts reading — it is logged, not thrown.

---

## Backup & restore

**More → Backup & restore** writes one JSON file containing your library,
read progress, categories, tracker links, repository URLs and the list of
extensions you had.

It deliberately excludes covers, downloaded chapters and cookies: they are
re-fetchable or device-specific, and a multi-gigabyte backup is one nobody
actually makes.

Restoring **merges** — nothing is deleted. The file is validated before
anything is touched, and extensions are **not** auto-installed, because that
would mean silently downloading and executing code. Their repositories are
restored so reinstalling is one tap.

---

## Anti-bot handling

Most real sources sit behind Cloudflare. An HTTP client cannot pass its JS
challenge — it runs WebAssembly, times canvas operations and fingerprints the
JS environment. So the app does the only thing that reliably works:

1. `AppHttpClient` sends the request with the stored cookie jar and the
   host-pinned User-Agent.
2. `ChallengeDetector` recognises an interstitial (`cf-mitigated` header, or a
   403/503 carrying a challenge HTML body — a 403 with a JSON body is treated
   as a genuine auth error, not a challenge).
3. A WebView opens, runs the challenge, and the `cf_clearance` cookie is
   harvested **together with the WebView's own User-Agent** — clearance is
   bound to that exact UA, so both must be stored and replayed.
4. The request is retried once. If it fails again the stale clearance for that
   host is dropped so the next attempt starts clean.

Solving is **de-duplicated per host**: if twenty page images hit a challenge
at once, exactly one WebView opens and the other nineteen await it.

Cookies and UA are also injected into cover loading, reader images and video
streams — a common failure mode is the HTML fetch succeeding while every
image 403s, because the CDN checks the same clearance.

Manage all of this in **More → Network & browser**: inspect which hosts hold
clearance, open any site manually to log in ahead of time, or clear
everything when a source mysteriously stops working.

---

## Appearance

Seven palettes, default **Pure Black** (`#000000`) so OLED pixels are
physically off. The design uses iOS structural cues — hairline separators,
frosted translucent chrome, large collapsing titles, Cupertino page
transitions — with Material 3 underneath. Grid density and cover titles are
configurable in **More → Appearance**.

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
├── data/
│   ├── db/app_database.dart      sqflite: items, units, read state
│   └── net/
│       ├── cookie_store.dart     per-host cookie jar + pinned User-Agent
│       ├── cloudflare.dart       challenge detection
│       ├── app_http_client.dart  cookies + solve + retry, de-duped per host
│       └── headless_renderer.dart off-screen WebView for JS-rendered pages
└── features/                     library · browse · details · reader · player · settings
extensions_repo/                  a working example repository
docs/EXTENSIONS.md                how to write an extension
docs/BUILD.md                     build, run and troubleshooting
tool/bootstrap.sh                 one-command environment setup
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
