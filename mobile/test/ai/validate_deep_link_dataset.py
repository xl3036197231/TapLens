"""Check D's shared Deep Link dataset before A/B/C consume it."""

from __future__ import annotations

import json
import re
from pathlib import Path
from urllib.parse import urlparse


ROOT = Path(__file__).resolve().parents[3]
DATASETS = ROOT / "shared" / "datasets"
PUBLIC = DATASETS / "public-cases" / "deep-link-cases.json"
FIXTURES = DATASETS / "constructed-fixtures" / "deep-link-fixtures.json"
EVALUATION = DATASETS / "evaluation" / "deep-link-evaluation.json"
REQUIRED_CATEGORIES = {
    "normal_deep_link",
    "scheme_impersonation",
    "package_mismatch",
    "fallback_destination",
    "sensitive_extra",
    "malformed_intent",
    "unverified_web_link",
}
ALLOWED_CLOUD_OBSERVATIONS = {
    "skip_non_http",
    "skip_unmapped_fallback",
    "skip_invalid_input",
    "controlled_site_mapping_required",
}


def load(path: Path) -> list[dict]:
    with path.open(encoding="utf-8") as handle:
        rows = json.load(handle)
    assert isinstance(rows, list) and rows, f"{path}: expected a nonempty JSON array"
    return rows


def expected_local_ids(row: dict) -> list[str]:
    parsed = row["expected_parse"]
    if parsed["status"] == "failed":
        return []
    count = 1
    count += parsed["package_name"] is not None
    count += parsed["fallback_url"] is not None
    count += bool(parsed["parameter_names"] or parsed["extra_names"])
    return [f"L{index:02d}" for index in range(1, count + 1)]


def check() -> tuple[int, int, int]:
    public = load(PUBLIC)
    fixtures = load(FIXTURES)
    evaluation = load(EVALUATION)
    all_rows = [*public, *fixtures, *evaluation]
    ids = [row["id"] for row in all_rows]
    assert len(ids) == len(set(ids)), "dataset IDs must be unique"
    public_ids = {row["id"] for row in public}
    fixture_ids = {row["id"] for row in fixtures}

    for row in public:
        assert re.fullmatch(r"PUB-DL-\d{3}", row["id"])
        assert row["record_type"] in {"published_research", "published_case", "platform_documentation", "security_guidance"}
        assert row["source_url"].startswith("https://")
        assert row["source_location"] and row["behavior_summary"]
        assert row["real_target_or_exploit_included"] is False
        assert set(row["derived_fixture_ids"]) <= fixture_ids

    fixtures_by_id = {row["id"]: row for row in fixtures}
    for row in public:
        assert all(row["id"] in fixtures_by_id[fixture_id]["public_case_ids"]
                   for fixture_id in row["derived_fixture_ids"]), f"{row['id']}: reverse source mapping"

    assert REQUIRED_CATEGORIES <= {row["category"] for row in fixtures}
    fixture_inputs = {row["input"] for row in fixtures}
    assert not fixture_inputs.intersection(row["input"] for row in evaluation), "evaluation inputs must be held out"

    for row in [*fixtures, *evaluation]:
        prefix = "FIX" if row in fixtures else "EVAL"
        assert re.fullmatch(rf"{prefix}-DL-\d{{3}}", row["id"])
        if prefix == "FIX":
            assert set(row["public_case_ids"]) <= public_ids
            assert all(row["id"] in next(case["derived_fixture_ids"] for case in public if case["id"] == case_id)
                       for case_id in row["public_case_ids"]), f"{row['id']}: reverse fixture mapping"
        assert row["reproduction"]
        assert row["expected_local_ids"] == expected_local_ids(row), f"{row['id']}: local ID order"
        assert row["cloud_observation"] in ALLOWED_CLOUD_OBSERVATIONS
        assert row["expected_risk_label"] in {"low", "medium", "high", "insufficient_evidence"}
        assert row["input"].isascii() and len(row["input"]) <= 4096
        assert not any(secret in row["input"].lower() for secret in ("sk-", "bearer ", "password=", "token="))
        assert row["expected_package_name"] is None or row["expected_package_name"].startswith("org.example.")

        parsed = row["expected_parse"]
        assert parsed["status"] in {"succeeded", "failed"}
        if parsed["status"] == "failed":
            assert row["expected_risk_label"] == "insufficient_evidence"
            assert row["expected_local_ids"] == []
            assert row["expected_local_risk_hints"] == ["LOCAL_PARSE_FAILED"]
        else:
            assert "LOCAL_STATIC_ONLY" in row["expected_local_risk_hints"]
            if parsed["input_type"] == "intent":
                assert row["input"].startswith("intent://") and row["input"].endswith(";end")
            if parsed["input_type"] == "url":
                assert urlparse(row["input"]).scheme == "https"
                assert row["input"].endswith("/go/campus")
        if row["cloud_observation"] == "controlled_site_mapping_required":
            assert row["id"] == "FIX-DL-007"
            assert row["expected_cloud_ids"] == ["C01", "C02"]
        else:
            assert row["expected_cloud_ids"] == []

    assert len([row for row in public if row["record_type"] in {"published_research", "published_case"}]) >= 2
    return len(public), len(fixtures), len(evaluation)


if __name__ == "__main__":
    counts = check()
    print(f"DEEP LINK DATASET CHECK PASSED: public={counts[0]}, fixtures={counts[1]}, evaluation={counts[2]}")
