import asyncio
import json
from copy import deepcopy
from pathlib import Path

from httpx import ASGITransport, AsyncClient, MockTransport, Request, Response

from app.ai.provider import ProviderResult, SchoolOpenAiProvider
from app.core.config import Settings
from app.main import create_app


ROOT = Path(__file__).resolve().parents[2]
REQUEST_FIXTURE = ROOT / "shared/fixtures/ai/day5-school-model-request.json"
REPORT_FIXTURE = ROOT / "shared/fixtures/ai/day5-school-model-mock-report.json"
TEST_SECRET = "test-secret-that-is-long-enough-for-ai-api-tests"


class FakeProvider:
    def __init__(self, *, downgrade: bool = False) -> None:
        self.calls = []
        self.downgrade = downgrade

    async def analyze(self, payload: dict[str, object]) -> ProviderResult:
        self.calls.append(payload)
        report = json.loads(REPORT_FIXTURE.read_text(encoding="utf-8"))
        if self.downgrade:
            report["risk_level"] = "medium"
        return ProviderResult(
            report=report,
            prompt_tokens=120,
            completion_tokens=80,
            total_tokens=200,
            model="cuc/deepseek",
        )


def test_ai_requires_taplens_login(tmp_path) -> None:
    app = build_test_app(tmp_path, FakeProvider())
    response = request(app, "POST", "/api/v1/ai/analyze", json=payload())
    assert response.status_code == 401
    assert response.json()["error"]["code"] == "AUTH_TOKEN_MISSING"


def test_ai_rejects_client_key_without_echoing_it(tmp_path) -> None:
    provider = FakeProvider()
    app = build_test_app(tmp_path, provider)
    token = register_and_login(app)
    body = payload()
    secret = "sk-client-key-must-not-reach-backend-provider"
    body["deepseek_key"] = secret

    response = request(
        app,
        "POST",
        "/api/v1/ai/analyze",
        token=token,
        json=body,
    )

    assert response.status_code == 422
    assert response.json()["error"]["code"] == "AI_REQUEST_INVALID"
    assert secret not in response.text
    assert provider.calls == []


def test_ai_accepts_sanitized_day5_evidence_and_overwrites_usage(tmp_path) -> None:
    provider = FakeProvider()
    app = build_test_app(tmp_path, provider)
    token = register_and_login(app)

    response = request(
        app,
        "POST",
        "/api/v1/ai/analyze",
        token=token,
        json=payload(),
    )

    assert response.status_code == 200
    body = response.json()
    assert body["analysis_id"] == "0bab7eba-ff50-42f8-a264-543596b2c9bf"
    assert body["report"]["sources"] == {"local": True, "cloud": True, "ai": True}
    assert body["report"]["token_usage"] == {
        "request_count": 1,
        "prompt_tokens": 120,
        "completion_tokens": 80,
        "total_tokens": 200,
        "model": "cuc/deepseek",
    }
    assert body["usage"] == body["report"]["token_usage"]
    assert len(provider.calls) == 1
    assert "deepseek_key" not in json.dumps(provider.calls[0])
    assert "API-KEY" not in json.dumps(provider.calls[0])


def test_ai_rejects_model_downgrade_of_hard_high_risk(tmp_path) -> None:
    app = build_test_app(tmp_path, FakeProvider(downgrade=True))
    token = register_and_login(app)

    response = request(
        app,
        "POST",
        "/api/v1/ai/analyze",
        token=token,
        json=payload(),
    )

    assert response.status_code == 502
    assert response.json()["error"]["code"] == "AI_REPORT_REJECTED"


def test_enabled_llm_requires_complete_secure_configuration(tmp_path) -> None:
    try:
        Settings(
            environment="test",
            database_path=tmp_path / "taplens-test.db",
            jwt_secret=TEST_SECRET,
            llm_enabled=True,
        )
    except ValueError as error:
        assert "enabled LLM requires" in str(error)
    else:
        raise AssertionError("incomplete LLM configuration was accepted")


def test_school_provider_uses_documented_openai_request_without_extra_parameters(tmp_path) -> None:
    captured = {}

    def handler(request: Request) -> Response:
        captured["url"] = str(request.url)
        captured["authorization"] = request.headers.get("authorization")
        captured["body"] = json.loads(request.content)
        captured["timeout"] = request.extensions.get("timeout")
        report = REPORT_FIXTURE.read_text(encoding="utf-8")
        return Response(
            200,
            json={
                "choices": [{"message": {"content": report}}],
                "usage": {
                    "prompt_tokens": 12,
                    "completion_tokens": 8,
                    "total_tokens": 20,
                },
            },
        )

    settings = Settings(
        environment="test",
        database_path=tmp_path / "taplens-test.db",
        jwt_secret=TEST_SECRET,
        llm_enabled=True,
        llm_base_url="https://openai.cuc.edu.cn/v1",
        llm_api_key="school-key-test-placeholder",
        llm_model="cuc/deepseek",
    )
    provider = SchoolOpenAiProvider(settings, transport=MockTransport(handler))
    result = asyncio.run(provider.analyze(payload()))

    assert captured["url"] == "https://openai.cuc.edu.cn/v1/chat/completions"
    assert captured["authorization"] == "Bearer school-key-test-placeholder"
    assert captured["body"]["model"] == "cuc/deepseek"
    assert captured["body"]["stream"] is False
    assert captured["timeout"]["read"] == 120.0
    assert "thinking" not in captured["body"]
    assert "response_format" not in captured["body"]
    assert result.model == "cuc/deepseek"
    assert result.total_tokens == 20


def payload() -> dict:
    return deepcopy(json.loads(REQUEST_FIXTURE.read_text(encoding="utf-8")))


def build_test_app(tmp_path, provider: FakeProvider):
    settings = Settings(
        environment="test",
        database_path=tmp_path / "taplens-test.db",
        jwt_secret=TEST_SECRET,
    )
    app = create_app(settings)
    app.state.ai_provider = provider
    app.state.database.initialize()
    return app


def register_and_login(app) -> str:
    credentials = {"username": "Ai_Test_User", "password": "correct-horse"}
    assert request(app, "POST", "/api/v1/auth/register", json=credentials).status_code == 201
    response = request(app, "POST", "/api/v1/auth/login", json=credentials)
    assert response.status_code == 200
    return response.json()["access_token"]


def request(app, method: str, path: str, *, token: str | None = None, **kwargs) -> Response:
    async def send() -> Response:
        headers = kwargs.pop("headers", {})
        if token is not None:
            headers["Authorization"] = f"Bearer {token}"
        transport = ASGITransport(app=app)
        async with AsyncClient(transport=transport, base_url="http://testserver") as client:
            return await client.request(method, path, headers=headers, **kwargs)

    return asyncio.run(send())
