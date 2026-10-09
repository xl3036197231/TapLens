import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "tool"))
import generate_qr_sample_index as generator  # noqa: E402


class QrSampleIndexGeneratorTests(unittest.TestCase):
    def test_catalog_builds_exact_qr02_to_qr13_hash_index(self):
        index = generator.build_index()
        self.assertEqual(len(index), 12)
        self.assertEqual(
            {entry["sample_id"] for entry in index.values()},
            set(generator.SAMPLE_IDS),
        )
        self.assertTrue(
            all(entry["catalog_schema_version"] == "2.0" for entry in index.values())
        )
        self.assertTrue(
            all(entry["catalog_revision"] == "2026-10-09.1" for entry in index.values())
        )
        rendered = generator.render_dart(index)
        self.assertNotIn("intent://", rendered)
        self.assertNotIn("WIFI:", rendered)
        self.assertNotIn("payload'", rendered)

    def test_generation_is_deterministic(self):
        index = generator.build_index()
        self.assertEqual(generator.render_dart(index), generator.render_dart(index))


if __name__ == "__main__":
    unittest.main()
