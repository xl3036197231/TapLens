import argparse
import json
import time
from datetime import UTC, datetime
from pathlib import Path
from uuid import uuid4

import httpx


ROOT = Path(__file__).resolve().parents[2]
REQUEST_FIXTURE = ROOT / "shared/fixtures/qr/qr-cloud-analysis-v2-request.json"


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Smoke-test the local QR v2 Fake Provider lane")
    parser.add_argument("--base-url", default="http://127.0.0.1:8000")
    parser.add_argument("--timeout-seconds", type=float, default=15.0)
    parser.add_argument(
        "--expected-state",
        choices=("succeeded", "failed", "outcome_unknown", "result_expired"),
        default="succeeded",
    )
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    base_url = args.base_url.rstrip("/")
    suffix = uuid4().hex[:12]
    credentials = {"username": f"qr_mock_{suffix}", "password": f"mock-pass-{suffix}"}
    body = json.loads(REQUEST_FIXTURE.read_text(encoding="utf-8"))
    body["analysis_id"] = str(uuid4())
    body["created_at"] = datetime.now(UTC).isoformat().replace("+00:00", "Z")

    with httpx.Client(base_url=base_url, timeout=5.0) as client:
        register = client.post("/api/v1/auth/register", json=credentials)
        register.raise_for_status()
        login = client.post("/api/v1/auth/login", json=credentials)
        login.raise_for_status()
        headers = {"Authorization": f"Bearer {login.json()['access_token']}"}
        created = client.post("/api/v1/qr-analyses", headers=headers, json=body)
        if created.status_code != 202:
            raise RuntimeError(f"create failed: HTTP {created.status_code} {created.text}")
        response = created.json()
        if created.headers.get("location") != response["status_path"]:
            raise RuntimeError("Location header does not match status_path")
        if created.headers.get("retry-after") != str(response["poll_after_seconds"]):
            raise RuntimeError("Retry-After header does not match response")

        deadline = time.monotonic() + args.timeout_seconds
        states: list[str] = []
        result = None
        while time.monotonic() < deadline:
            status = client.get(response["status_path"], headers=headers)
            status.raise_for_status()
            result = status.json()
            if not states or states[-1] != result["state"]:
                states.append(result["state"])
            if result["state"] == args.expected_state:
                break
            time.sleep(min(float(result["poll_after_seconds"]), 0.25))
        if result is None or result["state"] != args.expected_state:
            raise RuntimeError(
                f"QR v2 Mock did not reach {args.expected_state}; "
                f"states={states}, result={result}"
            )
        if result["actions"]["repeat_post"] is not False:
            raise RuntimeError("terminal or unknown result unexpectedly permits POST replay")
        if args.expected_state == "succeeded":
            if result["usage"] != {
                "status": "known",
                "request_count": 1,
                "prompt_tokens": 40,
                "completion_tokens": 20,
                "total_tokens": 60,
                "model": "taplens/qr-v2-fake",
            }:
                raise RuntimeError(f"unexpected Fake Provider usage: {result['usage']}")
            if result["report"]["token_usage"] != {
                key: value for key, value in result["usage"].items() if key != "status"
            }:
                raise RuntimeError("top-level usage and report.token_usage differ")
        expected_error = {
            "failed": "AI_PROVIDER_UNAVAILABLE",
            "outcome_unknown": "AI_OUTCOME_UNKNOWN",
            "result_expired": "CLOUD_TASK_RESULT_EXPIRED",
        }.get(args.expected_state)
        if expected_error is not None and result["error"]["code"] != expected_error:
            raise RuntimeError(f"unexpected error contract: {result['error']}")
        if args.expected_state == "result_expired" and (
            result["report"] is not None or result["evidence_bundle"] is not None
        ):
            raise RuntimeError("expired result retained report or evidence cache")

    print(
        f"QR v2 HTTP Mock PASS; expected={args.expected_state}; "
        f"states={' -> '.join(states)}"
    )
    print("Provider=taplens/qr-v2-fake; network_model_calls=0")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
