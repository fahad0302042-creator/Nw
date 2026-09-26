# Writing a Kurayomi extension

An extension is **one JavaScript file**. It runs in an isolated QuickJS
runtime with a small standard library injected by the app. No build step, no
bundler, no npm — just a file you can serve over HTTP.

If you have written a Tachiyomi/Aniyomi extension before, the shape will be
immediately familiar; the method names are intentionally the same ideas.

---

## 1. The minimum

```js
class MySource {
  constructor() {
    this.id      = 'en.mysite';        // globally unique, stable forever
    this.name    = 'MySite';
    this.lang    = 'en';
    this.baseUrl = 'https://mysite.example';
    this.type    = 'manga';            // 'manga' | 'anime'
    this.supportsLatest = true;        // hides the "Latest" tab when false
  }

  async popular(page) { /* → MediaPage */ }
  async latest(page)  { /* → MediaPage */ }
  async search(query, page, filters) { /* → MediaPage */ }
  async details(item) { /* → MediaItem */ }

  // manga
  async chapters(item)   { /* → Chapter[] */ }
  async pages(chapter)   { /* → (string | Page)[] */ }

  // anime
  async episodes(item)   { /* → Episode[] */ }
  async videos(episode)  { /* → Video[] */ }
}

registerSource(new MySource());
```

One file may register **several** sources — useful for one site in many
languages:

```js
['en', 'es', 'fr'].forEach(lang => registerSource(new MySource(lang)));
```

> **Everything that touches the host is asynchronous.** `select`, `absUrl`,
> `http.*` and `utils.*` all return Promises. Always `await`.

---

## 2. Return shapes

### MediaPage
```js
{ items: MediaItem[], hasNext: boolean }
```
A bare array is also accepted and treated as `hasNext: false`.

### MediaItem
```js
{
  url: '/series/one-piece',   // required — identity, relative or absolute
  title: 'One Piece',         // required
  thumbnailUrl: 'https://…',
  author: '…', artist: '…',
  description: '…',
  genres: ['Action', 'Adventure'],
  status: 'ongoing'           // ongoing|completed|licensed|hiatus|cancelled
}
```
Listing endpoints only need `url`, `title`, `thumbnailUrl`. The rest is
filled in by `details()`.

### Chapter / Episode
```js
{
  url: '/series/one-piece/1100',  // required
  name: 'Chapter 1100',           // required
  number: 1100,                   // used for sorting — supply it if you can
  scanlator: 'TCB Scans',
  dateUpload: 1711929600000       // epoch ms
}
```
Return them **newest first**.

### Page (manga)
A plain URL string, or an object when the CDN needs headers:
```js
['https://cdn/1.jpg', { url: 'https://cdn/2.jpg', headers: { Referer: '…' } }]
```

### Video (anime)
```js
{
  url: 'https://cdn/master.m3u8',      // HLS or progressive MP4
  quality: '1080p',
  headers: { Referer: 'https://mysite.example/' },
  subtitles: [{ url: 'https://…/en.vtt', label: 'English' }]
}
```
Return them **best quality first**; the player uses `[0]` by default.

---

## 3. The standard library

### `http`
```js
const res = await http.get(url, { headers: { Referer: base } });
res.status; res.url; res.headers; res.body;   // body is always a string

await http.post(url, { form: { q: 'naruto', page: 1 } });  // urlencoded
await http.post(url, { headers: {'Content-Type':'application/json'},
                       body: JSON.stringify({ q: 'naruto' }) });

const doc  = await http.getDoc(url);    // fetch + parse in one step
const json = await http.getJson(url);
```
A `fetch()` shim is also provided so lightly-ported code tends to work.
Non-2xx responses throw unless you pass `{ allowError: true }`.

### `dom` — jsoup-flavoured HTML querying
```js
const doc = await dom.parse(html, baseUrl);

const els = await doc.select('div.card');       // Element[]
const el  = await doc.selectFirst('h1.title');  // Element | null

el.text          // trimmed text content
el.html          // innerHTML
el.outerHtml
el.attr('href')  // string | null
await el.absUrl('href')        // resolved against the document base URL
await el.select('img')         // scoped query, relative to this element
await el.selectFirst('img')
```
Selection happens on the Dart side against the real parsed DOM, so full CSS
selector support is available and nothing large crosses the bridge.

### `utils`
```js
await utils.absolute(base, '/relative/path');
await utils.sleep(500);                       // be polite, avoid rate limits
await utils.store.set('token', 'abc');        // persisted, scoped to your extension
const token = await utils.store.get('token'); // survives restarts
utils.parseDate('2024-04-01');                // → epoch ms | null
```

### `console`
`console.log/warn/error` are forwarded to the host log.

---

## 4. Filters (optional)

```js
async getFilters() {
  return [
    { key: 'genre', name: 'Genre', type: 'select',
      options: [ { label: 'Any', value: '' }, { label: 'Action', value: 'action' } ] },
    { key: 'status', name: 'Completed only', type: 'checkbox' },
    { key: 'sort',   name: 'Sort by', type: 'sort', options: ['Popular','Latest'] },
    { key: 'tags',   name: 'Tags', type: 'group', filters: [
        { key: 'isekai', name: 'Isekai', type: 'tristate' } ] }
  ];
}
```

The app renders the UI and passes the user's choices to `search()`:

```js
async search(query, page, filters) {
  const genre = (filters.find(f => f.key === 'genre') || {}).value || '';
  // …
}
```

Types: `text`, `select`, `checkbox`, `tristate`, `sort`, `group`.

---

## 5. Publishing a repository

A repository is a URL to an `index.json`. Relative `code`/`icon` paths resolve
against it, so a GitHub Pages folder or a `raw.githubusercontent.com` path is
enough.

```json
{
  "name": "My Repo",
  "extensions": [
    {
      "id": "en.mysite",
      "name": "MySite",
      "version": "1.0.0",
      "lang": "en",
      "type": "manga",
      "code": "src/en.mysite/index.js",
      "icon": "src/en.mysite/icon.png",
      "nsfw": false,
      "description": "Optional."
    }
  ]
}
```

Bump `version` to push an update — the app compares versions numerically and
surfaces an **Updates** section.

---

## 6. Developing locally

```bash
cd extensions_repo
python3 -m http.server 8080
```

Add `http://10.0.2.2:8080/index.json` (Android emulator) or your LAN IP
(physical device) as a repository. Bump the version and hit **Update** to
reload after each edit.

Check your file parses before installing:

```bash
node --check src/en.mysite/index.js
```

---

## 7. Practical notes

* **Referer is the usual culprit.** Most image CDNs and video hosts reject
  requests without it. The app automatically sends `Referer: <baseUrl>/` for
  covers, pages and streams; override per-item with `headers` when needed.
* **`url` is identity.** Read state, library membership and history are keyed
  on `(sourceId, url)`. Keep it stable and canonical — strip query noise.
* **Cloudflare / JS challenges** cannot currently be solved; a WebView-backed
  challenge solver is planned.
* **Be gentle.** `utils.sleep()` between requests in loops. Getting an IP
  banned is the fastest way to a broken extension.
* **One runtime per extension.** Globals you define are yours alone, and a
  crash in your extension cannot affect another.
