import json
import os
import re
import shutil
import subprocess
from pathlib import Path

import pytest


ROOT = Path(__file__).resolve().parents[2]
COMMON_SCRIPT = ROOT / "deploy/scripts/_common.sh"


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


def test_deployment_scripts_check_the_resolved_timeout() -> None:
    common = (ROOT / "deploy/scripts/_common.sh").read_text(encoding="utf-8")
    status = (ROOT / "deploy/scripts/status.sh").read_text(encoding="utf-8")

    assert 'validate_llm_timeout_env "$ENV_FILE"' in common
    assert "config --format json" in common
    assert "validate_resolved_compose_llm_timeout" in common
    assert "settings.llm_enabled and settings.llm_timeout_seconds != 120" in status


@pytest.mark.parametrize(
    ("enabled", "timeout", "accepted"),
    (
        ("true", "60", False),
        ('"true"', "60", False),
        ("'true'", "60", False),
        ("TRUE", "60", False),
        ("1", "60", False),
        ("on", "60", False),
        ('"true" # compose comment', '"120"', True),
        ("yes", "120.0", True),
        ('"false"', "60", True),
        ("not-a-boolean", "120", False),
    ),
)
def test_llm_timeout_preflight_matches_compose_boolean_forms(
    tmp_path: Path,
    enabled: str,
    timeout: str,
    accepted: bool,
) -> None:
    env_file = tmp_path / ".env"
    env_file.write_text(
        f"TAPLENS_LLM_ENABLED={enabled}\n"
        f"TAPLENS_LLM_TIMEOUT_SECONDS={timeout}\n",
        encoding="utf-8",
    )

    result = subprocess.run(
        [
            "bash",
            "-c",
            'source "$1"; validate_llm_timeout_env "$2"',
            "taplens-timeout-test",
            str(COMMON_SCRIPT),
            str(env_file),
        ],
        check=False,
        capture_output=True,
        text=True,
    )

    assert (result.returncode == 0) is accepted
    assert "TAPLENS_LLM_API_KEY" not in result.stdout + result.stderr


@pytest.mark.parametrize(
    ("enabled_line", "timeout_line", "accepted"),
    (
        ('TAPLENS_LLM_ENABLED: "true"', "TAPLENS_LLM_TIMEOUT_SECONDS: 60", False),
        ("TAPLENS_LLM_ENABLED:true", "TAPLENS_LLM_TIMEOUT_SECONDS:120", True),
        ("TAPLENS_LLM_ENABLED: yes", 'TAPLENS_LLM_TIMEOUT_SECONDS: "120"', True),
        ("TAPLENS_LLM_ENABLED: false", "TAPLENS_LLM_TIMEOUT_SECONDS: 60", True),
        ("export TAPLENS_LLM_ENABLED: true", "export TAPLENS_LLM_TIMEOUT_SECONDS: 60", False),
        ("export TAPLENS_LLM_ENABLED=true", "export TAPLENS_LLM_TIMEOUT_SECONDS=120", True),
    ),
)
def test_llm_timeout_preflight_supports_compose_colon_separator(
    tmp_path: Path,
    enabled_line: str,
    timeout_line: str,
    accepted: bool,
) -> None:
    env_file = tmp_path / ".env"
    env_file.write_text(f"{enabled_line}\n{timeout_line}\n", encoding="utf-8")

    result = subprocess.run(
        [
            "bash",
            "-c",
            'source "$1"; validate_llm_timeout_env "$2"',
            "taplens-colon-timeout-test",
            str(COMMON_SCRIPT),
            str(env_file),
        ],
        check=False,
        capture_output=True,
        text=True,
    )

    assert (result.returncode == 0) is accepted


@pytest.mark.parametrize(
    ("enabled", "timeout", "accepted"),
    (
        (True, "60", False),
        ("true", "120", True),
        ("yes", "120.0", True),
        (False, "60", True),
        ("invalid", "120", False),
    ),
)
def test_resolved_compose_json_has_an_authoritative_second_gate(
    enabled: object,
    timeout: object,
    accepted: bool,
) -> None:
    config = {
        "services": {
            "api": {
                "environment": {
                    "TAPLENS_LLM_ENABLED": enabled,
                    "TAPLENS_LLM_TIMEOUT_SECONDS": timeout,
                    "TAPLENS_LLM_API_KEY": "test-only-secret-must-not-be-printed",
                }
            }
        }
    }
    result = subprocess.run(
        [
            "bash",
            "-c",
            'source "$1"; validate_resolved_compose_llm_timeout',
            "taplens-resolved-timeout-test",
            str(COMMON_SCRIPT),
        ],
        input=json.dumps(config),
        check=False,
        capture_output=True,
        text=True,
    )

    assert (result.returncode == 0) is accepted
    assert "test-only-secret-must-not-be-printed" not in result.stdout + result.stderr


@pytest.mark.parametrize(
    ("prefix", "separator"),
    (("", "="), ("", ": "), ("export ", "="), ("export ", ": ")),
)
def test_update_stops_before_compose_up_for_quoted_true_with_old_timeout(
    tmp_path: Path,
    prefix: str,
    separator: str,
) -> None:
    project = tmp_path / "project"
    scripts = project / "deploy/scripts"
    scripts.mkdir(parents=True)
    shutil.copy2(COMMON_SCRIPT, scripts / "_common.sh")
    shutil.copy2(ROOT / "deploy/scripts/update.sh", scripts / "update.sh")
    (project / "deploy/.env").write_text(
        f'{prefix}TAPLENS_LLM_ENABLED{separator}"true"\n'
        f"{prefix}TAPLENS_LLM_TIMEOUT_SECONDS{separator}60\n",
        encoding="utf-8",
    )

    fake_bin = tmp_path / "bin"
    fake_bin.mkdir()
    docker_log = tmp_path / "docker.log"
    fake_docker = fake_bin / "docker"
    fake_docker.write_text(
        '#!/usr/bin/env bash\nprintf "%s\\n" "$*" >>"$TAPLENS_DOCKER_LOG"\n',
        encoding="utf-8",
    )
    fake_docker.chmod(0o755)
    environment = os.environ.copy()
    environment["PATH"] = f"{fake_bin}:{environment['PATH']}"
    environment["TAPLENS_DOCKER_LOG"] = str(docker_log)

    result = subprocess.run(
        ["bash", str(scripts / "update.sh")],
        check=False,
        capture_output=True,
        text=True,
        env=environment,
    )

    assert result.returncode != 0
    assert "requires TAPLENS_LLM_TIMEOUT_SECONDS=120" in result.stderr
    assert docker_log.read_text(encoding="utf-8").splitlines() == [
        "compose version"
    ]
