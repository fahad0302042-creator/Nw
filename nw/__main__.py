"""python -m nw  [serve | diagnose URL]"""

from __future__ import annotations

import argparse
import json
import sys


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(prog="nw", description="Nw — DiskWala downloader")
    sub = parser.add_subparsers(dest="cmd")

    serve = sub.add_parser("serve", help="start the web UI (default)")
    serve.add_argument("--host", default=None)
    serve.add_argument("--port", type=int, default=None)

    diag = sub.add_parser("diagnose", help="dump what a share URL returns")
    diag.add_argument("url")

    args = parser.parse_args(argv)
    cmd = args.cmd or "serve"

    if cmd == "diagnose":
        from .config import load_config
        from .extractors import get_extractor

        extractor = get_extractor(load_config())
        dump = extractor.diagnose(args.url)
        json.dump(dump, sys.stdout, indent=2, default=str)
        sys.stdout.write("\n")
        return 1 if dump.get("error") else 0

    from .config import load_config
    import uvicorn

    cfg = load_config()
    host = getattr(args, "host", None) or cfg.host
    port = getattr(args, "port", None) or cfg.port
    uvicorn.run("nw.server:app", host=host, port=port, log_level="info")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
