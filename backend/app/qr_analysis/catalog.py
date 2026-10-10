import hashlib
import json
from dataclasses import dataclass
from pathlib import Path

from app.core.errors import AppError
from app.qr_analysis.schemas import SampleRef


CATALOG_PATH = (
    Path(__file__).resolve().parents[3]
    / "shared/fixtures/qr/qr-cloud-fixture-catalog-v2.json"
)


@dataclass(frozen=True)
class CatalogCase:
    sample_id: str
    payload: str
    payload_sha256: str
    analyzer_profile: str
    expected_claim: dict[str, str]


class QrFixtureCatalog:
    def __init__(self, path: Path = CATALOG_PATH) -> None:
        raw = json.loads(path.read_text(encoding="utf-8"))
        if (
            raw.get("schema_version") != "2.0"
            or raw.get("catalog_revision") != "2026-10-09.1"
            or raw.get("analysis_mode") != "repository_fixture_static"
        ):
            raise ValueError("QR fixture catalog metadata is invalid")
        cases: dict[str, CatalogCase] = {}
        for item in raw.get("cases", []):
            sample_id = item.get("id")
            payload = item.get("payload")
            digest = item.get("payload_sha256")
            if not isinstance(sample_id, str) or sample_id in cases:
                raise ValueError("QR fixture catalog contains duplicate IDs")
            if not isinstance(payload, str) or not isinstance(digest, str):
                raise ValueError("QR fixture catalog payload is invalid")
            actual = hashlib.sha256(payload.encode("utf-8")).hexdigest()
            if actual != digest:
                raise ValueError("QR fixture catalog digest is invalid")
            if item.get("network_policy") != "deny" or item.get("external_action_policy") != "deny":
                raise ValueError("QR fixture catalog must deny external actions")
            cases[sample_id] = CatalogCase(
                sample_id=sample_id,
                payload=payload,
                payload_sha256=digest,
                analyzer_profile=str(item.get("analyzer_profile", "")),
                expected_claim=dict(item.get("expected_claim") or {}),
            )
        if set(cases) != {f"QR{value:02d}" for value in range(2, 14)}:
            raise ValueError("QR fixture catalog must contain QR02 through QR13")
        self.cases = cases

    def resolve(self, reference: SampleRef) -> CatalogCase:
        case = self.cases.get(reference.sample_id)
        if case is None:
            invalid("fixture_not_found", "固定样例不存在")
        if reference.payload_sha256 != case.payload_sha256:
            invalid("fixture_digest_mismatch", "固定样例摘要与服务端目录不一致")
        return case


def invalid(reason: str, message: str) -> None:
    raise AppError(
        code="CLOUD_REQUEST_INVALID",
        message=message,
        status_code=422,
        details={"reason": reason},
    )
