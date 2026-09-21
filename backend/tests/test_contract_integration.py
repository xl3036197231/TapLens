import json
from pathlib import Path

import pytest
from jsonschema import Draft202012Validator, FormatChecker
from referencing import Registry, Resource


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
CONTRACT_DIRECTORY = REPOSITORY_ROOT / "shared/contracts"
REPORT_FIXTURE_DIRECTORY = REPOSITORY_ROOT / "shared/fixtures/reports"
HTTP_FIXTURE_DIRECTORY = REPOSITORY_ROOT / "shared/fixtures/http"
LOCAL_SCHEMA_PATH = CONTRACT_DIRECTORY / "local-evidence.schema.json"
LOCAL_EXAMPLE_PATH = CONTRACT_DIRECTORY / "local-evidence.example.json"


def load_json(path: Path):
    return json.loads(path.read_text(encoding="utf-8"))


def common_registry() -> Registry:
    common = load_json(CONTRACT_DIRECTORY / "common.schema.json")
    return Registry().with_resource(common["$id"], Resource.from_contents(common))


def validator(schema_name: str) -> Draft202012Validator:
    schema = load_json(CONTRACT_DIRECTORY / schema_name)
    Draft202012Validator.check_schema(schema)
    return Draft202012Validator(
        schema,
        registry=common_registry(),
        format_checker=FormatChecker(),
    )


@pytest.mark.parametrize(
    "report_path",
    [
        CONTRACT_DIRECTORY / "analysis-report.example.json",
        *sorted(REPORT_FIXTURE_DIRECTORY.glob("*.json")),
    ],
)
def test_report_contract_and_semantics(report_path: Path) -> None:
    report = load_json(report_path)
    errors = list(validator("analysis-report.schema.json").iter_errors(report))
    assert errors == [], "\n".join(error.message for error in errors)

    evidence = {item["id"]: item for item in report["evidence"]}
    assert len(evidence) == len(report["evidence"]), "report evidence ids must be unique"
    references = set(report["observed_behavior"]["evidence_ids"])
    references.update(
        evidence_id
        for difference in report["differences"]
        for evidence_id in difference["evidence_ids"]
    )
    assert references <= evidence.keys()
    assert all(
        (item["id"].startswith("L") and item["source"] == "local")
        or (item["id"].startswith("C") and item["source"] == "cloud")
        for item in evidence.values()
    )
    assert report["sources"]["local"] is any(key.startswith("L") for key in evidence)
    assert report["sources"]["cloud"] is any(key.startswith("C") for key in evidence)

    usage = report["token_usage"]
    assert usage["total_tokens"] == usage["prompt_tokens"] + usage["completion_tokens"]
    if usage["request_count"] == 0:
        assert usage["total_tokens"] == 0
        assert usage["model"] is None
    else:
        assert usage["model"] is not None
    assert report["sources"]["ai"] is (usage["request_count"] == 1)

    if report["risk_level"] == "insufficient_evidence":
        assert report["uncertainty"]["status"] == "insufficient"


@pytest.mark.parametrize(
    "response_path",
    sorted(HTTP_FIXTURE_DIRECTORY.glob("deep-scan-*.response.json")),
)
def test_http_cloud_evidence_identity_and_report_projection(response_path: Path) -> None:
    response = load_json(response_path)
    cloud_evidence = response["cloud_evidence"]
    if cloud_evidence is None:
        return
    assert cloud_evidence["analysis_id"] == response["analysis_id"]
    assert cloud_evidence["task_id"] == response["task_id"]
    assert cloud_evidence["status"] == response["status"]

    report_validator = validator("analysis-report.schema.json")
    report = load_json(REPORT_FIXTURE_DIRECTORY / "high-risk.json")
    report["analysis_id"] = response["analysis_id"]
    report["evidence"] = [
        {
            "id": item["id"],
            "source": "cloud",
            "title": item["title"],
            "detail": item["detail"],
        }
        for item in cloud_evidence["evidence"]
    ]
    report["observed_behavior"]["evidence_ids"] = [item["id"] for item in report["evidence"]]
    report["differences"] = []
    report["sources"] = {"local": False, "cloud": True, "ai": False}
    assert list(report_validator.iter_errors(report)) == []


@pytest.mark.skipif(
    not (LOCAL_SCHEMA_PATH.exists() and LOCAL_EXAMPLE_PATH.exists()),
    reason="C has not yet supplied local-evidence schema and example",
)
def test_c_local_evidence_contract_after_merge() -> None:
    local = load_json(LOCAL_EXAMPLE_PATH)
    errors = list(validator("local-evidence.schema.json").iter_errors(local))
    assert errors == [], "\n".join(error.message for error in errors)
