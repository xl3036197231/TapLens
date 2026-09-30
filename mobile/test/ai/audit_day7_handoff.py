"""Read-only Day 7 audit of pinned A/B/C Git evidence; never contacts the API.

Run from any directory: python mobile/test/ai/audit_day7_handoff.py
Exit 0 means the *available rule evidence* is consistent, not AI/phone/PNG PASS.
"""

from __future__ import annotations

import json
import subprocess

from validate_day4_evidence import audit, audit_bundle


A = "839c1e51e9094f43586ae078fffb31cf29fcbb74"
B = "3bf8657ce188716daa7a83471c3d751a92de65e0"
B_RETENTION = "a1068cbb41d571d68c037c7b91019c8606e653b0"
C = "05d08aeb3e9854b01722b4ecab036ea961273a9d"
ANALYSIS_ID = "3def1166-1bff-49c0-a601-62ef37cfe503"
TASK_ID = "e454f7ea-5b9c-4626-83d3-d17d43496f40"
ORIGINAL_URL = "http://39.107.253.138/controlled/go/campus"
FINAL_URL = "http://39.107.253.138/controlled/campus-login.html"


def git_json(commit: str, path: str) -> dict:
    result = subprocess.run(
        ["git", "show", f"{commit}:{path}"],
        check=True,
        capture_output=True,
    )
    return json.loads(result.stdout.decode("utf-8-sig"))


def require(ok: bool, message: str) -> None:
    if not ok:
        raise ValueError(message)


