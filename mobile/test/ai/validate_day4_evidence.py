"""Audit one Day 4 report against evidence from the *same* analysis.

Examples:
  python mobile/test/ai/validate_day4_evidence.py --local local.json --report report.json
  python mobile/test/ai/validate_day4_evidence.py --local local.json --cloud cloud.json --report report.json --task-id UUID
  python mobile/test/ai/validate_day4_evidence.py --bundle day4-audit.json

The script prints IDs and a verdict only; never paste credentials into input JSON.
Historical B/C fixtures have different analysis IDs and must not be joined.
"""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
from urllib.parse import urlsplit

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
    if errors:
        first = errors[0]
        missing = []
        if first.validator == "required" and isinstance(first.instance, dict):
            missing = [key for key in first.validator_value if key not in first.instance]
        suffix = f"; missing required fields: {', '.join(missing)}" if missing else ""
        raise ValueError(f"{name} failed Schema validation at {list(first.path)}{suffix}")


def _http_key(value: str) -> tuple:
    """Compare redacted URLs without guessing any public/internal mapping."""
    try:
        uri = urlsplit(value)
        _require(uri.scheme.lower() in {"http", "https"} and bool(uri.hostname),
                 "target is not an HTTP URL")
        _require(uri.username is None and uri.password is None, "URL contains credentials")
        return (uri.scheme.lower(), uri.hostname.lower(),
                uri.port if uri.port is not None else (443 if uri.scheme.lower() == "https" else 80),
                uri.path or "/", uri.query, uri.fragment)
    except ValueError:
        # Never include the input URL or credentials in a failure message.
        raise ValueError("target URL structure is invalid") from None


def _audit_targets(local: dict, report: dict, cloud: dict) -> None:
    target = local["target"]
    _require(target["input_type"] == "url", "cloud case requires local target.input_type=url")
    initial = _http_key(cloud["initial_url"])
    final = _http_key(cloud["final_url"])
    _require(_http_key(target["display_value"]) == initial,
             "local target.display_value / cloud initial_url mismatch; mapping must be reviewed")
    _require((target["scheme"].lower(), (target["host"] or "").lower(), target["path"]) ==
             (initial[0], initial[1], initial[3]), "local target scheme/host/path mismatch")
    # Historical D reports show the input; the current APP shows the final URL.
    _require(report["target"]["type"] == "url" and
             _http_key(report["target"]["display"]) in {initial, final},
             "report target.display is neither cloud initial_url nor final_url")
    previous = initial
    for redirect in cloud["redirects"]:
        _require(_http_key(redirect["from_url"]) == previous,
                 "C01 redirect chain is discontinuous")
        _require(redirect["status_code"] in {301, 302, 303, 307, 308},
                 "C01 redirect status_code is not an HTTP redirect")
        previous = _http_key(redirect["to_url"])
    _require(previous == final, "C01 redirect chain does not reach final_url")
    for destination in report["observed_behavior"]["destinations"]:
        _require(_http_key(destination) == final,
                 "report observed_behavior.destinations differs from final_url")


def audit_screenshot(cloud: dict, path: Path, record: dict) -> dict:
    """Verify a supplied PNG against B's task-bound SHA-256 attestation.

    Does not download anything or prove pixel content / publisher identity.
    Pillow is needed only for this optional binary check.
    """
    from PIL import Image

    _require(isinstance(record, dict) and set(record) ==
             {"analysis_id", "task_id", "artifact_id", "sha256", "width", "height"},
             "screenshot record must contain only IDs, sha256, width and height")
    shot = cloud["screenshot"]
    for key in ("analysis_id", "task_id"):
        _require(record[key] == cloud[key], f"screenshot record {key} mismatch")
    _require(record["artifact_id"] == shot["artifact_id"], "screenshot record artifact_id mismatch")
    data = path.read_bytes()
    _require(data.startswith(b"\x89PNG\r\n\x1a\n"), "C04 file has no PNG signature")
    digest = hashlib.sha256(data).hexdigest()
    _require(record["sha256"] == digest, "C04 PNG sha256 differs from B record")
    try:
        with Image.open(path) as image:
            _require(image.format == "PNG", "C04 file is not PNG")
            size = image.size
            image.verify()
        with Image.open(path) as image:
            image.load()
    except (OSError, SyntaxError, ValueError):
        raise ValueError("C04 PNG binary validation failed") from None
    _require(list(size) == [record["width"], record["height"]], "C04 PNG dimensions mismatch")
    return {"artifact_id": shot["artifact_id"], "sha256": digest,
            "width": size[0], "height": size[1]}


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
    _require(local["preflight"]["attempted"] is False, "local preflight was attempted")
    local_ids = {item["id"] for item in local["evidence"]}
    for hint in local["risk_hints"]:
        _require(set(hint["evidence_ids"]) <= local_ids, "local risk_hints references missing Lxx")
    usage = report["token_usage"]
    _require(usage["total_tokens"] == usage["prompt_tokens"] + usage["completion_tokens"],
             "token_usage.total_tokens arithmetic mismatch")
    _require(report["sources"]["ai"] is (usage["request_count"] == 1),
             "sources.ai / token_usage.request_count mismatch")

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
        _require(cloud["page"] is not None, "C03 has no page observation")
        _audit_targets(local, report, cloud)
        shot = cloud["screenshot"]
        _require(shot["artifact_id"] == cloud["task_id"], "C04 artifact_id / task_id mismatch")
        _require(urlsplit(shot["download_url"]).path ==
                 f"/api/v1/deep-scans/{cloud['task_id']}/screenshot",
                 "C04 download_url does not belong to this task")
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
    _require(local_ids <= report_items.keys(), "report omits local evidence")
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


