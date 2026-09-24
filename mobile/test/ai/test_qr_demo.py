"""Keep the scene board aligned with the canonical offline QR fixtures."""

import json
import re
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[3]
SITE = ROOT / "mobile/test/ai/day2_site"
FIXTURES = ROOT / "shared/datasets/qr"


class QrDemoTest(unittest.TestCase):
    def test_scene_and_masked_preview_for_every_case(self) -> None:
        cases = json.loads((FIXTURES / "manifest.json").read_text(encoding="utf-8"))["cases"]
        self.assertEqual([case["id"] for case in cases], [f"QR{i:02d}" for i in range(1, 12)])
        tones = set(re.findall(r"^  (\w+): \{ wash:", (SITE / "qr-demo.js").read_text(encoding="utf-8"), re.M))
        self.assertEqual(len(tones), 11)
        for case in cases:
            with self.subTest(case=case["id"]):
                self.assertTrue((FIXTURES / case["png"]).is_file())
                self.assertIn(case["scene"]["tone"], tones)
                for key in ("surface", "headline", "body", "scan_prompt"):
                    self.assertTrue(case["scene"][key].strip())
                self.assertTrue(case["expected_preview"].strip())
                self.assertFalse(case["allow_cloud"])
        for case_id in ("QR03", "QR04", "QR05", "QR06", "QR07"):
            preview = next(case["expected_preview"] for case in cases if case["id"] == case_id)
            self.assertNotIn("+00000000000", preview)
            self.assertNotIn("NOT_A_REAL_PASSWORD", preview)
            self.assertNotIn("demo@example.test", preview)

    def test_page_has_no_external_action_or_remote_assets(self) -> None:
        html = (SITE / "qr-demo.html").read_text(encoding="utf-8")
        js = (SITE / "qr-demo.js").read_text(encoding="utf-8")
        self.assertIn('"../../../../shared/datasets/qr/manifest.json"', js)
        self.assertIn("showModal()", js)
        self.assertNotRegex(html, r"https?://|<form|<iframe")
        self.assertNotRegex(js, r"window\.open|location\s*=|document\.write|innerHTML|eval\(")
        self.assertNotRegex(html, r"on(?:click|load|submit)\s*=")


if __name__ == "__main__":
    unittest.main()
