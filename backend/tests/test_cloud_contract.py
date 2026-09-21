from copy import deepcopy
import json
from pathlib import Path
from typing import Any

import pytest
from jsonschema import Draft202012Validator, FormatChecker
from referencing import Registry, Resource


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
SCHEMA_PATH = REPOSITORY_ROOT / "shared/contracts/cloud-evidence.schema.json"
COMMON_SCHEMA_PATH = REPOSITORY_ROOT / "shared/contracts/common.schema.json"
EXAMPLE_PATH = REPOSITORY_ROOT / "shared/contracts/cloud-evidence.example.json"
FIXTURE_DIRECTORY = REPOSITORY_ROOT / "shared/fixtures/cloud"


def load_json(path: Path) -> Any:
    return json.loads(path.read_text(encoding="utf-8"))


def validator() -> Draft202012Validator:
    schema = load_json(SCHEMA_PATH)
    common_schema = load_json(COMMON_SCHEMA_PATH)
    Draft202012Validator.check_schema(schema)
    registry = Registry().with_resource(
        common_schema["$id"],
        Resource.from_contents(common_schema),
    )
    return Draft202012Validator(
        schema,
        registry=registry,
        format_checker=FormatChecker(),
    )


@pytest.mark.parametrize(
    "document_path",
    [
        EXAMPLE_PATH,
        FIXTURE_DIRECTORY / "case01-cloud-running.json",
        FIXTURE_DIRECTORY / "case01-cloud-succeeded.json",
        FIXTURE_DIRECTORY / "case01-cloud-failed.json",
    ],
)
def test_cloud_evidence_fixture_matches_schema(document_path: Path) -> None:
    document = load_json(document_path)
    errors = sorted(validator().iter_errors(document), key=lambda error: list(error.path))

    assert errors == [], "\n".join(error.message for error in errors)


def test_cloud_evidence_rejects_invalid_evidence_id() -> None:
    document = deepcopy(load_json(EXAMPLE_PATH))
    document["evidence"][0]["id"] = "L01"

    errors = list(validator().iter_errors(document))

    assert any("does not match" in error.message for error in errors)


def test_failed_cloud_evidence_requires_error_object() -> None:
    document = deepcopy(load_json(FIXTURE_DIRECTORY / "case01-cloud-failed.json"))
    document["error"] = None

    errors = list(validator().iter_errors(document))

    assert errors


def test_cloud_evidence_rejects_non_http_target() -> None:
    document = deepcopy(load_json(EXAMPLE_PATH))
    document["initial_url"] = "file:///etc/passwd"

    errors = list(validator().iter_errors(document))

    assert any("does not match" in error.message for error in errors)


def test_successful_cloud_evidence_cannot_include_error() -> None:
    document = deepcopy(load_json(EXAMPLE_PATH))
    document["error"] = {
        "code": "CLOUD_TASK_TIMEOUT",
        "message": "不应出现在成功响应中",
        "retryable": True,
        "details": None,
    }

    errors = list(validator().iter_errors(document))

    assert errors