def audit_bundle(bundle: dict, *, analysis_id: str | None = None,
                 task_id: str | None = None, rule_only: bool = False) -> dict:
    """Validate the debug bundle wrapper and its three schema documents."""
    _require(isinstance(bundle, dict), "bundle root must be an object")
    _require(bundle.get("bundle_version") == "1.0", "unsupported bundle_version")
    if analysis_id is not None:
        _require(bundle.get("analysis_id") == analysis_id, "bundle differs from expected analysis_id")
    if task_id is not None:
        _require(bundle.get("task_id") == task_id, "bundle differs from expected task_id")
    local = bundle.get("local_evidence")
    cloud = bundle.get("cloud_evidence")
    report = bundle.get("report")
    _require(isinstance(local, dict), "bundle local_evidence is missing")
    _require(isinstance(cloud, dict), "bundle cloud_evidence is missing")
    _require(isinstance(report, dict), "bundle report is missing")
    _require(bundle.get("analysis_id") == local.get("analysis_id"), "bundle/local analysis_id mismatch")
    _require(bundle.get("status") == cloud.get("status"), "bundle/cloud status mismatch")
    result = audit(local, report, cloud, task_id=bundle.get("task_id"))
    _require(local["preflight"]["screenshot_path"] is None,
             "bundle contains a private screenshot_path")
    _require(bundle.get("analysis_id") == result["analysis_id"], "bundle analysis_id mismatch")
    _require(bundle.get("task_id") == result["task_id"], "bundle task_id mismatch")
    if rule_only:
        _require(report["sources"]["ai"] is False and report["token_usage"]["request_count"] == 0,
                 "rule-only audit cannot claim real AI or Token usage")
    return result


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--bundle", type=Path, help="Debug bundle copied from the app")
    parser.add_argument("--local", type=Path)
    parser.add_argument("--cloud", type=Path)
    parser.add_argument("--report", type=Path)
    parser.add_argument("--task-id")
    parser.add_argument("--analysis-id", help="Pin the formal analysis instead of trusting the bundle")
    parser.add_argument("--rule-only", action="store_true", help="Require no real AI/Token claim")
    parser.add_argument("--screenshot", type=Path, help="B's PNG; never fetched by this tool")
    parser.add_argument("--screenshot-record", type=Path, help="B's IDs/SHA-256/dimensions record")
    args = parser.parse_args()
    if args.bundle is not None:
        if args.local or args.cloud or args.report:
            parser.error("--bundle cannot be combined with --local/--cloud/--report")
        bundle = json.loads(args.bundle.read_text(encoding="utf-8-sig"))
        result = audit_bundle(bundle, analysis_id=args.analysis_id,
                              task_id=args.task_id, rule_only=args.rule_only)
        cloud = bundle["cloud_evidence"]
    else:
        if args.local is None or args.report is None:
            parser.error("provide --bundle or both --local and --report")
        if args.analysis_id or args.rule_only:
            parser.error("--analysis-id and --rule-only require --bundle")
        cloud = json.loads(args.cloud.read_text(encoding="utf-8-sig")) if args.cloud else None
        result = audit(
            json.loads(args.local.read_text(encoding="utf-8")),
            json.loads(args.report.read_text(encoding="utf-8")),
            cloud,
            task_id=args.task_id,
        )
    if bool(args.screenshot) != bool(args.screenshot_record):
        parser.error("provide both --screenshot and --screenshot-record")
    if args.screenshot is not None:
        if cloud is None:
            parser.error("a screenshot requires cloud evidence")
        result["png_verification"] = audit_screenshot(
            cloud, args.screenshot,
            json.loads(args.screenshot_record.read_text(encoding="utf-8-sig")),
        )
    else:
        result["png_verification"] = "NOT_CHECKED"
    result["scope"] = "JSON evidence audit only; APP pixels and wording require manual review"
    print("DAY 4 EVIDENCE AUDIT PASSED:", json.dumps(result, ensure_ascii=False))


if __name__ == "__main__":
    try:
        main()
    except ValueError as exc:
        raise SystemExit("EVIDENCE AUDIT FAILED: " + str(exc)) from None
    except OSError:
        raise SystemExit("EVIDENCE AUDIT BLOCKED: an input file is unavailable") from None
