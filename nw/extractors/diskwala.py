"""Direct extractor for DiskWala / TeraBox-family share links.

How this works
--------------
A share URL is resolved in three steps:

1.  Fetch the share page with a browser User-Agent. The HTML embeds a short
    lived ``jsToken`` (plus sometimes ``sign``/``timestamp``/``shareid``/``uk``).
2.  Call the host's listing endpoint with that token to get the file list.
    Each entry carries a ``dlink`` (progressive download) and, for video, an
    HLS playlist can be built via the streaming endpoint.
3.  Hand the resulting URLs to the downloader together with the session
    cookies, which the host usually requires on the media request.

Step 2 is the part that differs between hosts and changes over time, so
``inspect()`` tries several known strategies in order and records which one
worked. If every strategy fails, run ``diagnose()`` (or the Inspect -> Raw
button in the UI) and the dump will show exactly what came back so the
patterns can be updated without guessing.
"""

from __future__ import annotations

import re
from typing import Any
from urllib.parse import parse_qs, urlencode, urljoin, urlparse

import httpx

from .base import ExtractorError, LinkInfo, MediaItem

# Patterns used to pull session values out of the share-page HTML.
TOKEN_PATTERNS: dict[str, tuple[str, ...]] = {
    "jsToken": (
        r'"jsToken"\s*:\s*"([^"]+)"',
        r"jsToken\s*[:=]\s*['\"]([^'\"]{8,})['\"]",
        r"window\.jsToken\s*=\s*['\"]([^'\"]+)['\"]",
        r'name="jsToken"\s+value="([^"]+)"',
    ),
    "sign": (
        r'"sign"\s*:\s*"([^"]+)"',
        r"sign\s*[:=]\s*['\"]([^'\"]{8,})['\"]",
    ),
    "timestamp": (
        r'"timestamp"\s*:\s*"?(\d{9,})"?',
        r"timestamp\s*[:=]\s*['\"]?(\d{9,})",
    ),
    "shareid": (
        r'"shareid"\s*:\s*"?(\d+)"?',
        r"shareid\s*[:=]\s*['\"]?(\d+)",
    ),
    "uk": (
        r'"uk"\s*:\s*"?(\d+)"?',
        r'"uk"\s*:\s*"([^"]+)"',
    ),
    "bdstoken": (r'"bdstoken"\s*:\s*"([^"]+)"',),
    "surl": (r'"shorturl"\s*:\s*"([^"]+)"', r'"surl"\s*:\s*"([^"]+)"'),
    "app_id": (r'"app_id"\s*:\s*"?(\d+)"?',),
}

# Fallback: some pages render the media URLs straight into the HTML.
M3U8_SCAN = re.compile(r"https?://[^\"'\\\s]+?\.m3u8[^\"'\\\s]*")
DLINK_SCAN = re.compile(r'"dlink"\s*:\s*"([^"]+)"')

VIDEO_EXT = (".mp4", ".mkv", ".webm", ".mov", ".m4v", ".avi", ".flv", ".ts")


