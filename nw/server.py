"""FastAPI app: serves the UI and drives the download manager."""

from __future__ import annotations

import asyncio
import json
import shutil
from pathlib import Path

from fastapi import FastAPI, HTTPException, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import FileResponse, JSONResponse, StreamingResponse
from pydantic import BaseModel, Field

from .config import load_config
from .extractors import get_extractor
from .extractors.base import ExtractorError
from .downloader import DownloadManager

WEB_DIR = Path(__file__).resolve().parent.parent / "web"

cfg = load_config()
extractor = get_extractor(cfg)
manager = DownloadManager(cfg, extractor)

app = FastAPI(title="Nw", version="0.1.0", redirect_slashes=False)
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)


@app.middleware("http")
async def allow_preview_iframe(request: Request, call_next):
    """Preview is shown in an iframe on a different origin — don't block it."""
    response = await call_next(request)
    response.headers["Content-Security-Policy"] = "frame-ancestors *"
    if "x-frame-options" in response.headers:
        del response.headers["x-frame-options"]
    return response


# --------------------------------------------------------------------- models
class InspectRequest(BaseModel):
    url: str = Field(..., min_length=4)
    quality: str = "auto"
    refresh: bool = False


class DownloadRequest(BaseModel):
    url: str = Field(..., min_length=4)
    item_index: int | None = None
    quality: str = "auto"


class UrlRequest(BaseModel):
    url: str = Field(..., min_length=4)


# ------------------------------------------------------------------ web routes
@app.api_route("/", methods=["GET", "HEAD"])
def index() -> FileResponse:
    return FileResponse(WEB_DIR / "index.html")


@app.api_route("/app.js", methods=["GET", "HEAD"])
def app_js() -> FileResponse:
    return FileResponse(WEB_DIR / "app.js", media_type="application/javascript")


@app.api_route("/styles.css", methods=["GET", "HEAD"])
def styles_css() -> FileResponse:
    return FileResponse(WEB_DIR / "styles.css", media_type="text/css")


@app.api_route("/health", methods=["GET", "HEAD"])
def health() -> dict:
    return {"ok": True}


# ----------------------------------------------------------------- api routes
@app.get("/api/config")
def api_config() -> dict:
    return {
        "download_dir": str(cfg.download_dir),
        "extractor": extractor.name,
        "has_ffmpeg": bool(shutil.which("ffmpeg")),
        "concurrency": cfg.concurrency,
        "allowed_hosts": list(cfg.allowed_hosts),
    }


@app.post("/api/inspect")
async def api_inspect(req: InspectRequest) -> JSONResponse:
    try:
        info = await manager.inspect(req.url.strip(), req.quality, req.refresh)
    except ExtractorError as exc:
        return JSONResponse({"ok": False, "error": str(exc)}, status_code=422)
    except Exception as exc:  # noqa: BLE001
        return JSONResponse({"ok": False, "error": f"{type(exc).__name__}: {exc}"}, status_code=500)
    return JSONResponse({"ok": True, **info.to_dict()})


@app.post("/api/diagnose")
async def api_diagnose(req: UrlRequest) -> JSONResponse:
    try:
        data = await manager.diagnose(req.url.strip())
    except Exception as exc:  # noqa: BLE001
        return JSONResponse({"ok": False, "error": f"{type(exc).__name__}: {exc}"}, status_code=500)
    return JSONResponse({"ok": True, "dump": data})


@app.post("/api/download")
async def api_download(req: DownloadRequest) -> JSONResponse:
    job = manager.create(req.url.strip(), req.item_index, req.quality)
    return JSONResponse({"ok": True, "job": job.to_dict()})


@app.get("/api/jobs")
def api_jobs() -> dict:
    return {"jobs": manager.list_jobs()}


@app.get("/api/events")
async def api_events() -> StreamingResponse:
    """Server-sent stream of job states (a snapshot twice a second)."""

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


@app.post("/api/jobs/{job_id}/cancel")
def api_cancel(job_id: str) -> dict:
    if not manager.cancel(job_id):
        raise HTTPException(404, "job not found")
    return {"ok": True}


@app.delete("/api/jobs/{job_id}")
def api_delete(job_id: str) -> dict:
    job = manager.jobs.pop(job_id, None)
    if not job:
        raise HTTPException(404, "job not found")
    manager.cancel(job_id)
    return {"ok": True}


@app.get("/api/jobs/{job_id}/file")
def api_file(job_id: str) -> FileResponse:
    """Stream a finished download to the browser so it saves to your device."""
    job = manager.get(job_id)
    if not job or not job.path or job.status != "done":
        raise HTTPException(404, "no finished file for this job")

    path = Path(job.path).resolve()
    root = cfg.download_dir.resolve()
    if root != path.parent and root not in path.parents:
        raise HTTPException(400, "refusing to serve a file outside the download folder")

    if not path.exists():
        raise HTTPException(404, "file is missing from disk")

    media = "video/mp4" if path.suffix.lower() == ".mp4" else "video/mp2t"
    return FileResponse(path, filename=path.name, media_type=media)
