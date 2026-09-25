"""Extractor that delegates to a third-party extraction API.

Enable by setting ``NW_API_URL`` (and ``NW_API_KEY`` if your provider needs
one). The key never leaves the server - the browser only ever sees the
resulting media URLs.
"""

from __future__ import annotations

from typing import Any

import httpx

from .base import ExtractorError, LinkInfo, MediaItem

VIDEO_EXT = (".mp4", ".mkv", ".webm", ".mov", ".m4v", ".avi", ".flv", ".ts")


class ProviderExtractor:
    name = "provider"

    def __init__(self, config) -> None:
        self.cfg = config

    def _headers(self) -> dict[str, str]:
        h = {"User-Agent": self.cfg.user_agent, "Accept": "application/json"}
        header = (self.cfg.api_auth_header or "").strip()
        if header and self.cfg.api_key:
            prefix = (self.cfg.api_auth_prefix or "").strip()
            h[header] = f"{prefix} {self.cfg.api_key}".strip()
        return h

    def _call(self, url: str) -> Any:
        with httpx.Client(follow_redirects=True, timeout=self.cfg.timeout) as client:
            if self.cfg.api_method == "GET":
                r = client.get(self.cfg.api_url, params={"url": url}, headers=self._headers())
            else:
                r = client.post(
                    self.cfg.api_url, json={"url": url}, headers=self._headers()
                )
            if r.status_code >= 400:
                raise ExtractorError(
                    f"Extraction API returned HTTP {r.status_code}: {r.text[:300]}"
                )
            try:
                return r.json()
            except ValueError as exc:
                raise ExtractorError(f"Extraction API returned non-JSON: {r.text[:300]}") from exc

    @staticmethod
    def _coerce(items: Any) -> list[MediaItem]:
        out: list[MediaItem] = []
        if isinstance(items, dict):
            items = [items]
        for entry in items or []:
            if not isinstance(entry, dict):
                continue
            name = entry.get("name") or entry.get("filename") or entry.get("title") or "file"
            direct = entry.get("url") or entry.get("download_url") or entry.get("dlink")
            stream = entry.get("stream_url") or entry.get("hls") or entry.get("m3u8")
            if isinstance(stream, list):
                stream = stream[0] if stream else None
            if isinstance(stream, dict):
                stream = stream.get("url")
            out.append(
                MediaItem(
                    fs_id=str(entry.get("file_id") or entry.get("fs_id") or ""),
                    name=str(name),
                    size=int(entry.get("size") or 0),
                    direct_url=direct or None,
                    stream_url=stream or None,
                    thumb=entry.get("thumbnail") or entry.get("thumb"),
                    is_video=str(name).lower().endswith(VIDEO_EXT) or bool(stream),
                    raw=entry,
                )
            )
        return out

    def inspect(self, url: str, quality: str = "auto") -> LinkInfo:
        data = self._call(url)
        items = self._coerce(data.get("files") or data.get("items") or data.get("list") or data)
        if not items:
            raise ExtractorError(f"Extraction API returned no files. Response: {str(data)[:400]}")
        return LinkInfo(
            url=url,
            title=str(data.get("title") or ""),
            items=items,
            strategy="provider",
            raw={"response_keys": list(data)[:20] if isinstance(data, dict) else []},
            headers={"User-Agent": self.cfg.user_agent},
        )

    def diagnose(self, url: str) -> dict[str, Any]:
        try:
            data = self._call(url)
        except ExtractorError as exc:
            return {"input": url, "error": str(exc)}
        text = str(data)
        return {
            "input": url,
            "api_url": self.cfg.api_url,
            "status": "ok",
            "response_head": text[:2000],
        }
