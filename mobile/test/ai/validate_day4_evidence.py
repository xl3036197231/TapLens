"""Audit one Day 4 report against evidence from the *same* analysis.

Examples:
  python mobile/test/ai/validate_day4_evidence.py --local local.json --report report.json
  python mobile/test/ai/validate_day4_evidence.py --local local.json --cloud cloud.json --report report.json --task-id UUID

The script prints IDs and a verdict only; never paste credentials into input JSON.
Historical B/C fixtures have different analysis IDs and must not be joined.
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path

from jsonschema import Draft202012Validator, FormatChecker
from referencing import Registry, Resource


ROOT = Path(__file__).resolve().parents[3]
CONTRACTS = ROOT / "shared" / "contracts"


def _schema_validator(name: str) -> Draft202012Validator:
    registry = Registry()
    for path in CONTRACTS.glob("*.schema.json"):
        schema = json.loads(path.read_text(encoding="utf-8"))
        registry = registry.with_resource(schema["$id"], Resource.from_contents(schema))
    schema = json.loads((CONTRACTS / name).read_text(encoding="utf-8"))
    return Draft202012Validator(schema, registry=registry, format_checker=FormatChecker())


def _require(condition: bool, message: str) -> None:
    if not condition:
        raise ValueError(message)


def _validate_schema(name: str, value: dict) -> None:
    errors = list(_schema_validator(name).iter_errors(value))
    _require(not errors, f"{name} failed Schema validation at {list(errors[0].path) if errors else []}")


def audit(local: dict, report: dict, cloud: dict | None = None, *, task_id: str | None = None) -> dict:
    """Return a non-sensitive summary or raise ValueError on any mismatch."""
    _validate_schema("local-evidence.schema.json", local)
    _validate_schema("analysis-report.schema.json", report)
    if cloud is not None:
        _validate_schema("cloud-evidence.schema.json", cloud)

    analysis_id = local["analysis_id"]
    _require(report["analysis_id"] == analysis_id, "report/local analysis_id mismatch")
    _require(local["processing_status"] == "succeeded", "local analysis did not succeed")
    _require(local["observations"]["launched_external_app"] is False, "local analysis launched an app")
    _require(local["observations"]["network_accessed"] is False, "local analysis accessed network")
    _require(local["preflight"]["status"] == "not_started", "local preflight unexpectedly ran")

    if cloud is not None:
        _require(cloud["analysis_id"] == analysis_id, "cloud/local analysis_id mismatch")
        _require(cloud["status"] == "succeeded", "cloud task did not succeed")
        if task_id is not None:
            _require(cloud["task_id"] == task_id, "cloud task_id mismatch")
        kinds = {item["id"]: item["kind"] for item in cloud["evidence"]}
        _require(
            all(kinds.get(eid) == kind for eid, kind in {
                "C01": "redirect", "C02": "form", "C03": "page", "C04": "screenshot"
            }.items()),
            "cloud C01-C04 kinds are incomplete or mismatched",
        )
        _require(bool(cloud["redirects"]), "C01 has no redirect observation")
        _require(
            any(field["sensitive"] for form in cloud["forms"] for field in form["fields"]),
            "C02 has no sensitive form-field observation",
        )
        _require(cloud["screenshot"] is not None, "C04 has no screenshot artifact")
        _require(
            not any(request["method"] == "POST" for request in cloud["requests"]),
            "cloud evidence contains a POST request",
        )

    source_items = {item["id"]: ("local", item) for item in local["evidence"]}
    if cloud is not None:
        for item in cloud["evidence"]:
            _require(item["id"] not in source_items, "duplicate Lxx/Cxx source ID")
            source_items[item["id"]] = ("cloud", item)
    _require(len(source_items) == len(local["evidence"]) + (len(cloud["evidence"]) if cloud else 0),
             "duplicate evidence source ID")

    report_items = {item["id"]: item for item in report["evidence"]}
    _require(len(report_items) == len(report["evidence"]), "duplicate report evidence ID")
    for eid, item in report_items.items():
        _require(eid in source_items, f"report references unavailable evidence ID {eid}")
        source, original = source_items[eid]
        _require(item["source"] == source, f"{eid} source mismatch")
        _require(
            item["title"] == original["title"] and item["detail"] == original["detail"],
            f"{eid} title/detail differs from source snapshot",
        )
    references = set(report["observed_behavior"]["evidence_ids"])
    for difference in report["differences"]:
        references.update(difference["evidence_ids"])
    _require(references <= report_items.keys(), "report conclusion references missing evidence")
    _require(report["sources"]["local"] is True, "report omits local source flag")
    _require(report["sources"]["cloud"] is (cloud is not None), "report cloud source flag mismatch")

    if cloud is None:
        _require(not any(eid.startswith("C") for eid in report_items), "local-only report contains Cxx")
        if local["target"]["input_type"] == "url" and set(source_items) == {"L01"}:
            _require(report["risk_level"] == "insufficient_evidence", "static-only URL cannot be called safe")
            _require(report["uncertainty"]["status"] == "insufficient", "static-only uncertainty mismatch")
    else:
        _require(report["risk_level"] == "high", "sensitive login case lost high risk")
        _require({"C01", "C02"} <= references, "high-risk conclusion must cite C01 and C02")
        _require({"C01", "C02", "C03", "C04"} <= report_items.keys(), "report omits cloud evidence")

    return {
        "analysis_id": analysis_id,
        "task_id": cloud["task_id"] if cloud else None,
        "local_ids": sorted(eid for eid in report_items if eid.startswith("L")),
        "cloud_ids": sorted(eid for eid in report_items if eid.startswith("C")),
    }


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--local", required=True, type=Path)
    parser.add_argument("--cloud", type=Path)
    parser.add_argument("--report", required=True, type=Path)
    parser.add_argument("--task-id")
    args = parser.parse_args()
    result = audit(
        json.loads(args.local.read_text(encoding="utf-8")),
        json.loads(args.report.read_text(encoding="utf-8")),
        json.loads(args.cloud.read_text(encoding="utf-8")) if args.cloud else None,
        task_id=args.task_id,
    )
    print("DAY 4 EVIDENCE AUDIT PASSED:", json.dumps(result, ensure_ascii=False))


if __name__ == "__main__":
    main()
