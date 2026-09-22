import asyncio
import json
import threading
from datetime import UTC, datetime, timedelta
from pathlib import Path
from uuid import uuid4

from jsonschema import Draft202012Validator, FormatChecker
from referencing import Registry, Resource

from app.sandbox.collector import DeepScanCollector, build_request_authorizer
from app.sandbox.test_site_server import create_controlled_site_server
from app.tasks.evidence import build_success_evidence


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
DAY2_SITE = REPOSITORY_ROOT / "mobile/test/ai/day2_site"
DAY2_REPORT = REPOSITORY_ROOT / "shared/fixtures/reports/day2-short-link-high-risk.json"
CLOUD_SCHEMA = REPOSITORY_ROOT / "shared/contracts/cloud-evidence.schema.json"
COMMON_SCHEMA = REPOSITORY_ROOT / "shared/contracts/common.schema.json"


def test_day2_short_link_collects_reported_c01_and_c02(tmp_path) -> None:
    server = create_controlled_site_server(directory=DAY2_SITE, port=0)
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    try:
        port = server.server_address[1]
        origin = f"http://127.0.0.1:{port}"
        task_id = uuid4()
        collector = DeepScanCollector(
            artifact_directory=tmp_path / "artifacts",
            request_authorizer=build_request_authorizer((origin,)),
        )
        result = asyncio.run(
            collector.collect(
                task_id=str(task_id),
                target_url=f"{origin}/go/campus?tracking=must-not-survive",
            )
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
    assert len(result.forms) == 1
    assert result.forms[0]["method"] == "POST"
    assert [(field["name"], field["sensitive"]) for field in result.forms[0]["fields"]] == [
        ("student_id", True),
        ("password", True),
    ]
    assert result.screenshot_path.is_file()
    serialized_result = json.dumps(result.__dict__, default=str)
    assert "REDACTED" not in serialized_result
    assert "TEST_ONLY" not in serialized_result
    assert "must-not-survive" not in serialized_result

    now = datetime.now(UTC)
    evidence = build_success_evidence(
        analysis_id=uuid4(),
        task_id=task_id,
        initial_url=f"{origin}/go/campus?tracking=must-not-survive",
        result=result,
        generated_at=now,
        expires_at=now + timedelta(minutes=30),
        duration_ms=100,
        public_base_url="http://127.0.0.1:8000",
    )
    schema = json.loads(CLOUD_SCHEMA.read_text(encoding="utf-8"))
    common_schema = json.loads(COMMON_SCHEMA.read_text(encoding="utf-8"))
    registry = Registry().with_resource(
        common_schema["$id"],
        Resource.from_contents(common_schema),
    )
    errors = list(
        Draft202012Validator(
            schema,
            registry=registry,
            format_checker=FormatChecker(),
        ).iter_errors(evidence)
    )
    assert errors == []

    report = json.loads(DAY2_REPORT.read_text(encoding="utf-8"))
    report_cloud_ids = {
        item["id"] for item in report["evidence"] if item["source"] == "cloud"
    }
    collected_by_id = {item["id"]: item for item in evidence["evidence"]}
    assert report_cloud_ids == {"C01", "C02"}
    assert collected_by_id["C01"]["kind"] == "redirect"
    assert collected_by_id["C02"]["kind"] == "form"