class DiskwalaExtractor:
    """Resolve share links by talking to the host directly."""

    name = "direct"

    def __init__(self, config) -> None:
        self.cfg = config

    # ------------------------------------------------------------------ utils
    def _headers(self, referer: str | None = None) -> dict[str, str]:
        h = {
            "User-Agent": self.cfg.user_agent,
            "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
            "Accept-Language": "en-US,en;q=0.9",
        }
        if referer:
            h["Referer"] = referer
        return h

    def _client(self) -> httpx.Client:
        return httpx.Client(
            follow_redirects=True,
            timeout=self.cfg.timeout,
            headers=self._headers(),
        )

    def check_host(self, url: str) -> str:
        """Validate a URL against the allowlist and return its lowercase host."""
        host = (urlparse(url).hostname or "").lower()
        if not host:
            raise ExtractorError(f"Could not parse a hostname out of {url!r}")
        if host not in self.cfg.allowed_hosts:
            raise ExtractorError(
                f"Host {host!r} is not in the allowlist. Add it with the "
                "NW_ALLOWED_HOSTS environment variable if you trust it."
            )
        return host

    def normalize(self, url: str) -> tuple[str, str]:
        """Return (host, surl) for a share URL."""
        host = self.check_host(url)
        parsed = urlparse(url)

        qs = parse_qs(parsed.query)
        for key in ("surl", "shorturl", "s"):
            if qs.get(key):
                return host, qs[key][0]

        parts = [p for p in parsed.path.split("/") if p]
        # /s/<id>  /share/<id>  /sharing/link/<id>  /video/<id>  /f/<id>
        if len(parts) >= 2 and parts[0] in {"s", "share", "sharing", "video", "f", "d"}:
            return host, parts[-1]
        if parts:
            return host, parts[-1]
        raise ExtractorError(f"Could not find a share id in {url!r}")

    @staticmethod
    def _extract_tokens(html: str) -> dict[str, str]:
        found: dict[str, str] = {}
        for key, patterns in TOKEN_PATTERNS.items():
            for pattern in patterns:
                m = re.search(pattern, html)
                if m:
                    found[key] = m.group(1)
                    break
        return found

    @staticmethod
    def _abs(url: str, base: str) -> str:
        return urljoin(base, url)

    # ------------------------------------------------------------------- page
    def fetch_page(self, url: str) -> tuple[str, dict[str, str], str, int]:
        """GET the share page. Returns (html, cookies, final_url, status)."""
        with self._client() as client:
            r = client.get(url, headers=self._headers())
            return r.text, dict(client.cookies), str(r.url), r.status_code

    # --------------------------------------------------------------- listing
    def _listing_params(self, host: str, surl: str, tokens: dict[str, str], **extra) -> dict[str, str]:
        params: dict[str, str] = {
            "app_id": tokens.get("app_id", self.cfg.app_id),
            "web": "1",
            "channel": "0",
            "clienttype": self.cfg.clienttype,
            "jsToken": tokens.get("jsToken", ""),
            "shorturl": surl,
            "root": "1",
            "page": "1",
            "num": "100",
            "order": "other",
            "by": "name",
        }
        if tokens.get("sign"):
            params["sign"] = tokens["sign"]
        if tokens.get("timestamp"):
            params["timestamp"] = tokens["timestamp"]
        params.update(extra)
        return {k: v for k, v in params.items() if v != ""}

    def _try_listing(
        self,
        client: httpx.Client,
        base: str,
        path: str,
        params: dict[str, str],
        referer: str,
    ) -> dict[str, Any] | None:
        url = f"{base}{path}?{urlencode(params)}"
        try:
            r = client.get(url, headers=self._headers(referer))
        except httpx.HTTPError:
            return None
        if r.status_code != 200:
            return None
        try:
            data = r.json()
        except ValueError:
            return None
        if isinstance(data, dict) and (data.get("list") or data.get("data")):
            return data
        return None

    @staticmethod
    def _items_from_payload(payload: dict[str, Any], base: str) -> list[MediaItem]:
        raw_list = payload.get("list")
        if raw_list is None:
            data = payload.get("data")
            if isinstance(data, dict):
                raw_list = data.get("list") or data.get("file_list")
            elif isinstance(data, list):
                raw_list = data
        if not raw_list:
            return []

        items: list[MediaItem] = []
        for entry in raw_list:
            if not isinstance(entry, dict):
                continue
            name = entry.get("server_filename") or entry.get("filename") or "file"
            dlink = entry.get("dlink") or entry.get("download_link") or ""
            if dlink and not dlink.startswith("http"):
                dlink = urljoin(base, dlink)

            thumbs = entry.get("thumbs") or {}
            thumb = None
            if isinstance(thumbs, dict):
                thumb = thumbs.get("url3") or thumbs.get("url2") or thumbs.get("url1")
            if thumb and not str(thumb).startswith("http"):
                thumb = urljoin(base, str(thumb))

            category = entry.get("category")
            is_dir = bool(entry.get("isdir"))
            is_video = (not is_dir) and (
                category == 1 or str(name).lower().endswith(VIDEO_EXT)
            )

            items.append(
                MediaItem(
                    fs_id=str(entry.get("fs_id") or ""),
                    name=str(name),
                    size=int(entry.get("size") or 0),
                    is_dir=is_dir,
                    is_video=is_video,
                    direct_url=dlink or None,
                    thumb=thumb,
                    raw=entry,
                )
            )
        return items

    def _attach_streams(
        self, items: list[MediaItem], host: str, tokens: dict[str, str], quality: str = "auto"
    ) -> None:
        """Add HLS playlist URLs to video items that do not already have one."""
        shareid = tokens.get("shareid", "")
        uk = tokens.get("uk", "")
        jstoken = tokens.get("jsToken", "")
        if not (shareid and uk and jstoken):
            return
        for item in items:
            if not item.is_video or item.stream_url:
                continue
            params = {
                "type": f"M3U8_AUTO_{quality}",
                "file_id": item.fs_id,
                "uk": uk,
                "shareid": shareid,
                "jsToken": jstoken,
                "app_id": tokens.get("app_id", self.cfg.app_id),
                "clienttype": self.cfg.clienttype,
            }
            item.stream_url = (
                f"https://{host}/share/streaming?{urlencode(params)}"
            )

    # ----------------------------------------------------------------- public
    def inspect(self, url: str, quality: str = "auto") -> LinkInfo:
        host, surl = self.normalize(url)
        base = f"https://{host}"
        page_url = f"{base}/sharing/link?surl={surl}" if surl else url

        with self._client() as client:
            r = client.get(page_url, headers=self._headers())
            html, final_url, status = r.text, str(r.url), r.status_code
            cookies = dict(client.cookies)

            info = LinkInfo(
                url=url,
                host=host,
                surl=surl,
                cookies=cookies,
                headers={"User-Agent": self.cfg.user_agent, "Referer": final_url},
            )
            info.raw["page_url"] = page_url
            info.raw["final_url"] = final_url
            info.raw["page_status"] = status
            info.raw["html_len"] = len(html)

            title = re.search(r"<title>(.*?)</title>", html, re.S | re.I)
            if title:
                info.title = title.group(1).strip()[:200]

            tokens = self._extract_tokens(html)
            tokens.setdefault("surl", surl)
            info.raw["tokens"] = {
                k: (v[:12] + "..." if len(v) > 24 else v) for k, v in tokens.items()
            }

            # --- Strategy 1/2: the two common listing endpoints ---------------
            payload = None
            for path in ("/share/list", "/api/shorturlinfo"):
                payload = self._try_listing(
                    client=client,
                    base=base,
                    path=path,
                    params=self._listing_params(host, surl, tokens),
                    referer=final_url,
                )
                if payload:
                    info.strategy = f"listing:{path}"
                    info.raw["listing_path"] = path
                    break
                payload = self._try_listing(
                    client=client,
                    base=base,
                    path=path,
                    params=self._listing_params(host, surl, tokens, surl=surl),
                    referer=final_url,
                )
                if payload:
                    info.strategy = f"listing:{path}(surl)"
                    info.raw["listing_path"] = path
                    break

        items: list[MediaItem] = []
        if payload:
            info.raw["errno"] = payload.get("errno")
            items = self._items_from_payload(payload, base)

        # --- Strategy 3: scrape what the page already rendered ----------------
        if not items:
            for m in DLINK_SCAN.finditer(html):
                dlink = m.group(1).replace("\\/", "/")
                items.append(
                    MediaItem(
                        name=info.title or "file",
                        direct_url=urljoin(base, dlink),
                        is_video=True,
                    )
                )
            for m in M3U8_SCAN.finditer(html):
                items.append(
                    MediaItem(
                        name=info.title or "video",
                        stream_url=m.group(0).replace("\\/", "/"),
                        is_video=True,
                    )
                )
            if items:
                info.strategy = "page-scan"

        if not items:
            raise ExtractorError(
                "Could not resolve any files from this link. The host's page "
                "structure has probably changed - open the Raw diagnostics "
                "panel to see what came back."
            )

        self._attach_streams(items, host, tokens, quality)
        info.items = items
        return info

    # ------------------------------------------------------------- diagnostics
    def diagnose(self, url: str) -> dict[str, Any]:
        """Return a raw dump of every step. Used to repair the patterns."""
        out: dict[str, Any] = {"input": url, "steps": []}
        try:
            host, surl = self.normalize(url)
        except ExtractorError as exc:
            out["error"] = str(exc)
            return out

        base = f"https://{host}"
        out["host"] = host
        out["surl"] = surl
        page_url = f"{base}/sharing/link?surl={surl}"
        out["page_url"] = page_url

        try:
            with self._client() as client:
                r = client.get(page_url, headers=self._headers())
                out["steps"].append(
                    {
                        "step": "GET share page",
                        "status": r.status_code,
                        "final_url": str(r.url),
                        "cookies": dict(client.cookies),
                        "content_type": r.headers.get("content-type"),
                        "length": len(r.text),
                    }
                )
                html = r.text

                tokens = self._extract_tokens(html)
                out["tokens"] = tokens

                for path in ("/share/list", "/api/shorturlinfo"):
                    params = self._listing_params(host, surl, tokens)
                    probe = f"{base}{path}?{urlencode(params)}"
                    try:
                        pr = client.get(probe, headers=self._headers(str(r.url)))
                        body = pr.text
                        out["steps"].append(
                            {
                                "step": f"GET {path}",
                                "url": probe,
                                "status": pr.status_code,
                                "content_type": pr.headers.get("content-type"),
                                "body_head": body[:1500],
                            }
                        )
                    except httpx.HTTPError as exc:
                        out["steps"].append({"step": f"GET {path}", "error": str(exc)})

                out["regex_findings"] = {
                    "m3u8": list(dict.fromkeys(M3U8_SCAN.findall(html)))[:10],
                    "dlink": list(dict.fromkeys(DLINK_SCAN.findall(html)))[:10],
                }
                snippet = html[:6000]
        except httpx.HTTPError as exc:
            out["error"] = f"network: {exc}"
            return out

        out["html_snippet"] = snippet
        return out