def main() -> None:
    bundle = git_json(A, "shared/daliy_task/day6-a-evidence/day6-a-unified-audit-bundle.json")
    fallback = git_json(A, "shared/daliy_task/day6-a-evidence/day6-a-school-ai-attempt-fallback.json")
    server = git_json(B, "shared/daliy_task/day7-b-evidence/ai-call-audit.json")
    retention = git_json(B_RETENTION, "shared/daliy_task/day7-b-evidence/c04-retention-audit.json")
    device = git_json(C, "shared/daliy_task/day7-c-evidence/static-verification.json")

    result = audit_bundle(bundle, analysis_id=ANALYSIS_ID, task_id=TASK_ID, rule_only=True)
    local, cloud, report = (bundle[name] for name in ("local_evidence", "cloud_evidence", "report"))
    audit(local, fallback, cloud, task_id=TASK_ID)
    require(fallback["analysis_id"] == ANALYSIS_ID and fallback["sources"]["ai"] is False,
            "A fallback is not a non-AI report for the candidate analysis")
    require(fallback["token_usage"]["request_count"] == 0,
            "A fallback incorrectly claims model requests")
    require(local["target"]["display_value"] == cloud["initial_url"] == ORIGINAL_URL,
            "candidate original URL mismatch")
    require(cloud["final_url"] == FINAL_URL and report["target"]["display"] == FINAL_URL,
            "candidate final URL mismatch")
    require([item["id"] for item in local["evidence"]] == ["L01"], "local evidence is not L01 only")
    require({item["id"]: item["kind"] for item in cloud["evidence"]} == {
        "C01": "redirect", "C02": "form", "C03": "page", "C04": "screenshot"
    }, "cloud evidence C01-C04 type mismatch")
    require(cloud["redirects"] == [{"from_url": ORIGINAL_URL, "to_url": FINAL_URL, "status_code": 302}],
            "C01 is not the documented single 302")
    fields = {(item["name"], item["type"], item["sensitive"])
              for form in cloud["forms"] for item in form["fields"]}
    require(("student_id", "input", True) in fields and ("password", "password", True) in fields,
            "C02 lacks the two sensitive field metadata records")
    cloud_items = {item["id"]: item for item in cloud["evidence"]}
    require(cloud["page"]["title"] in cloud_items["C03"]["detail"],
            "C03 title does not match observed page title")
    require(all(item["method"] == "GET" for item in cloud["requests"]),
            "candidate cloud evidence includes a non-GET request")
    conclusion = " ".join([report["summary"], report["observed_behavior"]["summary"]] +
                          [item["description"] for item in report["differences"]])
    require(not any(phrase in conclusion for phrase in
                    ("绝对安全", "身份已经确认", "表单已提交", "已输入密码")),
            "rule wording overclaims observed behavior")
    require(set(result["local_ids"] + result["cloud_ids"]) ==
            {"L01", "C01", "C02", "C03", "C04"}, "rule evidence set differs")

    require(server["analysis_id"] == device["candidate_l01"]["analysis_id"] == ANALYSIS_ID,
            "A/B/C analysis_id mismatch")
    require(server["task_id"] == device["candidate_l01"]["task_id"] == TASK_ID,
            "A/B/C task_id mismatch")
    require(device["candidate_l01"]["target"] == ORIGINAL_URL and
            device["candidate_l01"]["evidence_id"] == "L01", "C local review target mismatch")
    require(device["candidate_l01"]["launched_external_app"] is False and
            device["candidate_l01"]["network_accessed"] is False and
            device["candidate_l01"]["preflight_status"] == "not_started",
            "C local static-only boundary mismatch")

    calls = server["calls"]
    require(len(calls) == 2 and server["replayed_request"] is False and
            server["created_cloud_task"] is False, "B audit call count or safety boundary mismatch")
    first, second = calls
    require(first["http_status"] == 502 and first["provider_status"] == 302 and
            first["provider_model_inference_entered"] is False and
            first["provider_usage"] == "无法确认", "10:01 call classification mismatch")
    usage = second["provider_usage"]
    require(second["http_status"] == second["provider_status"] == 200 and
            second["provider_model_inference_entered"] is True and
            second["backend_report_guard"] == "passed" and
            usage["prompt_tokens"] + usage["completion_tokens"] == usage["total_tokens"] == 5203,
            "12:04 successful provider call or usage mismatch")
    require(second["client_result"] == "rule_report_fallback_sources_ai_false",
            "12:04 client fallback classification mismatch")
    require(retention["analysis_id"] == ANALYSIS_ID and retention["task_id"] == TASK_ID and
            cloud["screenshot"]["artifact_id"] == TASK_ID,
            "B C04 retention record does not match A candidate")
    require(retention["current_database"]["status"] == "expired" and
            retention["current_database"]["evidence_json_bytes"] == 0 and
            len(retention["backups"]) == 2 and
            all(backup["status"] == "expired" and backup["evidence_json_bytes"] == 0 and
                backup["artifact_files"] == 0 for backup in retention["backups"]) and
            retention["persistent_volume_matching_task_files"] == 0 and
            retention["c04_png_binary"] == "unavailable",
            "B C04 retention record does not support unavailable-PNG conclusion")

    print(json.dumps({
        "candidate": {"analysis_id": ANALYSIS_ID, "task_id": TASK_ID},
        "pinned_commits": {"A": A, "B_calls": B, "B_retention": B_RETENTION, "C": C},
        "rule_json_schema_ids_urls": "PASS",
        "fallback_is_non_ai": "PASS",
        "c04_metadata": "PASS",
        "c04_png_binary_and_hash": "BLOCKED: B attests current ECS/two backups have no PNG; D did not inspect ECS",
        "first_call": "502; provider gateway 302; model inference not entered; usage unknown",
        "second_call": "200; provider model and backend guard passed; 5203 provider tokens",
        "client_accepted_ai_report": "BLOCKED: only rule fallback is archived",
        "physical_android_15": "BLOCKED: C recorded no connected physical phone",
        "scope": "Pinned Git JSON only; no server GET, scan, provider call or pixel audit",
    }, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    try:
        main()
    except (ValueError, KeyError, subprocess.CalledProcessError) as exc:
        raise SystemExit(f"DAY 7 AUDIT FAILED: {exc}") from None
