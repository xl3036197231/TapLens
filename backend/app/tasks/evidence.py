from datetime import datetime
from uuid import UUID

from app.sandbox.collector import CollectorResult, sanitize_url


def build_success_evidence(
    *,
    analysis_id: UUID,
    task_id: UUID,
    initial_url: str,
    result: CollectorResult,
    generated_at: datetime,
    expires_at: datetime,
    duration_ms: int,
    public_base_url: str,
) -> dict[str, object]:
    evidence: list[dict[str, object]] = []

    def add(kind: str, title: str, detail: str) -> None:
        evidence.append(
            {
                "id": f"C{len(evidence) + 1:02d}",
                "kind": kind,
                "title": title,
                "detail": detail,
            }
        )

    if result.redirects:
        add("redirect", "云端跳转链", f"观察到{len(result.redirects)}次HTTP跳转。")
    sensitive_fields = sum(
        1
        for form in result.forms
        for field in form.get("fields", [])
        if isinstance(field, dict) and field.get("sensitive") is True
    )
    if sensitive_fields:
        add("form", "敏感表单字段", f"页面表单包含{ sensitive_fields }个敏感输入字段。")
    if result.blocked_actions:
        add("blocked_action", "已阻止主动操作", f"沙箱已阻止{len(result.blocked_actions)}个可能改变外部状态的操作。")
    add("page", "云端页面摘要", f"页面标题：{result.title or '未提供标题'}")
    add("screenshot", "云端页面截图", "已生成受鉴权与过期时间保护的页面截图。")

    base_url = public_base_url.rstrip("/")
    timestamp = generated_at.isoformat().replace("+00:00", "Z")
    expiry = expires_at.isoformat().replace("+00:00", "Z")
    return {
        "schema_version": "1.0",
        "analysis_id": str(analysis_id),
        "task_id": str(task_id),
        "status": "succeeded",
        "generated_at": timestamp,
        "duration_ms": duration_ms,
        "initial_url": sanitize_url(initial_url),
        "final_url": result.final_url,
        "redirects": result.redirects,
        "requests": result.requests,
        "forms": result.forms,
        "blocked_actions": result.blocked_actions,
        "page": {"title": result.title, "text_summary": result.text_summary},
        "screenshot": {
            "artifact_id": str(task_id),
            "download_url": f"{base_url}/api/v1/deep-scans/{task_id}/screenshot",
            "expires_at": expiry,
        },
        "evidence": evidence,
        "limitations": result.limitations,
        "error": None,
        "expires_at": expiry,
    }


def build_failure_evidence(
    *,
    analysis_id: UUID,
    task_id: UUID,
    initial_url: str,
    generated_at: datetime,
    expires_at: datetime,
    duration_ms: int,
    error_code: str,
    message: str,
    retryable: bool,
) -> dict[str, object]:
    timestamp = generated_at.isoformat().replace("+00:00", "Z")
    expiry = expires_at.isoformat().replace("+00:00", "Z")
    return {
        "schema_version": "1.0",
        "analysis_id": str(analysis_id),
        "task_id": str(task_id),
        "status": "failed",
        "generated_at": timestamp,
        "duration_ms": duration_ms,
        "initial_url": sanitize_url(initial_url),
        "final_url": None,
        "redirects": [],
        "requests": [],
        "forms": [],
        "blocked_actions": [],
        "page": None,
        "screenshot": None,
        "evidence": [{
            "id": "C01",
            "kind": "error",
            "title": "云端深度分析未完成",
            "detail": message,
        }],
        "limitations": ["任务未完成，未取得完整动态证据。"],
        "error": {
            "code": error_code,
            "message": message,
            "retryable": retryable,
            "details": None,
        },
        "expires_at": expiry,
    }
