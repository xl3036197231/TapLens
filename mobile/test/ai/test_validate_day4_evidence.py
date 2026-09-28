"""Fixture-only tests; no historical data is presented as a live joint scan."""

import copy
import hashlib
import json
import tempfile
import unittest
from pathlib import Path
from urllib.parse import urlsplit

from validate_day4_evidence import audit, audit_bundle, audit_screenshot


ROOT = Path(__file__).resolve().parents[3]


def fixture(path: str) -> dict:
    return json.loads((ROOT / "shared" / "fixtures" / path).read_text(encoding="utf-8"))


class DayFourAuditTest(unittest.TestCase):
    def setUp(self) -> None:
        self.local = fixture("local/case03-local-url-succeeded.json")
        self.cloud = fixture("cloud/day2-short-link-succeeded.json")
        self.report = fixture("reports/day3-short-link-verified.json")

    def synthetic_bundle(self) -> dict:
        """Align in memory only. Never save synthetic data as a formal task."""
        local = copy.deepcopy(self.local)
        cloud = copy.deepcopy(self.cloud)
        report = copy.deepcopy(self.report)
        local["analysis_id"] = cloud["analysis_id"]
        url = urlsplit(cloud["initial_url"])
        local["target"].update(display_value=cloud["initial_url"], scheme=url.scheme,
                               host=url.hostname, path=url.path)
        local["evidence"][0]["detail"] = f"{url.scheme} {url.hostname} {url.path}"
        report["analysis_id"] = cloud["analysis_id"]
        report["sources"]["local"] = True
        report["evidence"].append({
            "id": "L01", "source": "local", "title": local["evidence"][0]["title"],
            "detail": local["evidence"][0]["detail"],
        })
        return {"bundle_version": "1.0", "analysis_id": cloud["analysis_id"],
                "task_id": cloud["task_id"], "status": cloud["status"],
                "local_evidence": local, "cloud_evidence": cloud, "report": report}

    def test_local_only_insufficient_report(self) -> None:
        report = fixture("reports/day3-local-static-insufficient.json")
        result = audit(self.local, report)
        self.assertEqual(result["local_ids"], ["L01"])
        self.assertIsNone(result["task_id"])

    def test_historical_scans_cannot_be_joined(self) -> None:
        with self.assertRaisesRegex(ValueError, "analysis_id mismatch"):
            audit(self.local, self.report, self.cloud)

    def test_synthetic_same_id_contract(self) -> None:
        # In-memory alignment tests the validator only; it is not field evidence.
        self.local["analysis_id"] = self.cloud["analysis_id"]
        self.local["target"]["display_value"] = self.cloud["initial_url"]
        uri = urlsplit(self.cloud["initial_url"])
        self.local["target"].update(scheme=uri.scheme, host=uri.hostname, path=uri.path)
        self.report["sources"]["local"] = True
        self.report["evidence"].append({
            "id": "L01", "source": "local",
            "title": self.local["evidence"][0]["title"],
            "detail": self.local["evidence"][0]["detail"],
        })
        result = audit(self.local, self.report, self.cloud, task_id=self.cloud["task_id"])
        self.assertEqual(result["cloud_ids"], ["C01", "C02", "C03", "C04"])
        self.assertEqual(result["local_ids"], ["L01"])

        wrong_id = copy.deepcopy(self.report)
        wrong_id["evidence"][0]["id"] = "C99"
        with self.assertRaisesRegex(ValueError, "unavailable evidence ID"):
            audit(self.local, wrong_id, self.cloud)

        wrong_task = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"
        with self.assertRaisesRegex(ValueError, "task_id mismatch"):
            audit(self.local, self.report, self.cloud, task_id=wrong_task)

    def test_debug_bundle_uses_same_strict_audit(self) -> None:
        local = copy.deepcopy(self.local)
        cloud = copy.deepcopy(self.cloud)
        report = copy.deepcopy(self.report)
        local["analysis_id"] = cloud["analysis_id"]
        local["target"]["display_value"] = cloud["initial_url"]
        uri = urlsplit(cloud["initial_url"])
        local["target"].update(scheme=uri.scheme, host=uri.hostname, path=uri.path)
        report["analysis_id"] = cloud["analysis_id"]
        report["sources"]["local"] = True
        report["evidence"].append({
            "id": "L01", "source": "local",
            "title": local["evidence"][0]["title"],
            "detail": local["evidence"][0]["detail"],
        })
        result = audit_bundle({
            "bundle_version": "1.0",
            "analysis_id": cloud["analysis_id"],
            "task_id": cloud["task_id"],
            "status": cloud["status"],
            "local_evidence": local,
            "cloud_evidence": cloud,
            "report": report,
        })
        self.assertEqual(result["analysis_id"], cloud["analysis_id"])
        self.assertEqual(result["task_id"], cloud["task_id"])

        wrong_status = {
            "bundle_version": "1.0",
            "analysis_id": cloud["analysis_id"],
            "task_id": cloud["task_id"],
            "status": "failed",
            "local_evidence": local,
            "cloud_evidence": cloud,
            "report": report,
        }
        with self.assertRaisesRegex(ValueError, "bundle/cloud status mismatch"):
            audit_bundle(wrong_status)

    def test_same_id_cannot_hide_wrong_local_target(self) -> None:
        bundle = self.synthetic_bundle()
        bundle["local_evidence"]["target"]["display_value"] = "https://scholarship.example.test/apply"
        with self.assertRaisesRegex(ValueError, "initial_url mismatch"):
            audit_bundle(bundle)
        bundle = self.synthetic_bundle()
        bundle["local_evidence"]["target"]["host"] = "scholarship.example.test"
        with self.assertRaisesRegex(ValueError, "scheme/host/path mismatch"):
            audit_bundle(bundle)
        bundle = self.synthetic_bundle()
        bundle["report"]["evidence"] = [entry for entry in bundle["report"]["evidence"] if entry["id"] != "L01"]
        with self.assertRaisesRegex(ValueError, "omits local evidence"):
            audit_bundle(bundle)

    def test_report_can_show_initial_or_final_but_not_other_target(self) -> None:
        bundle = self.synthetic_bundle()
        bundle["report"]["target"]["display"] = bundle["cloud_evidence"]["final_url"]
        audit_bundle(bundle)
        bundle["report"]["target"]["display"] = "https://another.example.test/"
        with self.assertRaisesRegex(ValueError, "report target.display"):
            audit_bundle(bundle)

    def test_cloud_redirect_must_reach_the_reported_target(self) -> None:
        bundle = self.synthetic_bundle()
        bundle["cloud_evidence"]["redirects"][0]["from_url"] = "https://another.example.test/"
        with self.assertRaisesRegex(ValueError, "discontinuous"):
            audit_bundle(bundle)
        bundle = self.synthetic_bundle()
        bundle["cloud_evidence"]["redirects"][0]["to_url"] = "https://another.example.test/"
        with self.assertRaisesRegex(ValueError, "does not reach final_url"):
            audit_bundle(bundle)

    def test_pin_formal_task_and_analysis_and_require_rule_only(self) -> None:
        bundle = self.synthetic_bundle()
        audit_bundle(bundle, analysis_id=bundle["analysis_id"], task_id=bundle["task_id"], rule_only=True)
        for name in ("analysis_id", "task_id"):
            with self.assertRaisesRegex(ValueError, f"expected {name}"):
                audit_bundle(bundle, **{name: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"})
        bundle["report"]["sources"]["ai"] = True
        bundle["report"]["token_usage"].update(request_count=1, model="deepseek-flash")
        with self.assertRaisesRegex(ValueError, "rule-only"):
            audit_bundle(bundle, rule_only=True)

    def test_token_counters_and_ai_flag_are_consistent(self) -> None:
        bundle = self.synthetic_bundle()
        bundle["report"]["sources"]["ai"] = True
        with self.assertRaisesRegex(ValueError, "sources.ai"):
            audit_bundle(bundle)
        bundle["report"]["token_usage"].update(request_count=1, prompt_tokens=4,
                                              completion_tokens=2, total_tokens=5, model="deepseek-flash")
        with self.assertRaisesRegex(ValueError, "arithmetic"):
            audit_bundle(bundle)

    def test_screenshot_metadata_must_belong_to_the_task(self) -> None:
        bundle = self.synthetic_bundle()
        bundle["cloud_evidence"]["screenshot"]["artifact_id"] = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"
        with self.assertRaisesRegex(ValueError, "artifact_id"):
            audit_bundle(bundle)
        bundle = self.synthetic_bundle()
        bundle["cloud_evidence"]["screenshot"]["download_url"] = "https://example.test/api/v1/deep-scans/other/screenshot"
        with self.assertRaisesRegex(ValueError, "download_url"):
            audit_bundle(bundle)

    def test_missing_page_and_nonexistent_local_hint_are_rejected(self) -> None:
        bundle = self.synthetic_bundle()
        bundle["cloud_evidence"]["page"] = None
        with self.assertRaisesRegex(ValueError, "C03"):
            audit_bundle(bundle)
        bundle = self.synthetic_bundle()
        bundle["local_evidence"]["risk_hints"][0]["evidence_ids"] = ["L99"]
        with self.assertRaisesRegex(ValueError, "missing Lxx"):
            audit_bundle(bundle)

    def test_png_is_checked_against_task_hash_and_dimensions(self) -> None:
        from PIL import Image

        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / "synthetic.png"
            Image.new("RGB", (32, 24), color="white").save(path)
            cloud = self.cloud
            record = {"analysis_id": cloud["analysis_id"], "task_id": cloud["task_id"],
                      "artifact_id": cloud["screenshot"]["artifact_id"],
                      "sha256": hashlib.sha256(path.read_bytes()).hexdigest(),
                      "width": 32, "height": 24}
            self.assertEqual(audit_screenshot(cloud, path, record)["width"], 32)
            wrong = dict(record, sha256="0" * 64)
            with self.assertRaisesRegex(ValueError, "sha256"):
                audit_screenshot(cloud, path, wrong)
            wrong = dict(record, task_id="aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa")
            with self.assertRaisesRegex(ValueError, "task_id"):
                audit_screenshot(cloud, path, wrong)
            wrong = dict(record, height=25)
            with self.assertRaisesRegex(ValueError, "dimensions"):
                audit_screenshot(cloud, path, wrong)


if __name__ == "__main__":
    unittest.main()
