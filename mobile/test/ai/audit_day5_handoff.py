"""Read-only audit of pinned A/B/C Git deliveries. Never calls an API or model.

Optional --image-dir exports original Git PNGs outside the repository for review.
Output JSON records blob identity and verdicts, not credentials or report text.
"""

from __future__ import annotations

import argparse
from datetime import datetime
import hashlib
import json
import re
from pathlib import Path
import subprocess

from validate_day4_evidence import ROOT, audit, audit_bundle, audit_png_bytes, _validate_schema


ANALYSIS = "0bab7eba-ff50-42f8-a264-543596b2c9bf"
TASK = "f1858539-4595-4297-acfe-5bf81a91bc54"
A = "434ce911aa65070ff8ed2abed44cf088d49309ec"
B = "3ef0cdc547b20a884fcba78dc1de03bec86fb6ed"
C = "a519db2c94c2083249e5c8ec73e961f220ac93db"
BASE = "shared/daliy_task/"


def blob(revision: str, path: str) -> bytes:
    return subprocess.run(["git", "show", f"{revision}:{path}"], cwd=ROOT,
                          check=True, capture_output=True).stdout


def document(revision: str, path: str) -> dict:
    return json.loads(blob(revision, path).decode("utf-8-sig"))


def require(condition: bool, message: str) -> None:
    if not condition:
        raise ValueError(message)


def audit_ai_report(bundle: dict, report: dict) -> dict:
    result = audit(bundle["local_evidence"], report, bundle["cloud_evidence"], task_id=bundle["task_id"])
    require(report["sources"]["ai"] is True and report["token_usage"]["request_count"] == 1,
            "school report has no real-AI source/usage marker")
    require(report["token_usage"]["model"] == "cuc/deepseek", "school model name mismatch")
    require(datetime.fromisoformat(report["created_at"].replace("Z", "+00:00")) ==
            datetime.fromisoformat(bundle["report"]["created_at"].replace("Z", "+00:00")),
            "AI report created_at differs from the original report context")
    return result


def check_secret_markers(docs: dict) -> None:
    encoded = json.dumps(docs, ensure_ascii=False)
    require(not re.search(r"sk-[A-Za-z0-9_-]{8,}|eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+", encoded),
            "handoff contains a key/JWT-like secret marker")
    forbidden = {"api_key", "deepseek_key", "password", "passwd", "authorization",
                 "cookie", "access_token", "refresh_token"}
    def walk(value):
        if isinstance(value, dict):
            require(not (set(key.lower() for key in value) & forbidden),
                    "handoff contains a credential field")
            for nested in value.values():
                walk(nested)
        elif isinstance(value, list):
            for nested in value:
                walk(nested)
    walk(docs)


def run(image_dir: Path | None = None, ai_report: Path | None = None) -> dict:
    paths = {
        "a_bundle": (A, BASE + "day5-a-evidence/test1.json"),
        "b_cloud": (B, BASE + "day5-b-evidence/day5-unified/cloud-evidence.json"),
        "b_record": (B, BASE + "day5-b-evidence/day5-unified/server-verification.json"),
        "c_local": (C, BASE + "day5-c-evidence/local-evidence.json"),
        "b_ai_summary": (B, BASE + "day5-b-evidence/day5-school-model/server-verification.json"),
    }
    docs = {key: document(*source) for key, source in paths.items()}
    check_secret_markers(docs)
    bundle = docs["a_bundle"]
    result = audit_bundle(bundle, analysis_id=ANALYSIS, task_id=TASK, rule_only=True)
    cloud = docs["b_cloud"]
    require(cloud == bundle["cloud_evidence"], "A cloud / B snapshot mismatch")
    _validate_schema("local-evidence.schema.json", docs["c_local"])
    a_local = dict(bundle["local_evidence"])
    c_local = dict(docs["c_local"])
    a_local.pop("processed_at")
    c_local.pop("processed_at")
    require(a_local == c_local, "A local / C device JSON mismatch beyond execution time")
    record = docs["b_record"]
    require(record["target"] == {"analysis_id": ANALYSIS, "task_id": TASK}, "B record IDs mismatch")
    require(record["artifact"]["file"] == TASK + ".png", "B artifact filename mismatch")
    shot_record = {
        "analysis_id": ANALYSIS, "task_id": TASK,
        "artifact_id": cloud["screenshot"]["artifact_id"],
        **{key: record["artifact"][key] for key in ("sha256", "width", "height")},
    }
    image_sources = {
        "cloud-page.png": (B, BASE + f"day5-b-evidence/day5-unified/{TASK}.png"),
        "app-report.png": (A, BASE + "day5-a-evidence/day5-a-report-screen.png"),
        "app-task.png": (A, BASE + "day5-a-evidence/day5-a-task-status.png"),
    }
    png = audit_png_bytes(cloud, blob(*image_sources["cloud-page.png"]), shot_record)
    ai_result = None
    ai_digest = None
    if ai_report is not None:
        data = ai_report.read_bytes()
        report = json.loads(data.decode("utf-8-sig"))
        check_secret_markers({"ai_report": report})
        ai_result = audit_ai_report(bundle, report)
        ai_digest = hashlib.sha256(data).hexdigest()
    if image_dir is not None:
        target = image_dir.resolve()
        require(not target.is_relative_to(ROOT.resolve()), "review images must be outside repository")
        target.mkdir(parents=True, exist_ok=True)
        for name, source in image_sources.items():
            destination = target / name
            data = blob(*source)
            require(not destination.exists() or destination.read_bytes() == data,
                    "refusing to replace a different review image")
            destination.write_bytes(data)
    real_ai = docs["b_ai_summary"]["real_model_verification"]
    require(real_ai["analysis_id"] == ANALYSIS and real_ai["risk_level"] == "high",
            "B school-call summary is not for the unified analysis")
    require(set(real_ai["evidence_ids"]) == {"L01", "C01", "C02", "C03", "C04"},
            "B school-call summary evidence IDs mismatch")
    identities = {}
    for key, (revision, path) in {**paths, **image_sources}.items():
        identities[key] = {
            "commit": subprocess.run(["git", "rev-parse", revision], cwd=ROOT,
                                     check=True, capture_output=True, text=True).stdout.strip(),
            "path": path,
            "blob": subprocess.run(["git", "rev-parse", f"{revision}:{path}"], cwd=ROOT,
                                   check=True, capture_output=True, text=True).stdout.strip(),
        }
    return {
        "analysis_id": ANALYSIS, "task_id": TASK, "inputs": identities,
        "checks": {"rule_bundle": "PASS", "a_b_cloud_exact_match": "PASS",
                   "a_c_local_equal_except_time": "PASS", "cloud_png": "PASS",
                   "credential_marker_check": "PASS",
                   "school_ai_full_report": "PASS" if ai_result else "BLOCKED",
                   "school_ai_app_display": "BLOCKED"},
        "rule_evidence": result, "png_verification": png,
        "school_ai_summary_only": real_ai["token_usage"],
        "ai_report_audit": ai_result, "ai_report_sha256": ai_digest,
        "limitation": "B real-call summary is not a full AI report; A delivery is rule-only. "
                      "Mock is not formal AI evidence. APP pixels need manual review.",
    }


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--image-dir", type=Path)
    parser.add_argument("--ai-report", type=Path, help="A's full final school report, not B summary or Mock")
    args = parser.parse_args()
    print(json.dumps(run(args.image_dir, args.ai_report), ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
