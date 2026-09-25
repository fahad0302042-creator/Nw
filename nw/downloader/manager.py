"""Download job manager: inspect links, run transfers, track progress."""

from __future__ import annotations

import asyncio
import re
import time
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any

import httpx

from ..extractors.base import ExtractorError, LinkInfo
from .hls import HlsError, download_hls, remux_with_ffmpeg

_UNSAFE = re.compile(r'[\\/:*?"<>|\x00-\x1f]+')


def safe_name(name: str, fallback: str = "download") -> str:
    cleaned = _UNSAFE.sub("_", (name or "").strip()).strip(" .")
    return (cleaned[:180] or fallback)


def unique_path(path: Path) -> Path:
    if not path.exists():
        return path
    stem, suffix, parent = path.stem, path.suffix, path.parent
    for n in range(1, 1000):
        candidate = parent / f"{stem} ({n}){suffix}"
        if not candidate.exists():
            return candidate
    return path


@dataclass
class Job:
    id: str
    url: str
    item_index: int | None = None
    quality: str = "auto"

    name: str = ""
    size: int = 0
    done: int = 0
    speed: float = 0.0
    eta: float | None = None
    status: str = "queued"  # queued|inspecting|downloading|merging|done|error|cancelled
    error: str | None = None
    path: str | None = None
    kind: str = ""  # direct|hls
    created: float = field(default_factory=time.time)

    _task: asyncio.Task | None = None
    _cancel: asyncio.Event = field(default_factory=asyncio.Event)
    _last_t: float = field(default_factory=time.time)
    _last_bytes: int = 0

    def to_dict(self) -> dict[str, Any]:
        return {
            "id": self.id,
            "url": self.url,
            "name": self.name,
            "size": self.size,
            "done": self.done,
            "speed": round(self.speed, 1),
            "eta": round(self.eta) if self.eta is not None else None,
            "status": self.status,
            "error": self.error,
            "path": self.path,
            "kind": self.kind,
            "quality": self.quality,
            "percent": round(self.done * 100 / self.size, 1) if self.size else None,
            "created": self.created,
        }


