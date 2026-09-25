"""Starlette app: serves the UI and drives the download manager.

Starlette (not FastAPI) so Termux / Python 3.14 can install from wheels
without compiling pydantic-core or cryptography.
"""

from __future__ import annotations

import asyncio
import json
import shutil
from pathlib import Path

from starlette.applications import Starlette
from starlette.middleware import Middleware
from starlette.middleware.base import BaseHTTPMiddleware
from starlette.middleware.cors import CORSMiddleware
from starlette.requests import Request
from starlette.responses import FileResponse, JSONResponse, StreamingResponse
from starlette.routing import Route

from .config import load_config
from .extractors import get_extractor
from .extractors.base import ExtractorError
from .downloader import DownloadManager

WEB_DIR = Path(__file__).resolve().parent.parent / "web"

cfg = load_config()
extractor = get_extractor(cfg)
manager = DownloadManager(cfg, extractor)


class PreviewMiddleware(BaseHTTPMiddleware):
    async def dispatch(self, request, call_next):
        response = await call_next(request)
        response.headers["Content-Security-Policy"] = "frame-ancestors *"
        if "x-frame-options" in response.headers:
            del response.headers["x-frame-options"]
        return response


async def _json_body(request: Request) -> dict:
    try:
        data = await request.json()
    except Exception:
        return {}
    return data if isinstance(data, dict) else {}


def _file(path: Path, media: str | None = None) -> FileResponse:
    kwargs = {}
    if media:
        kwargs["media_type"] = media
    return FileResponse(path, **kwargs)


async def index(request: Request) -> FileResponse:
    return _file(WEB_DIR / "index.html")


async def app_js(request: Request) -> FileResponse:
    return _file(WEB_DIR / "app.js", "application/javascript")


async def styles_css(request: Request) -> FileResponse:
    return _file(WEB_DIR / "styles.css", "text/css")


async def health(request: Request) -> JSONResponse:
    return JSONResponse({"ok": True})


async def api_config(request: Request) -> JSONResponse:
    return JSONResponse(
        {
            "download_dir": str(cfg.download_dir),
            "extractor": extractor.name,
            "has_ffmpeg": bool(shutil.which("ffmpeg")),
            "concurrency": cfg.concurrency,
            "allowed_hosts": list(cfg.allowed_hosts),
        }
    )


async def api_inspect(request: Request) -> JSONResponse:
    body = await _json_body(request)
    url = str(body.get("url") or "").strip()
    quality = str(body.get("quality") or "auto")
    refresh = bool(body.get("refresh"))
    if len(url) < 4:
        return JSONResponse({"ok": False, "error": "paste a link first"}, status_code=422)
    try:
        info = await manager.inspect(url, quality, refresh)
    except ExtractorError as exc:
        return JSONResponse({"ok": False, "error": str(exc)}, status_code=422)
    except Exception as exc:  # noqa: BLE001
        return JSONResponse(
            {"ok": False, "error": f"{type(exc).__name__}: {exc}"}, status_code=500
        )
    return JSONResponse({"ok": True, **info.to_dict()})


async def api_diagnose(request: Request) -> JSONResponse:
    body = await _json_body(request)
    url = str(body.get("url") or "").strip()
    if len(url) < 4:
        return JSONResponse({"ok": False, "error": "paste a link first"}, status_code=422)
    try:
        data = await manager.diagnose(url)
    except Exception as exc:  # noqa: BLE001
        return JSONResponse(
            {"ok": False, "error": f"{type(exc).__name__}: {exc}"}, status_code=500
        )
    return JSONResponse({"ok": True, "dump": data})


async def api_download(request: Request) -> JSONResponse:
    body = await _json_body(request)
    url = str(body.get("url") or "").strip()
    if len(url) < 4:
        return JSONResponse({"ok": False, "error": "paste a link first"}, status_code=422)
    item_index = body.get("item_index")
    if item_index is not None:
        try:
            item_index = int(item_index)
        except (TypeError, ValueError):
            item_index = None
    quality = str(body.get("quality") or "auto")
    job = manager.create(url, item_index, quality)
    return JSONResponse({"ok": True, "job": job.to_dict()})


async def api_jobs(request: Request) -> JSONResponse:
    return JSONResponse({"jobs": manager.list_jobs()})


async def api_events(request: Request) -> StreamingResponse:
    async def gen():
        last = ""
        while True:
            payload = json.dumps({"jobs": manager.list_jobs()})
            if payload != last:
                yield f"data: {payload}\n\n"
                last = payload
            await asyncio.sleep(0.5)

    return StreamingResponse(
        gen(),
        media_type="text/event-stream",
        headers={"Cache-Control": "no-cache", "X-Accel-Buffering": "no"},
    )


async def api_cancel(request: Request) -> JSONResponse:
    job_id = request.path_params["job_id"]
    if not manager.cancel(job_id):
        return JSONResponse({"ok": False, "error": "job not found"}, status_code=404)
    return JSONResponse({"ok": True})


async def api_delete(request: Request) -> JSONResponse:
    job_id = request.path_params["job_id"]
    job = manager.jobs.pop(job_id, None)
    if not job:
        return JSONResponse({"ok": False, "error": "job not found"}, status_code=404)
    manager.cancel(job_id)
    return JSONResponse({"ok": True})


async def api_file(request: Request) -> FileResponse | JSONResponse:
    job_id = request.path_params["job_id"]
    job = manager.get(job_id)
    if not job or not job.path or job.status != "done":
        return JSONResponse(
            {"ok": False, "error": "no finished file for this job"}, status_code=404
        )

    path = Path(job.path).resolve()
    root = cfg.download_dir.resolve()
    if root != path.parent and root not in path.parents:
        return JSONResponse(
            {"ok": False, "error": "refusing to serve a file outside the download folder"},
            status_code=400,
        )
    if not path.exists():
        return JSONResponse({"ok": False, "error": "file is missing from disk"}, status_code=404)

    media = "video/mp4" if path.suffix.lower() == ".mp4" else "video/mp2t"
    return FileResponse(path, filename=path.name, media_type=media)


routes = [
    Route("/", index, methods=["GET", "HEAD"]),
    Route("/app.js", app_js, methods=["GET", "HEAD"]),
    Route("/styles.css", styles_css, methods=["GET", "HEAD"]),
    Route("/health", health, methods=["GET", "HEAD"]),
    Route("/api/config", api_config, methods=["GET", "HEAD"]),
    Route("/api/inspect", api_inspect, methods=["POST"]),
    Route("/api/diagnose", api_diagnose, methods=["POST"]),
    Route("/api/download", api_download, methods=["POST"]),
    Route("/api/jobs", api_jobs, methods=["GET"]),
    Route("/api/events", api_events, methods=["GET"]),
    Route("/api/jobs/{job_id}/cancel", api_cancel, methods=["POST"]),
    Route("/api/jobs/{job_id}", api_delete, methods=["DELETE"]),
    Route("/api/jobs/{job_id}/file", api_file, methods=["GET", "HEAD"]),
]

app = Starlette(
    routes=routes,
    middleware=[
        Middleware(
            CORSMiddleware,
            allow_origins=["*"],
            allow_methods=["*"],
            allow_headers=["*"],
        ),
        Middleware(PreviewMiddleware),
    ],
)
