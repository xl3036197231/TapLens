"""Validate D report fixtures against the merged A/B/C contract set.

This is a contract/fixture check only. It does not call an AI service.
The jsonschema package is part of backend[dev].
"""

from __future__ import annotations

import json
import sys
from pathlib import Path
from typing import Any

from jsonschema import Draft202012Validator, FormatChecker
from referencing import Registry, Resource


ROOT = Path(__file__).resolve().parents[3]
CONTRACTS = ROOT / "shared" / "contracts"
REPORTS = ROOT / "shared" / "fixtures" / "reports"
AI_FIXTURES = ROOT / "shared" / "fixtures" / "ai"


def schema_registry() -> Registry:
    registry = Registry()
    for path in CONTRACTS.glob("*.schema.json"):
        schema = load_json(path)
        registry = registry.with_resource(schema["$id"], Resource.from_contents(schema))
    return registry


def load_json(path: Path) -> Any:
    with path.open(encoding="utf-8") as handle:
        return json.load(handle)


def validator_for(path: Path) -> Draft202012Validator:
    schema = load_json(path)
    return Draft202012Validator(schema, registry=schema_registry(), format_checker=FormatChecker())


def errors_for(validator: Draft202012Validator, instance: Any) -> list[str]:
    errors = sorted(validator.iter_errors(instance), key=lambda error: list(error.path))
    return [f"{'.'.join(map(str, error.path)) or '<root>'}: {error.message}" for error in errors]


def validate_json(validator: Draft202012Validator, path: Path) -> None:
    errors = errors_for(validator, load_json(path))
    if errors:
        raise AssertionError(f"{path.relative_to(ROOT)}\n" + "\n".join(errors))


def main() -> int:
    local_example = load_json(CONTRACTS / "local-evidence.example.json")
    cloud_example = load_json(CONTRACTS / "cloud-evidence.example.json")
    local_ids = {item["id"] for item in local_example["evidence"]}
    cloud_ids = {item["id"] for item in cloud_example["evidence"]}
    known_ids = local_ids | cloud_ids

    validate_json(validator_for(CONTRACTS / "local-evidence.schema.json"), CONTRACTS / "local-evidence.example.json")
    validate_json(validator_for(CONTRACTS / "cloud-evidence.schema.json"), CONTRACTS / "cloud-evidence.example.json")
    report_validator = validator_for(CONTRACTS / "analysis-report.schema.json")

    failures: list[str] = []
    report_paths = sorted(REPORTS.glob("*.json")) + [AI_FIXTURES / "mock-success-report.json"]
    for report_path in report_paths:
        report = load_json(report_path)
        schema_errors = errors_for(report_validator, report)
        if schema_errors:
            failures.append(f"{report_path.name}: schema\n" + "\n".join(schema_errors))
            continue

        evidence = {item["id"]: item for item in report["evidence"]}
        if len(evidence) != len(report["evidence"]):
            failures.append(f"{report_path.name}: duplicate evidence id")

        references = list(report["observed_behavior"]["evidence_ids"])
        references.extend(ref for item in report["differences"] for ref in item["evidence_ids"])
        missing = sorted(set(references) - set(evidence))
        if missing:
            failures.append(f"{report_path.name}: missing report evidence {missing}")

        difference_ids = [item["id"] for item in report["differences"]]
        if len(set(difference_ids)) != len(difference_ids):
            failures.append(f"{report_path.name}: duplicate difference id")

        token_usage = report["token_usage"]
        if not report["sources"]["ai"] and token_usage["request_count"] != 0:
            failures.append(f"{report_path.name}: sources.ai=false requires request_count=0")

        for item in report["evidence"]:
            evidence_id = item["id"]
            if evidence_id not in known_ids:
                failures.append(f"{report_path.name}: unknown merged evidence id {evidence_id}")
            if evidence_id.startswith("L") and item["source"] != "local":
                failures.append(f"{report_path.name}: {evidence_id} must use source=local")
            if evidence_id.startswith("C") and item["source"] != "cloud":
                failures.append(f"{report_path.name}: {evidence_id} must use source=cloud")

    if failures:
        print("REPORT CONTRACT CHECK FAILED")
        print("\n".join(failures))
        return 1

    print("REPORT CONTRACT CHECK PASSED")
    print(f"local evidence ids: {sorted(local_ids)}")
    print(f"cloud evidence ids: {sorted(cloud_ids)}")
    print(f"reports checked: {len(report_paths)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
