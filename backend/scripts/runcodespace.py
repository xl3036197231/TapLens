"""Run the temporary Codespaces integration stack from one command.

This helper is intentionally development-only.  It starts the controlled test
site and queue worker as child processes, then serves the FastAPI application
in the foreground so a Codespaces forwarded port can expose it temporarily.
"""

from __future__ import annotations

import os
from pathlib import Path
import secrets
import subprocess
import sys

import uvicorn


BACKEND_ROOT = Path(__file__).resolve().parents[1]
REPOSITORY_ROOT = BACKEND_ROOT.parent


def codespace_public_url(port: int) -> str:
    codespace_name = os.environ.get("CODESPACE_NAME")
    if not codespace_name:
        raise SystemExit("CODESPACE_NAME is unavailable; run this inside GitHub Codespaces")
    forwarding_domain = os.environ.get(
        "GITHUB_CODESPACES_PORT_FORWARDING_DOMAIN",
        "app.github.dev",
    )
    return f"https://{codespace_name}-{port}.{forwarding_domain}"


def configure_environment() -> None:
    os.environ.setdefault("TAPLENS_ENVIRONMENT", "development")
    os.environ.setdefault("TAPLENS_DATABASE_PATH", "/tmp/taplens-codespace.db")
    os.environ.setdefault("TAPLENS_ARTIFACT_DIRECTORY", "/tmp/taplens-artifacts")
    os.environ.setdefault("TAPLENS_PUBLIC_BASE_URL", codespace_public_url(8000))
    os.environ.setdefault("TAPLENS_JWT_SECRET", secrets.token_hex(32))
    os.environ.setdefault("TAPLENS_TEST_ALLOWED_ORIGINS", "http://127.0.0.1:8765")


def start_child(command: list[str], log_name: str) -> tuple[subprocess.Popen[bytes], object]:
    log = open(f"/tmp/{log_name}", "ab", buffering=0)
    process = subprocess.Popen(command, cwd=BACKEND_ROOT, stdout=log, stderr=log)
    return process, log


def main() -> None:
    configure_environment()
    site, site_log = start_child(
        [
            sys.executable,
            "scripts/run_test_site.py",
            "--directory",
            str(REPOSITORY_ROOT / "mobile/test/ai/day2_site"),
            "--port",
            "8765",
        ],
        "taplens-codespace-site.log",
    )
    worker, worker_log = start_child(
        [sys.executable, "scripts/run_worker.py", "--poll-seconds", "0.5"],
        "taplens-codespace-worker.log",
    )
    try:
        uvicorn.run("app.main:app", host="0.0.0.0", port=8000, log_level="info")
    finally:
        for process in (site, worker):
            process.terminate()
        for process in (site, worker):
            process.wait(timeout=5)
        site_log.close()
        worker_log.close()


if __name__ == "__main__":
    main()
