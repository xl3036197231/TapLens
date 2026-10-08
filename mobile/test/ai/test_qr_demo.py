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
        manifest = json.loads((FIXTURES / "manifest.json").read_text(encoding="utf-8"))
        self.assertEqual([case["id"] for case in manifest["cases"]], [f"QR{i:02d}" for i in range(1, 12)])
        self.assertEqual([case["id"] for case in manifest["supplemental_cases"]], ["QR12", "QR13"])
        cases = [*manifest["cases"], *manifest["supplemental_cases"]]
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
        for case in manifest["supplemental_cases"]:
            self.assertEqual(case["expected_type"], "http_url")
            self.assertEqual(case["expected_package_name"], "tv.danmaku.bili")
            self.assertEqual(case["payload"], case["source_product_url"])
            self.assertTrue(case["payload"].startswith("https://item.taobao.com/item.htm?id="))
            entry_copy = " ".join(case["scene"][key] for key in ("surface", "headline", "body", "scan_prompt"))
            self.assertIn("哔哩哔哩", entry_copy)
            self.assertNotIn("淘宝", entry_copy)
            self.assertNotIn("taobao", entry_copy.lower())
            self.assertIn("淘宝", case["expected_preview"])

    def test_page_has_no_automatic_external_action_or_remote_assets(self) -> None:
        html = (SITE / "qr-demo.html").read_text(encoding="utf-8")
        js = (SITE / "qr-demo.js").read_text(encoding="utf-8")
        self.assertIn('"../../../../shared/datasets/qr/manifest.json"', js)
        self.assertIn("showModal()", js)
        self.assertNotRegex(html, r"https?://|<form|<iframe")
        self.assertNotRegex(js, r"window\.open|location\s*=|document\.write|innerHTML|eval\(")
        self.assertIn('link.rel = "noopener noreferrer"', js)
        self.assertNotRegex(html, r"on(?:click|load|submit)\s*=")


if __name__ == "__main__":
    unittest.main()
