import argparse
import os
import subprocess
import sys
import time
from pathlib import Path


BACKEND_ROOT = Path(__file__).resolve().parents[1]


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Run the local QR v2 API and worker with a non-networked Fake Provider"
    )
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=8000)
    parser.add_argument(
        "--scenario",
        choices=("success", "failure", "timeout", "result_expired"),
        default="success",
    )
    parser.add_argument(
        "--database",
        type=Path,
        default=None,
    )
    return parser.parse_args()


def stop(processes: list[subprocess.Popen[bytes]]) -> None:
    for process in processes:
        if process.poll() is None:
            process.terminate()
    for process in processes:
        try:
            process.wait(timeout=5)
        except subprocess.TimeoutExpired:
            process.kill()


def main() -> int:
    args = parse_args()
    database = args.database or BACKEND_ROOT / f"data/qr-v2-mock-{args.scenario}.db"
    database.parent.mkdir(parents=True, exist_ok=True)
    environment = os.environ.copy()
    environment.update(
        TAPLENS_ENVIRONMENT="development",
        TAPLENS_HOST=args.host,
        TAPLENS_PORT=str(args.port),
        TAPLENS_DATABASE_PATH=str(database.resolve()),
        TAPLENS_PUBLIC_BASE_URL=f"http://{args.host}:{args.port}",
        TAPLENS_JWT_SECRET="qr-v2-mock-only-jwt-secret-32-bytes-minimum",
        TAPLENS_LLM_ENABLED="false",
        TAPLENS_QR_FAKE_PROVIDER_ENABLED="true",
        TAPLENS_QR_FAKE_PROVIDER_SCENARIO=args.scenario,
    )
    commands = [
        [
            sys.executable,
            "-m",
            "uvicorn",
            "app.main:app",
            "--host",
            args.host,
            "--port",
            str(args.port),
        ],
        [sys.executable, "scripts/run_worker.py", "--poll-seconds", "0.2"],
    ]
    processes = [
        subprocess.Popen(command, cwd=BACKEND_ROOT, env=environment)
        for command in commands
    ]
    try:
        while True:
            for process in processes:
                return_code = process.poll()
                if return_code is not None:
                    return return_code or 1
            time.sleep(0.2)
    except KeyboardInterrupt:
        return 0
    finally:
        stop(processes)


if __name__ == "__main__":
    raise SystemExit(main())
