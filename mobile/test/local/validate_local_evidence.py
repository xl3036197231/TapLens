"""Validate every committed C local-evidence example and fixture."""

from __future__ import annotations

import json
from pathlib import Path

from jsonschema import Draft202012Validator, FormatChecker
from referencing import Registry, Resource


ROOT = Path(__file__).resolve().parents[3]
CONTRACTS = ROOT / "shared" / "contracts"
LOCAL_FIXTURES = ROOT / "shared" / "fixtures" / "local"


def load_json(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


def main() -> None:
    registry = Registry()
    for path in CONTRACTS.glob("*.schema.json"):
        schema = load_json(path)
        registry = registry.with_resource(schema["$id"], Resource.from_contents(schema))

    local_schema = load_json(CONTRACTS / "local-evidence.schema.json")
    Draft202012Validator.check_schema(local_schema)
    validator = Draft202012Validator(
        local_schema,
        registry=registry,
        format_checker=FormatChecker(),
    )

    documents = [CONTRACTS / "local-evidence.example.json"]
    documents.extend(sorted(LOCAL_FIXTURES.glob("*.json")))
    failures: list[str] = []

    for path in documents:
        document = load_json(path)
        errors = sorted(validator.iter_errors(document), key=lambda item: list(item.path))
        if errors:
            failures.extend(f"{path.name}: {error.json_path}: {error.message}" for error in errors)
            continue

        evidence_ids = {item["id"] for item in document["evidence"]}
        referenced_ids = {
            evidence_id
            for hint in document["risk_hints"]
            for evidence_id in hint["evidence_ids"]
        }
        missing_ids = referenced_ids - evidence_ids
        if missing_ids:
            failures.append(f"{path.name}: missing evidence references {sorted(missing_ids)}")

        observations = document["observations"]
        if observations["launched_external_app"] is not False:
            failures.append(f"{path.name}: launched_external_app must remain false")
        preflight = document["preflight"]
        if preflight["attempted"] is False:
            if observations["network_accessed"] is not False:
                failures.append(f"{path.name}: static-only result must not access the network")
            if preflight["status"] != "not_started":
                failures.append(f"{path.name}: unattempted preflight must remain not_started")

    if failures:
        raise SystemExit("LOCAL EVIDENCE CHECK FAILED\n" + "\n".join(failures))

    print(f"LOCAL EVIDENCE CHECK PASSED: {len(documents)} documents")


if __name__ == "__main__":
    main()
