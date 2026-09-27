import json
from pathlib import Path

from jsonschema import Draft202012Validator, FormatChecker
from referencing import Registry, Resource

from app.ai.provider import ProviderResult
from app.ai.schemas import AiAnalyzeRequest
from app.core.errors import AppError


CONTRACTS = Path(__file__).resolve().parents[3] / "shared" / "contracts"


def validate_and_finalize_report(
    payload: AiAnalyzeRequest,
    result: ProviderResult,
) -> dict[str, object]:
    report = dict(result.report)
    report["analysis_id"] = str(report.get("analysis_id", ""))
    expected_id = str(payload.report_context.analysis_id)
    if report["analysis_id"] != expected_id:
        reject("模型返回了其他 analysis_id")

    expected_created_at = payload.report_context.created_at.isoformat().replace("+00:00", "Z")
    returned_created_at = str(report.get("created_at", ""))
    if returned_created_at.replace("+00:00", "Z") != expected_created_at:
        reject("模型没有原样返回 created_at")

    source_items = {}
    for source, summary in (
        ("local", payload.local_evidence),
        ("cloud", payload.cloud_evidence),
    ):
        if summary is None:
            continue
        for item in summary.evidence:
            if item.id in source_items:
                reject("证据编号重复")
            source_items[item.id] = {
                "source": source,
                "title": item.title,
                "detail": item.detail,
            }

    evidence = report.get("evidence")
    if not isinstance(evidence, list):
        reject("报告缺少 evidence")
    report_items = {}
    normalized_evidence = []
    for raw in evidence:
        if not isinstance(raw, dict) or not isinstance(raw.get("id"), str):
            reject("报告证据格式无效")
        evidence_id = raw["id"]
        original = source_items.get(evidence_id)
        if original is None or evidence_id in report_items:
            reject("报告引用了不存在或重复的证据")
        normalized = {"id": evidence_id, **original}
        report_items[evidence_id] = normalized
        normalized_evidence.append(normalized)
    if set(report_items) != set(source_items):
        reject("报告没有完整保留输入证据")
    report["evidence"] = normalized_evidence

    references = set()
    observed = report.get("observed_behavior")
    if isinstance(observed, dict) and isinstance(observed.get("evidence_ids"), list):
        references.update(observed["evidence_ids"])
    differences = report.get("differences")
    if isinstance(differences, list):
        for difference in differences:
            if isinstance(difference, dict) and isinstance(difference.get("evidence_ids"), list):
                references.update(difference["evidence_ids"])
    if not references <= set(source_items):
        reject("报告结论引用了不存在的证据")

    hard_high = any(item.risk_level == "high" for item in payload.hard_risk_findings)
    if hard_high and report.get("risk_level") != "high":
        reject("模型试图降低规则确认的高风险")

    report["sources"] = {
        "local": payload.local_evidence is not None and bool(payload.local_evidence.evidence),
        "cloud": payload.cloud_evidence is not None and bool(payload.cloud_evidence.evidence),
        "ai": True,
    }
    report["token_usage"] = {
        "request_count": 1,
        "prompt_tokens": result.prompt_tokens,
        "completion_tokens": result.completion_tokens,
        "total_tokens": result.total_tokens,
        "model": result.model,
    }
    validate_schema(report)
    return report


def validate_schema(report: dict[str, object]) -> None:
    registry = Registry()
    for path in CONTRACTS.glob("*.schema.json"):
        schema = json.loads(path.read_text(encoding="utf-8"))
        registry = registry.with_resource(schema["$id"], Resource.from_contents(schema))
    schema = json.loads((CONTRACTS / "analysis-report.schema.json").read_text(encoding="utf-8"))
    errors = list(
        Draft202012Validator(
            schema,
            registry=registry,
            format_checker=FormatChecker(),
        ).iter_errors(report)
    )
    if errors:
        error = errors[0]
        reject(
            f"模型报告不符合 Schema：{list(error.path)}",
            details={"validator": error.validator, "schema_message": error.message},
        )


def reject(message: str, *, details: dict[str, object] | None = None) -> None:
    raise AppError(
        code="AI_REPORT_REJECTED",
        message=message,
        status_code=502,
        details=details,
    )
