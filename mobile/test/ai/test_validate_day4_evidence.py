"""Fixture-only tests; no historical data is presented as a live joint scan."""

import copy
import json
import unittest
from pathlib import Path

from validate_day4_evidence import audit


ROOT = Path(__file__).resolve().parents[3]


def fixture(path: str) -> dict:
    return json.loads((ROOT / "shared" / "fixtures" / path).read_text(encoding="utf-8"))


class DayFourAuditTest(unittest.TestCase):
    def setUp(self) -> None:
        self.local = fixture("local/case03-local-url-succeeded.json")
        self.cloud = fixture("cloud/day2-short-link-succeeded.json")
        self.report = fixture("reports/day3-short-link-verified.json")

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


if __name__ == "__main__":
    unittest.main()
