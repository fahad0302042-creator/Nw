"""HLS / m3u8 downloader.

Handles master playlists (variant selection), AES-128 encrypted segments,
byte-range segments and fMP4 init sections. Segments are fetched in parallel
into a temp directory and concatenated in order, so memory use stays flat
regardless of video length.

If ``ffmpeg`` is on PATH the result is remuxed to a clean .mp4 container;
otherwise the concatenated transport stream is kept as-is (playable in VLC,
mpv and most TV apps).
"""

from __future__ import annotations

import asyncio
import shutil
from pathlib import Path
from urllib.parse import urljoin

import httpx
import m3u8

try:  # optional - only needed for AES-128 encrypted streams
    from cryptography.hazmat.primitives.ciphers import Cipher, algorithms, modes

    _HAS_CRYPTO = True
except ImportError:  # pragma: no cover
    _HAS_CRYPTO = False


class HlsError(RuntimeError):
    pass


def _unpad(data: bytes) -> bytes:
    if not data:
        return data
    n = data[-1]
    if 1 <= n <= 16 and data[-n:] == bytes([n]) * n:
        return data[:-n]
    return data


def _decrypt(data: bytes, key: bytes, iv: bytes) -> bytes:
    if len(data) % 16:
        data += b"\x00" * (16 - len(data) % 16)
    decryptor = Cipher(algorithms.AES(key), modes.CBC(iv)).decryptor()
    return _unpad(decryptor.update(data) + decryptor.finalize())


def _iv_for(key, seq: int) -> bytes:
    """An explicit IV wins; otherwise the HLS default is the sequence number."""
    raw = getattr(key, "iv", None)
    if raw:
        raw = raw.lower()
        if raw.startswith("0x"):
            raw = raw[2:]
        try:
            return bytes.fromhex(raw)
        except ValueError:
            pass
    return seq.to_bytes(16, "big")


async def _get_bytes(
    client: httpx.AsyncClient,
    url: str,
    headers: dict[str, str],
    cookies: dict[str, str],
    retries: int,
    byte_range: str | None = None,
) -> bytes:
    last: Exception | None = None
    for attempt in range(retries + 1):
        try:
            h = dict(headers)
            if byte_range:
                h["Range"] = byte_range
            r = await client.get(url, headers=h, cookies=cookies, timeout=None)
            r.raise_for_status()
            return r.content
        except (httpx.HTTPError, httpx.StreamError) as exc:
            last = exc
            if attempt >= retries:
                break
            await asyncio.sleep(min(2 ** attempt, 8))
    raise HlsError(f"failed to fetch {url}: {last}")


