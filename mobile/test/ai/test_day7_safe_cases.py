"""Offline provenance/fixture consistency checks; intentionally no network I/O."""

import json
import unittest
from pathlib import Path
from urllib.parse import urlsplit


ROOT = Path(__file__).resolve().parents[3]


class Day7SafeCasesTest(unittest.TestCase):
    def test_cases_reuse_safe_fixtures(self) -> None:
        cases = json.loads((ROOT / "shared/datasets/day7-safe-case-list.json").read_text(encoding="utf-8"))["cases"]
        self.assertEqual({item["id"] for item in cases}, {"D7-QR-01", "D7-URL-01", "D7-DL-01"})
        self.assertTrue(all(item["safe_for_demo"] and item["source_urls"] for item in cases))

        qr = next(item for item in cases if item["type"] == "qr")
        manifest = json.loads((ROOT / "shared/datasets/qr/manifest.json").read_text(encoding="utf-8"))
        self.assertEqual(qr["payload"], next(item["payload"] for item in manifest["cases"] if item["id"] == "QR02"))

        deep_link = next(item for item in cases if item["type"] == "deep_link")
        fixtures = json.loads((ROOT / "shared/datasets/constructed-fixtures/deep-link-fixtures.json").read_text(encoding="utf-8"))
        self.assertEqual(deep_link["payload"], next(item["input"] for item in fixtures if item["id"] == "FIX-DL-004"))

        url = next(item for item in cases if item["type"] == "url")
        parsed = urlsplit(url["payload"])
        self.assertEqual(parsed.username, "campus.example.test")
        self.assertEqual(parsed.hostname, "download.example.test")
        self.assertTrue(parsed.path.endswith(".apk"))
        self.assertTrue(all(item["payload"].count("example.test") >= 1 for item in cases))


if __name__ == "__main__":
    unittest.main()
