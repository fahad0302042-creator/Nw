# Writing Kuroyomi extensions

An extension is **plain JSON**. There is no scripting: you declare *where to request* and *how to
read the response*, and the app's engine does the rest. That keeps extensions safe, tiny and
editable straight from a phone.

## 1. The repository file

```json
{
  "name": "My repository",
  "sources": [
    { "...full source manifest..." }
  ]
}
```

Sources may also be referenced indirectly, which keeps the index small:

```json
{
  "name": "My repository",
  "sources": [
    { "name": "Example", "url": "sources/example.json" }
  ]
}
```

Relative `url`s resolve against the folder holding the index file. A bare JSON array of manifests
works too.

Add the repository in the app by pasting its **raw** url. These are all accepted:

```
https://raw.githubusercontent.com/user/repo/main/index.json
https://github.com/user/repo/blob/main/index.json      → rewritten to raw
https://example.com/myrepo                             → /index.json appended
```

## 2. The source manifest

```json
{
  "id": "example-en",
  "name": "Example",
  "type": "manga",
  "lang": "en",
  "version": "1.0.0",
  "nsfw": false,
  "baseUrl": "https://example.com",
  "parse": "html",
  "headers": { "Referer": "https://example.com/" },
  "endpoints": { }
}
```

| Field | Meaning |
| --- | --- |
| `id` | Unique, stable. Used as the install key and in the library. |
| `type` | `manga` (reader) or `anime` (video player). |
| `parse` | Default response format: `html`, `json` or `raw`. Overridable per endpoint. |
| `baseUrl` | Relative urls found while scraping are resolved against this. |
| `headers` | Sent with every request *and* with image/video loads (handy for `Referer`). |

### Endpoints

| Key | Purpose | Variables |
| --- | --- | --- |
| `popular` | Main listing | `{page}` |
| `latest` | Recently updated listing | `{page}` |
| `search` | Search results | `{query}`, `{rawQuery}`, `{page}` |
| `details` | Metadata for one entry | `{url}` |
| `chapters` / `episodes` | Chapter or episode list | `{url}` |
| `pages` / `images` | Image urls of one chapter | `{url}` |
| `video` / `videos` | Playable streams of one episode | `{url}` |

`episodes`, `images` and `videos` are aliases, so anime extensions can use natural wording.

### Endpoint object

```json
{
  "url": "/browse?page={page}",
  "method": "GET",
  "body": null,
  "parse": "html",
  "items": ".card",
  "next": "a.next-page",
  "reverse": false,
  "filter": false,
  "headers": { },
  "fields": {
    "title": "h3",
    "url": "a@href",
    "thumbnail": { "sel": "img", "attr": "data-src,src" }
  }
}
```

* `items` — CSS selector (html) or dotted path (json) selecting the list nodes.
* `next` — if it matches, another page exists. Omit to keep paging while results arrive.
* `reverse` — flip the chapter list (for sites that list oldest first).
* `filter` — filter results by the search query client-side (for static/json sources).
* `fields` may also be written inline, i.e. `"title": "h3"` directly on the endpoint.

### Field names the engine looks for

| Endpoint | Fields |
| --- | --- |
| `popular` / `latest` / `search` | `title`\*, `url`\*, `thumbnail`, `subtitle` |
| `details` | `title`, `description`, `author`, `artist`, `status`, `thumbnail`, `genres` |
| `chapters` | `name`\*, `url`\*, `date`, `scanlator` |
| `pages` | `image` (defaults to the node itself / its `src`) |
| `video` | `url`\*, `quality` |

\* required — entries missing them are skipped.

## 3. Rules

A rule says how to turn a node into a string.

```json
"h3 a"                                     // css selector, text content
"img@data-src"                             // css selector + attribute
"data.title"                               // json dotted path
{ "sel": "a", "attr": "href" }
{ "path": "cover.url", "prefix": "https://cdn.example" }
{ "regex": "\"chapterId\":(\\d+)", "group": 1 }
{ "value": "Ongoing" }                     // constant
```

| Key | Effect |
| --- | --- |
| `sel` | CSS selector relative to the current node. Omit to use the node itself. |
| `attr` | `text` (default), `html`, `outerHtml`, or an attribute. Comma separated = fallbacks. |
| `path` | Dotted json path; supports `a.b[0].c`. Empty means "this node". |
| `regex` + `group` | Applied to the extracted string. No match → field is empty. |
| `strip` | Regex whose matches are deleted. |
| `prefix` / `suffix` | Wrapped around the result. |
| `value` | Constant, ignores everything else. |

Urls are resolved against `baseUrl`, and JavaScript-escaped urls (`https:\/\/…`) are cleaned up
automatically.

## 4. Examples

### HTML manga source

```json
{
  "id": "example-en",
  "name": "Example",
  "type": "manga",
  "baseUrl": "https://example.com",
  "parse": "html",
  "endpoints": {
    "popular": {
      "url": "/popular?page={page}",
      "items": "div.series-card",
      "next": "a.next",
      "fields": {
        "title": "h3",
        "url": "a@href",
        "thumbnail": { "sel": "img", "attr": "data-src,src" }
      }
    },
    "search": {
      "url": "/search?q={query}&page={page}",
      "items": "div.series-card",
      "fields": { "title": "h3", "url": "a@href", "thumbnail": "img@src" }
    },
    "details": {
      "url": "{url}",
      "fields": {
        "description": "div.summary",
        "author": "span.author",
        "status": "span.status",
        "thumbnail": "div.cover img@src",
        "genres": "a.genre"
      }
    },
    "chapters": {
      "url": "{url}",
      "items": "li.chapter",
      "reverse": false,
      "fields": { "name": "a", "url": "a@href", "date": "span.date" }
    },
    "pages": {
      "url": "{url}",
      "items": "div.reader img",
      "fields": { "image": { "attr": "data-src,src" } }
    }
  }
}
```

### Pages hidden inside a script tag

```json
"pages": {
  "url": "{url}",
  "parse": "raw",
  "fields": {
    "image": { "regex": "\"(https:[^\"]+?\\.(?:jpg|png|webp))\"", "group": 1 }
  }
}
```

Every regex match becomes a page, in order.

### JSON anime source

```json
"video": {
  "url": "{url}",
  "parse": "json",
  "items": "data.sources",
  "fields": { "url": "file", "quality": "label" }
}
```

## 5. Testing your extension

1. Host the JSON anywhere raw (a GitHub repo works well, edits are possible from a phone browser).
2. Add the url in **Extensions**, install the source, open **Browse**.
3. If a screen is empty the app shows the failing url and status — usually a selector typo or a site
   that needs a `Referer` header.

The bundled [`example_repo/`](../example_repo) is a complete working reference for the JSON style.
