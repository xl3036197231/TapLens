import asyncio
import json
import threading
from datetime import UTC, datetime, timedelta
from pathlib import Path
from uuid import UUID, uuid4
from zoneinfo import ZoneInfo

from httpx import ASGITransport, AsyncClient
from jsonschema import Draft202012Validator, FormatChecker
from referencing import Registry, Resource

from app.core.config import Settings
from app.main import create_app
from app.sandbox.collector import DeepScanCollector, build_request_authorizer
from app.sandbox.test_site_server import create_controlled_site_server
from app.storage.tasks import TaskRepository
from app.tasks.evidence import build_success_evidence
from app.tasks.executor import TaskExecutor
from app.tasks.service import TaskService


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
DAY2_SITE = REPOSITORY_ROOT / "mobile/test/ai/day2_site"
DAY2_REPORT = REPOSITORY_ROOT / "shared/fixtures/reports/day2-short-link-high-risk.json"
CLOUD_SCHEMA = REPOSITORY_ROOT / "shared/contracts/cloud-evidence.schema.json"
COMMON_SCHEMA = REPOSITORY_ROOT / "shared/contracts/common.schema.json"
TEST_SECRET = "test-secret-that-is-long-enough-for-qr01-integration"


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


def test_fictional_cloud_fixture_maps_to_controlled_site_and_marks_simulation(tmp_path) -> None:
    server = create_controlled_site_server(directory=DAY2_SITE, port=0)
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    try:
        port = server.server_address[1]
        origin = f"http://127.0.0.1:{port}"
        task_id = uuid4()
        collector = DeepScanCollector(
            artifact_directory=tmp_path / "artifacts",
            fictional_fixture_base_url=origin,
        )
        initial_url = "https://campus.example.test/go/campus"
        result = asyncio.run(
            collector.collect(task_id=str(task_id), target_url=initial_url)
        )
    finally:
        server.shutdown()
        server.server_close()
        thread.join(timeout=2)

    virtual_origin = "https://campus.example.test"
    assert result.final_url == f"{virtual_origin}/campus-login.html"
    assert result.redirects == [{
        "from_url": f"{virtual_origin}/go/campus",
        "to_url": f"{virtual_origin}/campus-login.html",
        "status_code": 302,
    }]
    assert result.forms[0]["action"] == f"{virtual_origin}/blocked-submit"
    assert [(field["name"], field["sensitive"]) for field in result.forms[0]["fields"]] == [
        ("student_id", True),
        ("password", True),
    ]
    assert {request["origin"] for request in result.requests} == {virtual_origin}
    assert result.screenshot_path.is_file()
    assert any("模拟云端证据" in item for item in result.limitations)

    now = datetime.now(UTC)
    evidence = build_success_evidence(
        analysis_id=uuid4(),
        task_id=task_id,
        initial_url=initial_url,
        result=result,
        generated_at=now,
        expires_at=now + timedelta(minutes=30),
        duration_ms=100,
        public_base_url="https://taplens.example.test",
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
    assert [item["id"] for item in evidence["evidence"]] == ["C01", "C02", "C03", "C04"]
    assert [item["kind"] for item in evidence["evidence"]] == [
        "redirect",
        "form",
        "page",
        "screenshot",
    ]
    serialized = json.dumps(evidence)
    assert "nginx:8080" not in serialized
    assert "127.0.0.1" not in serialized
    assert "TEST_ONLY" not in serialized
    assert any("模拟云端证据" in item for item in evidence["limitations"])


def test_qr01_api_to_worker_uses_only_controlled_fixture(tmp_path) -> None:
    server = create_controlled_site_server(directory=DAY2_SITE, port=0)
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    try:
        origin = f"http://127.0.0.1:{server.server_address[1]}"
        settings = Settings(
            environment="test",
            database_path=tmp_path / "taplens-qr01-integration.db",
            artifact_directory=tmp_path / "artifacts",
            jwt_secret=TEST_SECRET,
            daily_quota_limit=2,
        )
        app = create_app(settings)
        app.state.database.initialize()
        credentials = {"username": "Qr01_Worker_User", "password": "correct-horse"}
        assert api_request(app, "POST", "/api/v1/auth/register", json=credentials).status_code == 201
        login = api_request(app, "POST", "/api/v1/auth/login", json=credentials)
        token = login.json()["access_token"]
        analysis_id = uuid4()
        created = api_request(
            app,
            "POST",
            "/api/v1/deep-scans",
            token=token,
            json={
                "analysis_id": str(analysis_id),
                "url": "https://campus.example.test/go/campus",
            },
        )
        assert created.status_code == 202
        task_id = UUID(created.json()["task_id"])
        repository = TaskRepository(app.state.database)
        service = TaskService(
            repository=repository,
            daily_limit=2,
            quota_timezone=ZoneInfo("Asia/Shanghai"),
            digest_secrets=settings.ai_digest_secret_map,
            active_digest_key_version=settings.ai_digest_active_key_version,
        )
        executor = TaskExecutor(
            repository=repository,
            service=service,
            collector=DeepScanCollector(
                artifact_directory=settings.artifact_directory,
                fictional_fixture_base_url=origin,
            ),
            public_base_url="http://testserver",
        )
        assert asyncio.run(executor.execute(task_id)) is True
        completed = api_request(
            app,
            "GET",
            f"/api/v1/deep-scans/{task_id}",
            token=token,
        )
    finally:
        server.shutdown()
        server.server_close()
        thread.join(timeout=2)

    assert completed.status_code == 200
    body = completed.json()
    assert body["analysis_id"] == str(analysis_id)
    assert body["status"] == "succeeded"
    evidence = body["cloud_evidence"]
    assert [item["id"] for item in evidence["evidence"]] == [
        "C01",
        "C02",
        "C03",
        "C04",
    ]
    assert any("模拟云端证据" in item for item in evidence["limitations"])
    serialized = json.dumps(evidence, ensure_ascii=False)
    assert origin not in serialized
    assert "nginx:8080" not in serialized
    assert "campus.example.test" in serialized


def api_request(app, method: str, path: str, *, token: str | None = None, **kwargs):
    async def send():
        headers = kwargs.pop("headers", {})
        if token is not None:
            headers["Authorization"] = f"Bearer {token}"
        async with AsyncClient(
            transport=ASGITransport(app=app),
            base_url="http://testserver",
        ) as client:
            return await client.request(method, path, headers=headers, **kwargs)

    return asyncio.run(send())
