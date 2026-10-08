import re
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]


def test_nginx_waits_longer_than_the_maximum_provider_timeout() -> None:
    config = (ROOT / "deploy/nginx/default.conf").read_text(encoding="utf-8")
    match = re.search(r"^\s*proxy_read_timeout\s+(\d+)s;", config, re.MULTILINE)

    assert match is not None
    assert int(match.group(1)) == 135
    assert int(match.group(1)) > 120


def test_deployment_example_uses_the_reviewed_provider_timeout() -> None:
    readme = (ROOT / "deploy/README.md").read_text(encoding="utf-8")
    example = (ROOT / "deploy/.env.example").read_text(encoding="utf-8")

    assert "TAPLENS_LLM_TIMEOUT_SECONDS=120" in readme
    assert "TAPLENS_LLM_TIMEOUT_SECONDS=120" in example


def test_deployment_scripts_fail_closed_on_an_old_enabled_timeout() -> None:
    common = (ROOT / "deploy/scripts/_common.sh").read_text(encoding="utf-8")
    status = (ROOT / "deploy/scripts/status.sh").read_text(encoding="utf-8")

    assert '"$llm_enabled" == "true" && "$llm_timeout" != "120"' in common
    assert "settings.llm_enabled and settings.llm_timeout_seconds != 120" in status
