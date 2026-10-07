"""Read-only Day 6 audit of pinned A/B/C Git evidence; never contacts ECS/AI.

The old success snapshot and current expired state are intentionally separate.
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path

from audit_day5_handoff import (
    ANALYSIS, TASK, BASE, blob, check_secret_markers, document,
    require, run as audit_day5,
)
from validate_day4_evidence import ROOT, audit


A = "a545297558a54e0d0c8f7e3ccde01368d2b20e6f"
B = "a851c0c5830324ae07f6047f40e1000508444173"
C = "36bcf9b3547c45d25d05413ac9e8e66259d929a8"


def run(image_dir: Path | None = None) -> dict:
    old = audit_day5()
    a_base = BASE + "day5-a-evidence/"
    a_call = document(A, a_base + "day5-a-school-ai-call-result.json")
    a_report = document(A, a_base + "day5-a-school-ai-report.json")
    a_query = document(A, a_base + "day5-a-readonly-query-attempt.json")
    b_now = document(B, BASE + "day6-b-evidence/server-verification.json")
    c_local = document(C, BASE + "day5-c-evidence/local-evidence.json")
    check_secret_markers({"a_call": a_call, "a_report": a_report,
                          "a_query": a_query, "b_now": b_now, "c_local": c_local})
    bundle = document(old["inputs"]["a_bundle"]["commit"],
                      old["inputs"]["a_bundle"]["path"])
    rule_result = audit(bundle["local_evidence"], a_report,
                        bundle["cloud_evidence"], task_id=TASK)
    require(c_local["analysis_id"] == ANALYSIS and
            c_local["target"]["display_value"] == bundle["cloud_evidence"]["initial_url"],
            "C Day 6 local source does not match archived target")
    require({"L01"} == {item["id"] for item in c_local["evidence"]},
            "C local evidence is not exactly L01")
    require(c_local["observations"]["network_accessed"] is False and
            c_local["observations"]["launched_external_app"] is False and
            c_local["preflight"]["status"] == "not_started", "C local static boundary changed")
    require(all(record["analysis_id"] == ANALYSIS and record["task_id"] == TASK
                for record in (a_call, a_query)), "A Day 6 record IDs mismatch")
    require(a_call["http_status"] == 422 and a_call["accepted_ai_report"] is False and
            a_call["backend_error_code_captured"] is False and
            a_call["school_ai_call_count"] == 1 and
            a_call["new_cloud_scan_created"] is False,
            "A 422 record does not support an unknown backend rejection cause")
    require(a_report["sources"]["ai"] is False and
            a_report["token_usage"]["request_count"] == 0 and
            a_report["token_usage"]["model"] is None,
            "A fallback report falsely claims real AI")
    require(a_query["app_result"]["task_get_sent"] is False and
            a_query["app_state"]["existing_task_id_filled"] is True and
            a_query["app_state"]["button_label"] == "查询已有任务" and
            a_query["app_result"]["login_request_sent"] is False and
            a_query["app_result"]["create_task_request_sent"] is False and
            a_query["app_result"]["school_ai_request_sent"] is False,
            "A failed health check was misreported as a task or model request")
    task = b_now["formal_task"]
    require(task["analysis_id"] == ANALYSIS and task["task_id"] == TASK and
            task["database_status"] == "expired" and task["readonly_get_status"] == 410 and
            task["readonly_get_error_code"] == "CLOUD_TASK_EXPIRED" and
            task["evidence_present"] is False,
            "B current task expiry evidence is inconsistent")
    require(b_now["complete_model_report_recovery"]["recoverable"] is False and
            b_now["scope"]["new_cloud_tasks_created"] == 0 and
            b_now["scope"]["school_model_provider_calls"] == 0,
            "B Day 6 recovery or no-new-calls boundary changed")
    require(b_now["error_contract"]["observed_401"]["provider_invoked"] is False and
            b_now["error_contract"]["observed_422"]["provider_invoked"] is False,
            "B no-auth error probes called provider")
    # These are independent tests, not network access by the formal local parser.
    c_debug_manifest = blob(C, "mobile/android/app/src/debug/AndroidManifest.xml").decode()
    c_network = blob(C, "mobile/android/app/src/debug/res/xml/network_security_config.xml").decode()
    c_query_test = blob(C, "mobile/integration_test/day6_c_readonly_query_test.dart").decode()
    require("network_security_config" in c_debug_manifest and
            'cleartextTrafficPermitted="false"' in c_network and
            '39.107.253.138' in c_network and
            "MockClient" in c_query_test and "contains('POST')" in c_query_test,
            "C debug/Mock network boundary not present in delivered source")
    screenshots = {
        "a-ai-rejected.png": (A, a_base + "day5-a-school-ai-guard-rejected.png"),
        "a-ai-evidence.png": (A, a_base + "day5-a-school-ai-evidence.png"),
        "a-readonly-blocked.png": (A, a_base + "day5-a-readonly-query-blocked.png"),
        "a-local-preflight.png": (A, a_base + "day5-a-preflight-risk.png"),
        "c-local-preflight.png": (C, BASE + "day6-c-evidence/latest-apk-local-preflight.png"),
    }
    if image_dir is not None:
        target = image_dir.resolve()
        require(not target.is_relative_to(ROOT.resolve()), "review images must be outside repository")
        target.mkdir(parents=True, exist_ok=True)
        for name, source in screenshots.items():
            data = blob(*source)
            output = target / name
            require(not output.exists() or output.read_bytes() == data,
                    "refusing to replace a different review image")
            output.write_bytes(data)
    return {
        "analysis_id": ANALYSIS, "task_id": TASK,
        "sources": {"a": A, "b": B, "c": C},
        "checks": {
            "archived_day5_rule_bundle_and_png": "PASS",
            "a_day6_fallback_report_and_schema": "PASS",
            "c_formal_local_unchanged": "PASS",
            "c_debug_network_and_mock_source_boundary": "PASS",
            "b_current_task_expired_410": "PASS",
            "a_actual_existing_task_get": "BLOCKED",
            "school_ai_complete_report": "BLOCKED",
            "school_ai_app_result": "BLOCKED",
        },
        "rule_report": rule_result,
        "a_school_http_status": a_call["http_status"],
        "a_school_error_code_known": a_call["backend_error_code_captured"],
        "current_task_status": task["database_status"],
        "current_task_readonly_get_status": task["readonly_get_status"],
        "complete_model_report_recoverable": b_now["complete_model_report_recovery"]["recoverable"],
        "scope": "No new scan, no provider call, no live task GET. C device results are source-reported; screenshots require human review.",
    }


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--image-dir", type=Path)
    args = parser.parse_args()
    print(json.dumps(run(args.image_dir), ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
