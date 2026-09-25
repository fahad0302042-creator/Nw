from __future__ import annotations

from dataclasses import dataclass, field
from typing import Any


class ExtractorError(RuntimeError):
    """Raised when a link cannot be resolved into downloadable media."""


@dataclass
class MediaItem:
    """One downloadable file behind a share link."""

    fs_id: str = ""
    name: str = ""
    size: int = 0
    is_dir: bool = False
    is_video: bool = False
    direct_url: str | None = None   # progressive download (mp4 etc.)
    stream_url: str | None = None   # HLS/m3u8 playlist
    thumb: str | None = None
    raw: dict[str, Any] = field(default_factory=dict)

    def to_dict(self) -> dict[str, Any]:
        return {
            "fs_id": self.fs_id,
            "name": self.name,
            "size": self.size,
            "is_dir": self.is_dir,
            "is_video": self.is_video,
            "thumb": self.thumb,
            "has_direct": bool(self.direct_url),
            "has_stream": bool(self.stream_url),
            "stream_is_hls": bool(self.stream_url and ".m3u8" in self.stream_url),
        }


@dataclass
class LinkInfo:
    """Everything we learned about a share link."""

    url: str
    host: str = ""
    surl: str = ""
    title: str = ""
    items: list[MediaItem] = field(default_factory=list)
    cookies: dict[str, str] = field(default_factory=dict)
    headers: dict[str, str] = field(default_factory=dict)
    strategy: str = ""
    raw: dict[str, Any] = field(default_factory=dict)

    def to_dict(self) -> dict[str, Any]:
        return {
            "url": self.url,
            "host": self.host,
            "surl": self.surl,
            "title": self.title,
            "items": [i.to_dict() for i in self.items],
            "strategy": self.strategy,
        }
