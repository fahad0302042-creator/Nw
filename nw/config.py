from __future__ import annotations

import os
from dataclasses import dataclass, field
from pathlib import Path

# Hosts this tool is allowed to fetch from. Keeping this closed prevents the
# server from being used as a general-purpose open proxy / SSRF pivot.
DEFAULT_ALLOWED_HOSTS = (
    "diskwala.com",
    "www.diskwala.com",
    "diskwala.app",
    "www.diskwala.app",
    "terabox.com",
    "www.terabox.com",
    "teraboxapp.com",
    "www.teraboxapp.com",
    "1024tera.com",
    "www.1024tera.com",
    "freeterabox.com",
    "www.freeterabox.com",
)

BROWSER_UA = (
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 "
    "(KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36"
)


def _default_download_dir() -> Path:
    """Prefer ~/Downloads/Nw when a Downloads folder exists."""
    home = Path.home()
    for candidate in (home / "Downloads", home / "downloads"):
        if candidate.is_dir():
            return candidate / "Nw"
    return Path.cwd() / "downloads"


def _env_bool(name: str, default: bool) -> bool:
    raw = os.getenv(name)
    if raw is None:
        return default
    return raw.strip().lower() in {"1", "true", "yes", "on"}


@dataclass
class Config:
    download_dir: Path = field(default_factory=_default_download_dir)
    host: str = "0.0.0.0"
    port: int = 8000

    allowed_hosts: tuple[str, ...] = DEFAULT_ALLOWED_HOSTS
    user_agent: str = BROWSER_UA
    concurrency: int = 4
    max_retries: int = 3
    timeout: float = 30.0
    max_bytes_per_sec: int = 0  # 0 = unlimited

    # Third-party extraction API (optional)
    api_url: str = ""
    api_key: str = ""
    api_method: str = "POST"
    api_auth_header: str = "Authorization"
    api_auth_prefix: str = "Bearer"

    # Direct extractor tuning
    app_id: str = "250528"
    clienttype: str = "0"

    def ensure_dirs(self) -> None:
        self.download_dir.mkdir(parents=True, exist_ok=True)


def load_config() -> Config:
    """Build a Config from environment variables (optionally loaded from .env)."""
    try:
        from dotenv import load_dotenv

        load_dotenv()
    except ImportError:  # python-dotenv is optional at runtime
        pass

    cfg = Config(
        download_dir=Path(os.getenv("NW_DOWNLOAD_DIR") or _default_download_dir()).expanduser(),
        host=os.getenv("NW_HOST", "0.0.0.0"),
        port=int(os.getenv("NW_PORT", "8000")),
        user_agent=os.getenv("NW_USER_AGENT", BROWSER_UA),
        concurrency=int(os.getenv("NW_CONCURRENCY", "4")),
        max_retries=int(os.getenv("NW_MAX_RETRIES", "3")),
        timeout=float(os.getenv("NW_TIMEOUT", "30")),
        max_bytes_per_sec=int(os.getenv("NW_MAX_BYTES_PER_SEC", "0")),
        api_url=os.getenv("NW_API_URL", ""),
        api_key=os.getenv("NW_API_KEY", ""),
        api_method=os.getenv("NW_API_METHOD", "POST").upper(),
        api_auth_header=os.getenv("NW_API_AUTH_HEADER", "Authorization"),
        api_auth_prefix=os.getenv("NW_API_AUTH_PREFIX", "Bearer"),
        app_id=os.getenv("NW_APP_ID", "250528"),
        clienttype=os.getenv("NW_CLIENTTYPE", "0"),
    )

    extra = os.getenv("NW_ALLOWED_HOSTS", "")
    if extra.strip():
        cfg.allowed_hosts = tuple(
            h.strip().lower() for h in extra.split(",") if h.strip()
        ) + DEFAULT_ALLOWED_HOSTS

    cfg.ensure_dirs()
    return cfg