def _select_variant(playlist: m3u8.M3U8, quality: str) -> m3u8.Playlist:
    variants = list(playlist.playlists or [])
    if not variants:
        raise HlsError("master playlist contains no variants")

    def height(v: m3u8.Playlist) -> int:
        res = getattr(v.stream_info, "resolution", None)
        return int(res[1]) if res and len(res) == 2 else 0

    if quality not in ("auto", "best", ""):
        wanted = int("".join(ch for ch in quality if ch.isdigit()) or 0)
        if wanted:
            exact = [v for v in variants if height(v) == wanted]
            if exact:
                return max(exact, key=lambda v: v.stream_info.bandwidth or 0)
            below = [v for v in variants if height(v) and height(v) <= wanted]
            if below:
                return max(below, key=height)

    def score(v: m3u8.Playlist) -> int:
        return v.stream_info.bandwidth or height(v) or 0

    ordered = sorted(variants, key=score)
    if quality in ("auto", "best", ""):
        return ordered[-1]
    return ordered[min(len(ordered) - 1, max(0, len(ordered) // 2))]


async def download_hls(
    *,
    client: httpx.AsyncClient,
    playlist_url: str,
    dest: Path,
    headers: dict[str, str] | None = None,
    cookies: dict[str, str] | None = None,
    quality: str = "auto",
    concurrency: int = 4,
    max_retries: int = 3,
    on_progress=None,
    on_status=None,
    cancel: asyncio.Event | None = None,
) -> Path:
    """Download an HLS playlist to ``dest`` (a .ts file unless remuxed)."""
    headers = dict(headers or {})
    cookies = dict(cookies or {})
    headers.setdefault("User-Agent", "Mozilla/5.0")
    headers.setdefault("Referer", playlist_url)

    if on_status:
        on_status("fetching playlist")

    text = (
        await _get_bytes(client, playlist_url, headers, cookies, max_retries)
    ).decode("utf-8", "replace")
    master = m3u8.loads(text, uri=playlist_url)

    media_uri = playlist_url
    if master.playlists:
        variant = _select_variant(master, quality)
        media_uri = urljoin(playlist_url, variant.uri)
        text = (
            await _get_bytes(client, media_uri, headers, cookies, max_retries)
        ).decode("utf-8", "replace")

    media = m3u8.loads(text, uri=media_uri)
    segments = list(media.segments or [])
    if not segments:
        raise HlsError("playlist contains no segments")

    if on_status:
        on_status(f"downloading {len(segments)} segments")

    tmpdir = Path(dest.parent) / f".{dest.name}.segs"
    if tmpdir.exists():
        shutil.rmtree(tmpdir, ignore_errors=True)
    tmpdir.mkdir(parents=True, exist_ok=True)

    sem = asyncio.Semaphore(max(1, concurrency))
    key_cache: dict[str, bytes] = {}
    key_lock = asyncio.Lock()

    # Precompute byte-ranges so concurrent fetches don't race on the offset.
    ranges: list[tuple[int, int] | None] = []
    running_offset = 0
    for seg in segments:
        br = getattr(seg, "byterange", None)
        if br and "@" in str(br):
            length, offset = str(br).split("@", 1)
            start, end = int(offset), int(offset) + int(length) - 1
            running_offset = end + 1
            ranges.append((start, end))
        elif br:
            length = int(str(br).split("@", 1)[0])
            start, end = running_offset, running_offset + length - 1
            running_offset = end + 1
            ranges.append((start, end))
        else:
            ranges.append(None)

    async def fetch_key(key) -> bytes | None:
        if not key or not getattr(key, "method", None):
            return None
        method = (key.method or "").upper()
        if method == "NONE":
            return None
        if method != "AES-128":
            raise HlsError(f"unsupported segment encryption: {method}")
        if not _HAS_CRYPTO:
            raise HlsError(
                "this stream is AES-128 encrypted - install the 'cryptography' "
                "package to download it"
            )
        key_uri = urljoin(media_uri, key.uri)
        async with key_lock:
            if key_uri not in key_cache:
                key_cache[key_uri] = await _get_bytes(
                    client, key_uri, headers, cookies, max_retries
                )
            return key_cache[key_uri]

    async def fetch_segment(idx: int, seg) -> None:
        if cancel and cancel.is_set():
            raise asyncio.CancelledError
        async with sem:
            seg_uri = urljoin(media_uri, seg.uri)
            rng = ranges[idx]
            raw = await _get_bytes(
                client,
                seg_uri,
                headers,
                cookies,
                max_retries,
                byte_range=f"bytes={rng[0]}-{rng[1]}" if rng else None,
            )

            key = await fetch_key(getattr(seg, "key", None))
            if key is not None:
                raw = _decrypt(raw, key[:16], _iv_for(seg.key, idx))

            (tmpdir / f"{idx:07d}.ts").write_bytes(raw)
            if on_progress:
                on_progress(len(raw))

    try:
        tasks = [asyncio.create_task(fetch_segment(i, s)) for i, s in enumerate(segments)]
        for coro in asyncio.as_completed(tasks):
            await coro
            if cancel and cancel.is_set():
                for t in tasks:
                    t.cancel()
                raise asyncio.CancelledError
    finally:
        if cancel and cancel.is_set():
            shutil.rmtree(tmpdir, ignore_errors=True)

    if on_status:
        on_status("merging")

    dest.parent.mkdir(parents=True, exist_ok=True)
    with open(dest, "wb") as out:
        init = getattr(media, "segments", None)
        # fMP4 streams need the init section written once, before the segments.
        first_init = getattr(segments[0], "init_section", None) if segments else None
        if first_init and getattr(first_init, "uri", None):
            init_uri = urljoin(media_uri, first_init.uri)
            out.write(await _get_bytes(client, init_uri, headers, cookies, max_retries))
        for idx in range(len(segments)):
            part = tmpdir / f"{idx:07d}.ts"
            if part.exists():
                out.write(part.read_bytes())

    shutil.rmtree(tmpdir, ignore_errors=True)
    return dest


def remux_with_ffmpeg(src: Path, dst: Path) -> bool:
    """Remux a transport stream to mp4. Returns False if ffmpeg is missing."""
    if not shutil.which("ffmpeg"):
        return False
    import subprocess

    try:
        subprocess.run(
            [
                "ffmpeg", "-y", "-loglevel", "error",
                "-i", str(src), "-c", "copy", "-movflags", "+faststart", str(dst),
            ],
            check=True,
            capture_output=True,
            timeout=3600,
        )
    except (subprocess.CalledProcessError, subprocess.TimeoutExpired):
        return False
    if dst.exists() and dst.stat().st_size > 0:
        src.unlink(missing_ok=True)
        return True
    return False