class DownloadManager:
    def __init__(self, config, extractor) -> None:
        self.cfg = config
        self.extractor = extractor
        self.jobs: dict[str, Job] = {}
        self._seq = 0
        self._cache: dict[str, LinkInfo] = {}

    # ---------------------------------------------------------------- inspect
    async def inspect(self, url: str, quality: str = "auto", refresh: bool = False) -> LinkInfo:
        key = f"{url}|{quality}"
        if not refresh and key in self._cache:
            return self._cache[key]
        info = await asyncio.to_thread(self.extractor.inspect, url, quality)
        self._cache[key] = info
        return info

    async def diagnose(self, url: str) -> dict[str, Any]:
        return await asyncio.to_thread(self.extractor.diagnose, url)

    # ------------------------------------------------------------------ jobs
    def _new_id(self) -> str:
        self._seq += 1
        return f"{self._seq:04d}"

    def create(self, url: str, item_index: int | None = None, quality: str = "auto") -> Job:
        job = Job(id=self._new_id(), url=url, item_index=item_index, quality=quality)
        self.jobs[job.id] = job
        job._task = asyncio.create_task(self._run(job))
        return job

    def get(self, job_id: str) -> Job | None:
        return self.jobs.get(job_id)

    def list_jobs(self) -> list[dict[str, Any]]:
        order = {"downloading": 0, "inspecting": 1, "merging": 2, "queued": 3, "error": 4, "done": 5, "cancelled": 6}
        jobs = sorted(self.jobs.values(), key=lambda j: (order.get(j.status, 9), -j.created))
        return [j.to_dict() for j in jobs]

    def cancel(self, job_id: str) -> bool:
        job = self.jobs.get(job_id)
        if not job:
            return False
        job._cancel.set()
        if job._task and not job._task.done():
            job._task.cancel()
        if job.status not in ("done", "error"):
            job.status = "cancelled"
        return True

    # --------------------------------------------------------------- progress
    def _progress(self, job: Job):
        def cb(delta: int) -> None:
            if job._cancel.is_set():
                raise asyncio.CancelledError
            job.done += delta
            now = time.time()
            dt = now - job._last_t
            if dt >= 0.5:
                instant = (job.done - job._last_bytes) / dt
                job.speed = job.speed * 0.6 + instant * 0.4 if job.speed else instant
                job._last_t = now
                job._last_bytes = job.done
                if job.speed > 0 and job.size:
                    job.eta = max(0.0, (job.size - job.done) / job.speed)

        return cb

    # ------------------------------------------------------------------- run
    async def _run(self, job: Job) -> None:
        try:
            job.status = "inspecting"
            info = await self.inspect(job.url, job.quality)

            item = self._pick(info, job.item_index)
            job.name = item.name
            job.size = item.size

            headers = dict(info.headers or {})
            cookies = dict(info.cookies or {})

            if item.stream_url and job.quality != "direct":
                job.kind = "hls"
                await self._run_hls(job, item.stream_url, headers, cookies)
            elif item.direct_url:
                job.kind = "direct"
                await self._run_direct(job, item.direct_url, headers, cookies)
            else:
                raise ExtractorError("this item has no downloadable URL")

            job.status = "done"
        except asyncio.CancelledError:
            job.status = "cancelled"
        except (ExtractorError, HlsError, httpx.HTTPError) as exc:
            job.status = "error"
            job.error = f"{type(exc).__name__}: {exc}"
        except Exception as exc:  # noqa: BLE001 - surface anything unexpected
            job.status = "error"
            job.error = f"{type(exc).__name__}: {exc}"

    @staticmethod
    def _pick(info: LinkInfo, index: int | None):
        if not info.items:
            raise ExtractorError("no files found at this link")
        if index is not None:
            if index >= len(info.items):
                raise ExtractorError(f"item {index} does not exist")
            return info.items[index]
        videos = [i for i in info.items if i.is_video and not i.is_dir]
        pool = videos or [i for i in info.items if not i.is_dir]
        return max(pool or info.items, key=lambda i: i.size)

    async def _run_direct(
        self, job: Job, url: str, headers: dict[str, str], cookies: dict[str, str]
    ) -> None:
        job.status = "downloading"
        dest = unique_path(self.cfg.download_dir / safe_name(job.name or "download"))
        part = dest.with_name(dest.name + ".part")

        resume = part.stat().st_size if part.exists() else 0
        job.done = resume
        job._last_bytes = resume

        h = dict(headers)
        h.setdefault("User-Agent", self.cfg.user_agent)
        if resume:
            h["Range"] = f"bytes={resume}-"

        async with httpx.AsyncClient(
            follow_redirects=True, timeout=None, limits=httpx.Limits(max_connections=8)
        ) as client:
            r = None
            try:
                r = await client.send(
                    client.build_request("GET", url, headers=h, cookies=cookies),
                    stream=True,
                )
                if r.status_code == 416 and resume:
                    await r.aclose()
                    resume = 0
                    job.done = 0
                    part.unlink(missing_ok=True)
                    h.pop("Range", None)
                    r = await client.send(
                        client.build_request("GET", url, headers=h, cookies=cookies),
                        stream=True,
                    )
                r.raise_for_status()

                total = int(r.headers.get("content-length") or 0)
                crange = r.headers.get("content-range")
                if crange and "/" in crange:
                    try:
                        total = int(crange.rsplit("/", 1)[1])
                    except ValueError:
                        pass
                if total:
                    job.size = total

                ctype = r.headers.get("content-type", "")
                if "text/html" in ctype and total and total < 100_000:
                    body = (await r.aread())[:400]
                    raise ExtractorError(
                        "host returned an HTML page instead of the file "
                        f"(probably an expired token): {body[:200]!r}"
                    )

                cb = self._progress(job)
                part.parent.mkdir(parents=True, exist_ok=True)
                with open(part, "ab" if resume else "wb") as fh:
                    async for chunk in r.aiter_bytes(256 * 1024):
                        if job._cancel.is_set():
                            raise asyncio.CancelledError
                        fh.write(chunk)
                        cb(len(chunk))
            finally:
                if r is not None:
                    await r.aclose()

        part.rename(dest)
        job.path = str(dest)

    async def _run_hls(
        self, job: Job, url: str, headers: dict[str, str], cookies: dict[str, str]
    ) -> None:
        job.status = "downloading"
        base = safe_name(job.name or "video")
        out_ts = unique_path(self.cfg.download_dir / f"{base}.ts")

        def status_cb(text: str) -> None:
            if text == "merging":
                job.status = "merging"

        async with httpx.AsyncClient(
            follow_redirects=True, timeout=None, limits=httpx.Limits(max_connections=16)
        ) as client:
            await download_hls(
                client=client,
                playlist_url=url,
                dest=out_ts,
                headers=headers,
                cookies=cookies,
                quality=job.quality,
                concurrency=self.cfg.concurrency,
                max_retries=self.cfg.max_retries,
                on_progress=self._progress(job),
                on_status=status_cb,
                cancel=job._cancel,
            )

        if remux_with_ffmpeg(out_ts, out_ts.with_suffix(".mp4")):
            job.path = str(out_ts.with_suffix(".mp4"))
        else:
            job.path = str(out_ts)
        job.done = Path(job.path).stat().st_size
        job.size = job.done
