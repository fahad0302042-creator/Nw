"""Run the Nw server:  python run.py"""

import uvicorn

from nw.config import load_config


def main() -> None:
    cfg = load_config()
    uvicorn.run(
        "nw.server:app",
        host=cfg.host,
        port=cfg.port,
        log_level="info",
        proxy_headers=True,
        forwarded_allow_ips="*",
    )


if __name__ == "__main__":
    main()
