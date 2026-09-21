import json
from pathlib import Path

import pytest
from jsonschema import Draft202012Validator, FormatChecker

from app.tasks.schemas import DeepScanTaskResponse


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
HTTP_FIXTURE_DIRECTORY = REPOSITORY_ROOT / "shared/fixtures/http"
CLOUD_SCHEMA_PATH = REPOSITORY_ROOT / "shared/contracts/cloud-evidence.schema.json"


@pytest.mark.parametrize(
    "fixture_path",
    sorted(HTTP_FIXTURE_DIRECTORY.glob("deep-scan-*.response.json")),
)
def test_deep_scan_http_fixture_matches_models_and_contract(fixture_path: Path) -> None:
    document = json.loads(fixture_path.read_text(encoding="utf-8"))
    DeepScanTaskResponse.model_validate(document)

    cloud_evidence = document["cloud_evidence"]
    if cloud_evidence is None:
        return
    schema = json.loads(CLOUD_SCHEMA_PATH.read_text(encoding="utf-8"))
    errors = list(
        Draft202012Validator(
            schema,
            format_checker=FormatChecker(),
        ).iter_errors(cloud_evidence)
    )
    assert errors == [], "\n".join(error.message for error in errors)
