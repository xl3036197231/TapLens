#!/usr/bin/env python3
"""Validate the 30-case acceptance matrix without running its test cases."""

from __future__ import annotations

import argparse
import json
import re
from pathlib import Path

HERE = Path(__file__).resolve().parent
REPO_ROOT = HERE.parents[2]
EXPECTED_AREAS = {"qr_safe_preview": 11, "deep_link_static": 10, "ai_and_report": 9}
EXPECTED_LEVELS = {"device", "automated"}


def validate(matrix_path: Path, *, check_files: bool = False, repo_root: Path = REPO_ROOT) -> list[str]:
    errors: list[str] = []
    try:
        matrix = json.loads(matrix_path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        return [f"Cannot read matrix: {exc}"]
    if not isinstance(matrix, dict) or matrix.get("schema_version") != "1.0":
        return ["Matrix must be a version 1.0 JSON object."]
    if not re.fullmatch(r"[0-9a-f]{40}", str(matrix.get("baseline_commit", ""))):
        errors.append("baseline_commit must be a full Git SHA.")
    cases = matrix.get("cases")
    if not isinstance(cases, list) or len(cases) != 30:
        return errors + ["Exactly 30 cases are required."]
    counts = {area: 0 for area in EXPECTED_AREAS}
    seen_sources: set[tuple[str, str]] = set()
    for index, case in enumerate(cases, 1):
        label = f"D30-{index:02d}"
        if not isinstance(case, dict):
            errors.append(f"{label}: case must be an object.")
            continue
        if case.get("case_id") != label:
            errors.append(f"{label}: case IDs must be unique and sequential.")
        area = case.get("area")
        if area not in EXPECTED_AREAS:
            errors.append(f"{label}: unknown area.")
        else:
            counts[area] += 1
        if case.get("run_level") not in EXPECTED_LEVELS:
            errors.append(f"{label}: run_level must be device or automated.")
        for field in ("procedure",):
            if not isinstance(case.get(field), str) or not case[field].strip():
                errors.append(f"{label}: {field} is required.")
        if not isinstance(case.get("expected"), dict) or not case["expected"]:
            errors.append(f"{label}: expected result is required.")
        capture = case.get("capture")
        if not isinstance(capture, list) or not capture or not all(isinstance(x, str) and x.strip() for x in capture):
            errors.append(f"{label}: evidence capture list is required.")
        source = case.get("source")
        if not isinstance(source, dict) or not isinstance(source.get("path"), str):
            errors.append(f"{label}: source path is required.")
            continue
        path = Path(source["path"])
        if path.is_absolute() or ".." in path.parts or not path.parts:
            errors.append(f"{label}: source must be a repository-relative path.")
            continue
        discriminator = source.get("fixture_id") or source.get("check")
        if not isinstance(discriminator, str) or not discriminator:
            if label != "D30-30":
                errors.append(f"{label}: fixture_id or check is required.")
        else:
            key = (source["path"], discriminator)
            if key in seen_sources:
                errors.append(f"{label}: duplicate source case.")
            seen_sources.add(key)
        if not check_files:
            continue
        actual_path = repo_root / path
        if not actual_path.is_file():
            errors.append(f"{label}: source file missing: {path}")
            continue
        try:
            content = actual_path.read_text(encoding="utf-8")
            if source.get("check") and source["check"] not in content:
                errors.append(f"{label}: source check text missing.")
            if source.get("fixture_id"):
                fixture = json.loads(content)
                items = fixture if isinstance(fixture, list) else fixture.get("cases", [])
                if not any(isinstance(item, dict) and item.get("id") == source["fixture_id"] for item in items):
                    errors.append(f"{label}: fixture ID missing.")
        except (OSError, json.JSONDecodeError) as exc:
            errors.append(f"{label}: could not verify source: {exc}")
    if counts != EXPECTED_AREAS:
        errors.append(f"Area counts differ: {counts!r}")
    return errors


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check-files", action="store_true", help="Verify each referenced fixture or source file in a full checkout.")
    parser.add_argument("--repo-root", type=Path, default=REPO_ROOT)
    args = parser.parse_args()
    errors = validate(args.repo_root / "shared/datasets/acceptance/matrix.json", check_files=args.check_files, repo_root=args.repo_root)
    if errors:
        for error in errors:
            print(f"FAIL: {error}")
        return 1
    print("PASS: 30 unique cases, expected area counts, procedures, results, and evidence capture fields.")
    if args.check_files:
        print("PASS: all referenced source files, fixture IDs, and test markers exist.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
