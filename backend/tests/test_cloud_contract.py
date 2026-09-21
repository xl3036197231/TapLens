from copy import deepcopy
import json
from pathlib import Path
from typing import Any

import pytest
from jsonschema import Draft202012Validator, FormatChecker


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
SCHEMA_PATH = REPOSITORY_ROOT / "shared/contracts/cloud-evidence.schema.json"
EXAMPLE_PATH = REPOSITORY_ROOT / "shared/contracts/cloud-evidence.example.json"
FIXTURE_DIRECTORY = REPOSITORY_ROOT / "shared/fixtures/cloud"


def load_json(path: Path) -> Any:
    return json.loads(path.read_text(encoding="utf-8"))


def validator() -> Draft202012Validator:
    schema = load_json(SCHEMA_PATH)
    Draft202012Validator.check_schema(schema)
    return Draft202012Validator(schema, format_checker=FormatChecker())


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
