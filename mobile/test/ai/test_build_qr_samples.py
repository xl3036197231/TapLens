"""Verify shared QR images and temporary live-generator boundaries."""

import tempfile
import unittest
from pathlib import Path

from build_qr_samples import HERE, _cases, _decode, _live_url, _render


class QrSamplesTest(unittest.TestCase):
    def test_manifest_matches_every_png(self) -> None:
        cases = _cases()
        self.assertGreaterEqual(len(cases), 10)
        for case in cases:
            with self.subTest(case=case["id"]):
                self.assertEqual(_decode(HERE / case["png"]), case["payload"])
                self.assertFalse(case["allow_cloud"])

    def test_temporary_controlled_url_can_be_generated_and_decoded(self) -> None:
        url = "https://example-8765.app.github.dev/go/campus"
        with tempfile.TemporaryDirectory() as folder:
            image = Path(folder) / "live.png"
            _render(_live_url(url), image)
            self.assertEqual(_decode(image), url)

    def test_live_generator_rejects_uncontrolled_or_sensitive_urls(self) -> None:
        invalid = (
            "http://example-8765.app.github.dev/go/campus",
            "https://example-8765.app.github.dev/other",
            "https://example-8765.app.github.dev/go/campus?token=TEST",
            "https://user:pass@example-8765.app.github.dev/go/campus",
            "https://campus.example.test/go/campus",
        )
        for url in invalid:
            with self.subTest(url=url), self.assertRaises(ValueError):
                _live_url(url)


if __name__ == "__main__":
    unittest.main()
