# Nw

A personal downloader for DiskWala (and TeraBox-family) share links.

Paste a link, inspect what's behind it, pick a file, and save it to disk. HLS
streams are fetched in parallel and concatenated; progressive files resume if
interrupted.

**Only download content you have the rights to.** Creators on DiskWala are paid
per view — bypassing the official app to grab other people's films or dramas
is copyright infringement. Use this for your own uploads, licensed material,
or personal backups.

## Run on Android (Acode + Termux)

Acode is an editor — it cannot run this Python server by itself. Install
**Termux** from F-Droid (not Play Store), then:

```bash
pkg update
pkg install python git
git clone -b arena/01a0d6a6-nw https://github.com/fahad0302042-creator/Nw.git
cd Nw
pip install starlette uvicorn httpx m3u8 python-dotenv
python run.py
```

On the same phone, open Chrome and go to **http://127.0.0.1:8000**

In Acode: **Git → Clone** that same URL, checkout branch `arena/01a0d6a6-nw`,
and edit files there. Still start the app with `python run.py` inside Termux.

## Run

Python 3.10+.

```bash
python3 -m venv .venv
source .venv/bin/activate          # Windows: .venv\Scripts\activate
pip install -r requirements.txt
python run.py                      # http://127.0.0.1:8000
```

Or:

```bash
python -m nw serve --port 8000
python -m nw diagnose "https://diskwala.com/s/xxxxxxxx"
```

The UI is a single page: paste a link → Inspect → Download. Finished files land
in `~/Downloads/Nw` (or `./downloads` if that folder doesn't exist). Use
**Save to device** in the UI to pull a finished file into your browser's
download folder.

## How extraction works

DiskWala share pages are JS-rendered and hand out short-lived tokens. The
built-in extractor:

1. Fetches the share page with a browser User-Agent
2. Pulls `jsToken` / `sign` / `shareid` out of the HTML
3. Hits the listing endpoint for the file list (`dlink` + optional HLS)
4. Downloads with the session cookies the host usually requires

If DiskWala changes their page, click **Dump raw response** in the UI (or run
`python -m nw diagnose URL`) and use the dump to update the patterns in
`nw/extractors/diskwala.py`.

### Optional: third-party extraction API

If you already have a key for an extraction API, put it in `.env` (see
`.env.example`). The key stays on the server and is never sent to the browser.

```
NW_API_URL=https://your-provider.example/api/v1/diskwala/extract
NW_API_KEY=...
```

## Config

| Variable | Default | Meaning |
|---|---|---|
| `NW_DOWNLOAD_DIR` | `~/Downloads/Nw` | Where files are written |
| `NW_HOST` / `NW_PORT` | `0.0.0.0` / `8000` | Bind address |
| `NW_CONCURRENCY` | `4` | Parallel HLS segments |
| `NW_ALLOWED_HOSTS` | DiskWala + TeraBox family | Extra hosts, comma-separated |

Copy `.env.example` to `.env` to set them.

Install `ffmpeg` if you want HLS streams remuxed to `.mp4`. Without it, the
concatenated `.ts` is still playable in VLC / mpv.

## Tests

```bash
python -m unittest discover -s tests -v
```
