"""Poll the temporary Codespaces stack without creating cloud tasks.

This monitor is intentionally read-only. It checks the local API, the two
public forwarded endpoints, and the latest task rows without printing account
credentials, bearer tokens, cookies, request payloads, or evidence content.
"""

from __future__ import annotations

import argparse
from dataclasses import dataclass
from datetime import UTC, datetime
import json
import os
from pathlib import Path
import sqlite3
import time
from urllib.error import HTTPError, URLError
from urllib.request import HTTPRedirectHandler, Request, build_opener


DEFAULT_DATABASE = Path("/tmp/taplens-codespace.db")


class NoRedirectHandler(HTTPRedirectHandler):
    def redirect_request(self, request, file_pointer, code, message, headers, new_url):
        return None


@dataclass(frozen=True)
class HttpCheck:
    label: str
    status: int | None
    healthy: bool
    detail: str


def request_once(url: str, *, timeout: float) -> tuple[int | None, bytes, str | None]:
    request = Request(url, headers={"User-Agent": "TapLens-Codespace-Monitor/1.0"})
    opener = build_opener(NoRedirectHandler())
    try:
        with opener.open(request, timeout=timeout) as response:
            return response.status, response.read(), response.headers.get("Location")
    except HTTPError as error:
        return error.code, error.read(), error.headers.get("Location")
    except (TimeoutError, URLError, OSError) as error:
        return None, b"", type(error).__name__


def check_health(label: str, url: str, *, timeout: float) -> HttpCheck:
    status, body, transport_detail = request_once(url, timeout=timeout)
    if status != 200:
        return HttpCheck(label, status, False, transport_detail or "unexpected-status")
    try:
        payload = json.loads(body)
    except (UnicodeDecodeError, json.JSONDecodeError):
        return HttpCheck(label, status, False, "invalid-json")
    healthy = payload.get("status") == "ok" and payload.get("service") == "taplens-backend"
    return HttpCheck(label, status, healthy, "ok" if healthy else "unexpected-body")


def check_site(url: str, *, timeout: float) -> HttpCheck:
    status, _, location = request_once(url, timeout=timeout)
    healthy = status == 302 and location == "/campus-login.html"
    detail = f"location={location}" if location else "missing-location"
    return HttpCheck("public-site", status, healthy, detail)


def latest_tasks(database_path: Path, *, limit: int) -> list[tuple[object, ...]]:
    if not database_path.is_file():
        return []
    try:
        with sqlite3.connect(database_path, timeout=1) as connection:
            return connection.execute(
                """
                SELECT id, analysis_id, status, duration_ms, error_code
                FROM cloud_scan_tasks
                ORDER BY created_at DESC
                LIMIT ?
                """,
                (limit,),
            ).fetchall()
    except sqlite3.Error:
        return []


def public_urls() -> tuple[str, str]:
    codespace_name = os.environ.get("CODESPACE_NAME")
    if not codespace_name:
        raise SystemExit("CODESPACE_NAME is unavailable; run this inside GitHub Codespaces")
    forwarding_domain = os.environ.get(
        "GITHUB_CODESPACES_PORT_FORWARDING_DOMAIN",
        "app.github.dev",
    )
    api_url = f"https://{codespace_name}-8000.{forwarding_domain}/api/v1/health"
    site_url = f"https://{codespace_name}-8765.{forwarding_domain}/go/campus"
    return api_url, site_url


def format_check(check: HttpCheck) -> str:
    status = str(check.status) if check.status is not None else "ERR"
    state = "OK" if check.healthy else "FAIL"
    return f"{check.label}={state}({status},{check.detail})"


def poll_once(*, timeout: float, database_path: Path, task_limit: int) -> bool:
    public_api_url, public_site_url = public_urls()
    checks = [
        check_health(
            "local-api",
            "http://127.0.0.1:8000/api/v1/health",
            timeout=timeout,
        ),
        check_health("public-api", public_api_url, timeout=timeout),
        check_site(public_site_url, timeout=timeout),
    ]
    timestamp = datetime.now(UTC).astimezone().isoformat(timespec="seconds")
    print(timestamp, *(format_check(check) for check in checks), flush=True)
    tasks = latest_tasks(database_path, limit=task_limit)
    if not tasks:
        print("  tasks=none", flush=True)
    for task_id, analysis_id, status, duration_ms, error_code in tasks:
        print(
            "  task="
            f"{task_id} analysis={analysis_id} status={status} "
            f"duration_ms={duration_ms if duration_ms is not None else '-'} "
            f"error={error_code or '-'}",
            flush=True,
        )
    return all(check.healthy for check in checks)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Monitor TapLens Codespaces API, test site, and recent tasks",
    )
    parser.add_argument("--interval", type=float, default=10.0)
    parser.add_argument("--timeout", type=float, default=5.0)
    parser.add_argument("--database", type=Path, default=DEFAULT_DATABASE)
    parser.add_argument("--task-limit", type=int, default=3)
    parser.add_argument("--once", action="store_true")
    return parser.parse_args()


def main() -> int:
    arguments = parse_args()
    interval = max(1.0, arguments.interval)
    timeout = max(0.5, arguments.timeout)
    task_limit = max(1, arguments.task_limit)
    while True:
        healthy = poll_once(
            timeout=timeout,
            database_path=arguments.database,
            task_limit=task_limit,
        )
        if arguments.once:
            return 0 if healthy else 1
        try:
            time.sleep(interval)
        except KeyboardInterrupt:
            print("monitor stopped", flush=True)
            return 0


if __name__ == "__main__":
    raise SystemExit(main())
