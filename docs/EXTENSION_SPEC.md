# Tsundoku extension format (v1)

Tsundoku has **no compiled/binary extensions**. Every source is a single
JSON file (a "manifest") that declares, with CSS selectors or JSON paths,
how to pull popular/latest/search lists, a detail page, a chapter/episode
list, and page images/video links out of a website. The app ships with a
generic engine (`lib/core/source/source_engine.dart`) that executes any
manifest - adding a new site never requires writing or shipping Dart/Kotlin
code, and no app update is required either.

You can install extensions two ways from **Extensions** tab:

1. **A single manifest URL** - a direct link to one `*.json` file like the
   examples in `assets/extensions/` or `docs/example-repo/`.
2. **A repository index URL** - a JSON file listing many extensions, each
   either inlined or linked via `sourceUrl`. See
   `docs/example-repo/index.json`.

Both are just "paste a URL and press Add" in the app.

## Top-level manifest fields

```jsonc
{
  "id": "my-source",          // unique, stable, lowercase-kebab
  "name": "My Source",        // display name
  "lang": "en",                // language code shown in the UI
  "version": "1.0.0",
  "type": "manga",             // "manga" | "anime"
  "baseUrl": "https://example.com",
  "icon": "https://example.com/favicon.ico", // optional
  "description": "optional description",
  "nsfw": false,                // optional, for future filtering
  "headers": {                  // optional, sent on every request this source makes
    "User-Agent": "Mozilla/5.0 ..."
  },
  "popular": { ... },   // ListEndpoint, optional
  "latest": { ... },    // ListEndpoint, optional
  "search": { ... },    // ListEndpoint, optional
  "detail": { ... },    // DetailEndpoint, optional
  "chapters": { ... },  // ListEndpoint, optional (episodes for anime)
  "pages": { ... }      // PagesEndpoint, optional (video links for anime)
}
```

`type: anime` reuses the exact same shapes: `chapters` becomes the episode
list, and `pages` becomes the list of playable video links for one episode.

## FieldSpec

Used everywhere a single value needs to be pulled out of one item (an HTML
element or a JSON object):

| key | meaning |
|---|---|
| `selector` | CSS selector, relative to the item root (HTML mode) |
| `attr` | what to read from the matched element: `text` (default), `html`, `ownText`, or any attribute name (`href`, `src`, `data-src`, ...) |
| `path` | dotted/indexed path relative to the item root (JSON mode) - see below |
| `template` | build the value from `{otherField}` placeholders referencing fields already extracted for this same item (declaration order matters!) |
| `absolute` | resolve the extracted value into an absolute URL using `baseUrl` |
| `regex` / `regexGroup` | run a regex over the extracted string and keep only `regexGroup` (default `1`) |
| `list` | make this a `List<String>` instead of a single string |
| `itemPath` | (JSON, when `list: true`) sub-path extracted from every element of the array at `path` |
| `fallback` | literal value used when nothing was extracted |

### The JSON path mini-language

Segments are separated by `.`:

- `foo` - map key lookup
- `3` - list index lookup
- `key=value` - given the current value is a list of maps, find the first
  element whose `key` stringifies to `value`. This is what makes
  relationship arrays (e.g. MangaDex's `relationships`) easy to query:
  `relationships.type=cover_art.attributes.fileName`.

An empty path, `.`, or `$` returns the current value unchanged.

## ListEndpoint (`popular` / `latest` / `search` / `chapters`)

```jsonc
{
  "url": "https://example.com/manga?page={page}",   // supports {page}, {query}, {url} (chapters)
  "method": "GET",
  "responseType": "html",       // "html" | "json" | "static"
  "itemSelector": "div.manga-item",   // HTML: selector for each item's root
  "itemsPath": "data",                // JSON: dotted path to the items array
  "items": [ {"id": "1", "title": "Demo"} ],  // "static": items inlined right here, no request made
  "fields": { "id": {...}, "title": {...}, "cover": {...}, "subtitle": {...} }
}
```

- `{page}` is substituted with a 1-based page number; if your URL doesn't
  contain `{page}` the "Load more" button is hidden automatically.
- `{query}` (search only) is substituted with the URL-encoded search term.
- Chapter-list endpoints additionally receive `{url}` = the manga's stored
  id/URL.
- Recognised field names: `id`/`url` (required - the opaque id used for
  later requests), `title`, `cover`, `subtitle`. Chapter lists also read
  `number`, `date`, `scanlator`.

## DetailEndpoint (`detail`)

```jsonc
{
  "url": "https://example.com/manga/{url}",
  "responseType": "html",
  "rootSelector": "div.detail",  // optional scoping (HTML)
  "rootPath": "data",             // optional scoping (JSON)
  "fields": {
    "title": {...}, "cover": {...}, "description": {...},
    "status": {...}, "author": {...},
    "genres": { "list": true, "selector": ".genres a" }
  }
}
```

## PagesEndpoint (`pages`)

Three modes:

- **`simple`** - one request returns the final list directly:
  ```jsonc
  { "mode": "simple", "url": "{url}", "responseType": "html",
    "itemSelector": "div.reader img", "attr": "src" }
  ```
  `responseType` can also be `json` (`itemsPath` + optional `itemPath`),
  `regex_json` (a `regex` pulls an embedded JSON array out of an HTML/JS
  page - very common for sites that inline `var pages = [...]`), or
  `static` (inline `items`, for bundled/demo sources).

- **`compose`** - resolve a small JSON response into named variables, then
  build one URL per element of a loop variable. This is exactly what real
  APIs like MangaDex's "at-home" image server need:
  ```jsonc
  {
    "mode": "compose",
    "resolveUrl": "https://api.mangadex.org/at-home/server/{url}",
    "vars": { "baseUrl": "baseUrl", "hash": "chapter.hash", "files": "chapter.data" },
    "loopVar": "files",
    "urlTemplate": "{baseUrl}/data/{hash}/{item}"
  }
  ```

- **`echo`** - no request at all: the chapter/episode's own stored id/URL
  *is* the final playable URL (optionally reshaped via `urlTemplate`).
  Handy for anime sources whose episode list already links straight to a
  video file:
  ```jsonc
  { "mode": "echo" }
  ```

`resourceHeaders` (optional, any mode) adds headers (e.g. `Referer`) that
must be sent when the app actually downloads/plays each resulting URL.

## Worked, real examples

- `assets/extensions/mangadex.json` - a complete, working source against the
  public MangaDex API: JSON mode, relationship filtering, `compose` pages.
- `assets/extensions/demo_manga.json` / `demo_anime.json` - fully `static`/
  `echo` sources with zero network dependency, used to seed the app on
  first launch so there's always something to try.
- `docs/example-repo/` - a minimal repository index plus a single-file
  extension, for testing "Add repository" against your own fork/gist/CDN.

## Limitations (v1)

This is a declarative, no-code engine on purpose (keeps the app buildable
purely from CI with no native code per-site). It cannot execute JavaScript,
solve challenges (Cloudflare, etc.), or do multi-step logins. Sites that
require that are out of scope for now - a future version may add an
optional embedded JS engine for advanced sources.
