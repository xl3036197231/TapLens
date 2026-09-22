import asyncio
import json
import threading
from datetime import UTC, datetime, timedelta
from uuid import uuid4

from app.sandbox.collector import DeepScanCollector, build_request_authorizer
from app.sandbox.test_site_server import create_controlled_site_server
from app.tasks.evidence import build_success_evidence


def test_controlled_site_produces_redirect_and_sensitive_form_evidence(tmp_path) -> None:
    site = tmp_path / "site"
    site.mkdir()
    (site / "campus-login.html").write_text(
        """<!doctype html>
        <html><head><title>Example Campus single sign-on</title></head>
        <body>
          <form method="post" action="/blocked-submit">
            <input name="student_id" value="REDACTED">
            <input name="password" type="password" value="TEST_ONLY">
          </form>
          <script>
            fetch('/blocked-submit', {method: 'POST', body: 'password=TEST_ONLY'}).catch(() => {});
            window.open('/popup.html', '_blank');
            const download = document.createElement('a');
            download.href = '/download.txt';
            download.download = 'download.txt';
            document.body.append(download);
            download.click();
          </script>
        </body></html>""",
        encoding="utf-8",
    )
    (site / "popup.html").write_text("controlled popup", encoding="utf-8")
    (site / "download.txt").write_text("controlled download", encoding="utf-8")
    server = create_controlled_site_server(directory=site, port=0)
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    try:
        port = server.server_address[1]
        origin = f"http://127.0.0.1:{port}"
        task_id = str(uuid4())
        collector = DeepScanCollector(
            artifact_directory=tmp_path / "artifacts",
            request_authorizer=build_request_authorizer((origin,)),
        )

        result = asyncio.run(
            collector.collect(task_id=task_id, target_url=f"{origin}/go/campus")
        )
    finally:
        server.shutdown()
        server.server_close()
        thread.join(timeout=2)

    assert result.final_url == f"{origin}/campus-login.html"
    assert result.redirects == [{
        "from_url": f"{origin}/go/campus",
        "to_url": f"{origin}/campus-login.html",
        "status_code": 302,
    }]
    assert [field["name"] for field in result.forms[0]["fields"]] == [
        "student_id",
        "password",
    ]
    assert all(field["sensitive"] is True for field in result.forms[0]["fields"])
    blocked_types = {action["type"] for action in result.blocked_actions}
    assert {"business_post", "download", "popup"} <= blocked_types
    serialized = json.dumps(result.__dict__, default=str)
    assert "TEST_ONLY" not in serialized
    assert "REDACTED" not in serialized

    generated_at = datetime.now(UTC)
    evidence = build_success_evidence(
        analysis_id=uuid4(),
        task_id=uuid4(),
        initial_url=f"{origin}/go/campus?token=secret",
        result=result,
        generated_at=generated_at,
        expires_at=generated_at + timedelta(minutes=30),
        duration_ms=100,
        public_base_url="http://127.0.0.1:8000",
    )

    assert evidence["initial_url"] == f"{origin}/go/campus"
    assert evidence["evidence"][0]["id"] == "C01"
    assert evidence["evidence"][0]["kind"] == "redirect"
    assert evidence["evidence"][1]["id"] == "C02"
    assert evidence["evidence"][1]["kind"] == "form"
