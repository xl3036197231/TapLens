"""Audit B's captured cloud evidence and C's current Day 2 local fixtures.

Until C's branch is merged, C inputs are read from the fetched remote ref.
They are never combined with B's separate analysis ID.
"""

from __future__ import annotations

import json
import subprocess
from pathlib import Path

from jsonschema import Draft202012Validator, FormatChecker
from referencing import Registry, Resource


ROOT = Path(__file__).resolve().parents[3]
CONTRACTS = ROOT / "shared" / "contracts"
C_REF = "origin/feat/c-day2-device-validation"
C_FILES = (
    "case01-local-succeeded.json",
    "case03-local-url-succeeded.json",
    "case04-local-custom-scheme-succeeded.json",
    "case05-local-invalid-intent.json",
    "case06-local-missing-scheme.json",
    "case07-local-insufficient-succeeded.json",
)


def read_json(path: str) -> dict:
    local = ROOT / path
    if local.exists():
        return json.loads(local.read_text(encoding="utf-8"))
    output = subprocess.run(
        ["git", "show", f"{C_REF}:{path}"],
        cwd=ROOT,
        text=True,
        encoding="utf-8",
        capture_output=True,
        check=True,
    )
    return json.loads(output.stdout)


def validator_for(schema: dict, *, local_override: dict | None = None) -> Draft202012Validator:
    registry = Registry()
    for path in CONTRACTS.glob("*.schema.json"):
        current = json.loads(path.read_text(encoding="utf-8"))
        if path.name == "local-evidence.schema.json" and local_override is not None:
            current = local_override
        registry = registry.with_resource(current["$id"], Resource.from_contents(current))
    return Draft202012Validator(schema, registry=registry, format_checker=FormatChecker())


def assert_schema(validator: Draft202012Validator, item: dict, label: str) -> None:
    errors = sorted(validator.iter_errors(item), key=lambda error: str(error.path))
    assert not errors, f"{label}: " + "; ".join(error.message for error in errors)


def main() -> None:
    local_schema = read_json("shared/contracts/local-evidence.schema.json")
    # main still carries the Day 1 local schema; use C's branch contract when
    # reading its Day 2 fixtures before that branch is merged.
    if "risk_hints" not in local_schema.get("properties", {}):
        output = subprocess.run(
            ["git", "show", f"{C_REF}:shared/contracts/local-evidence.schema.json"],
            cwd=ROOT,
            text=True,
            encoding="utf-8",
            capture_output=True,
            check=True,
        )
        local_schema = json.loads(output.stdout)
    local_validator = validator_for(local_schema, local_override=local_schema)
    local_ids = set()
    local_by_name = {}
    for name in C_FILES:
        item = read_json(f"shared/fixtures/local/{name}")
        local_by_name[name] = item
        assert_schema(local_validator, item, name)
        assert item["analysis_id"] not in local_ids, f"duplicate analysis_id: {name}"
        local_ids.add(item["analysis_id"])
        evidence_ids = {evidence["id"] for evidence in item["evidence"]}
        assert len(evidence_ids) == len(item["evidence"]), f"duplicate Lxx: {name}"
        for hint in item["risk_hints"]:
            assert set(hint["evidence_ids"]) <= evidence_ids, f"unknown Lxx: {name}"
        assert item["observations"]["launched_external_app"] is False
        assert item["observations"]["network_accessed"] is False
        assert item["preflight"]["status"] == "not_started"
        if item["processing_status"] == "failed":
            assert not evidence_ids, f"failed parse has Lxx: {name}"

    cloud = read_json("shared/fixtures/cloud/day2-short-link-succeeded.json")
    report = read_json("shared/fixtures/reports/day3-short-link-verified.json")
    cloud_schema = read_json("shared/contracts/cloud-evidence.schema.json")
    report_schema = read_json("shared/contracts/analysis-report.schema.json")
    assert_schema(validator_for(cloud_schema), cloud, "B cloud snapshot")
    assert_schema(validator_for(report_schema), report, "D verified report")
    local_report = read_json("shared/fixtures/reports/day3-local-static-insufficient.json")
    assert_schema(validator_for(report_schema), local_report, "D local-only report")
    url_scan = local_by_name["case03-local-url-succeeded.json"]
    static_only = local_by_name["case07-local-insufficient-succeeded.json"]
    assert static_only["processing_status"] == "succeeded"
    assert [item["id"] for item in static_only["evidence"]] == ["L01"]
    assert any(hint["risk_level"] == "insufficient_evidence" for hint in static_only["risk_hints"])
    assert local_report["analysis_id"] == url_scan["analysis_id"]
    assert local_report["target"]["display"] == url_scan["target"]["display_value"]
    assert local_report["risk_level"] == "insufficient_evidence"
    assert local_report["uncertainty"]["status"] == "insufficient"
    assert [entry["id"] for entry in local_report["evidence"]] == ["L01"]
    assert local_report["evidence"][0]["title"] == url_scan["evidence"][0]["title"]
    assert local_report["evidence"][0]["detail"] == url_scan["evidence"][0]["detail"]
    by_id = {entry["id"]: entry for entry in cloud["evidence"]}
    assert list(by_id) == ["C01", "C02", "C03", "C04"]
    assert report["analysis_id"] == cloud["analysis_id"]
    assert report["target"]["display"] == cloud["initial_url"]
    assert {entry["id"] for entry in report["evidence"]} == set(by_id)
    for entry in report["evidence"]:
        actual = by_id[entry["id"]]
        assert (entry["title"], entry["detail"]) == (
            actual["title"], actual["detail"]
        )
    refs = set(report["observed_behavior"]["evidence_ids"])
    refs.update(evidence_id for diff in report["differences"] for evidence_id in diff["evidence_ids"])
    assert refs <= set(by_id)
    assert cloud["analysis_id"] not in local_ids, "B and C fixtures must remain separate analyses"

    print(f"DAY 3 EVIDENCE CHECK PASSED: C local={len(C_FILES)}, B cloud=C01-C04, report={len(refs)} references")
    print("C fixtures are separate scans; their Lxx cannot be attached to B's report yet.")


if __name__ == "__main__":
    main()
