import argparse
import time
from uuid import uuid4

import httpx


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Verify register, login, quota, create and poll against TapLens",
    )
    parser.add_argument("--base-url", default="http://127.0.0.1:8000/api/v1")
    parser.add_argument("--target-url", required=True)
    parser.add_argument("--username", default="taplens_smoke_user")
    parser.add_argument("--password", default="taplens-test-password")
    parser.add_argument("--timeout-seconds", type=float, default=30.0)
    return parser.parse_args()


def require_status(response: httpx.Response, expected: set[int], step: str) -> None:
    if response.status_code not in expected:
        raise SystemExit(f"{step} failed: HTTP {response.status_code} {response.text}")


def main() -> None:
    arguments = parse_args()
    base_url = arguments.base_url.rstrip("/")
    credentials = {"username": arguments.username, "password": arguments.password}
    with httpx.Client(timeout=10.0) as client:
        health = client.get(f"{base_url}/health")
        require_status(health, {200}, "health")

        registration = client.post(f"{base_url}/auth/register", json=credentials)
        require_status(registration, {201, 409}, "register")

        login = client.post(f"{base_url}/auth/login", json=credentials)
        require_status(login, {200}, "login")
        token = login.json()["access_token"]
        headers = {"Authorization": f"Bearer {token}"}

        quota = client.get(f"{base_url}/quota", headers=headers)
        require_status(quota, {200}, "quota")

        created = client.post(
            f"{base_url}/deep-scans",
            headers=headers,
            json={"analysis_id": str(uuid4()), "url": arguments.target_url},
        )
        require_status(created, {202}, "create")
        task_id = created.json()["task_id"]

        deadline = time.monotonic() + arguments.timeout_seconds
        while True:
            result = client.get(f"{base_url}/deep-scans/{task_id}", headers=headers)
            require_status(result, {200}, "poll")
            payload = result.json()
            if payload["status"] in {"succeeded", "failed"}:
                print(
                    f"flow=ok task_id={task_id} status={payload['status']} "
                    f"remaining={created.json()['remaining']}"
                )
                return
            if time.monotonic() >= deadline:
                raise SystemExit(f"poll timed out for task_id={task_id}")
            retry_after = float(result.headers.get("Retry-After", "2"))
            time.sleep(max(0.1, retry_after))


if __name__ == "__main__":
    main()
