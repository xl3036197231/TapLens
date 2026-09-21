import asyncio
import contextlib
import threading
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

from app.sandbox.collector import DeepScanCollector


BACKEND_ROOT = Path(__file__).resolve().parents[1]


async def allow_local_test_request(_: str) -> None:
    return None


def run_probe() -> None:
    handler = lambda *args, **kwargs: SimpleHTTPRequestHandler(
        *args,
        directory=str(BACKEND_ROOT / "fixtures"),
        **kwargs,
    )
    server = ThreadingHTTPServer(("127.0.0.1", 0), handler)
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    try:
        collector = DeepScanCollector(
            artifact_directory=BACKEND_ROOT / "artifacts",
            request_authorizer=allow_local_test_request,
        )
        result = asyncio.run(
            collector.collect(
                task_id="collector-probe",
                target_url=f"http://127.0.0.1:{server.server_port}/demo_page.html",
            )
        )
        print(
            {
                "title": result.title,
                "final_url": result.final_url,
                "forms": result.forms,
                "requests": result.requests,
                "screenshot": str(result.screenshot_path),
            }
        )
    finally:
        server.shutdown()
        server.server_close()
        thread.join(timeout=2)


if __name__ == "__main__":
    with contextlib.suppress(KeyboardInterrupt):
        run_probe()
