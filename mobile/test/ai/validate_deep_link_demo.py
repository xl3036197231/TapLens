"""Keep the realistic web demo tied to D's canonical constructed fixtures."""

from __future__ import annotations

import json
from pathlib import Path


ROOT = Path(__file__).resolve().parents[3]
SITE = ROOT / "mobile" / "test" / "ai" / "day2_site"
FIXTURES = ROOT / "shared" / "datasets" / "constructed-fixtures" / "deep-link-fixtures.json"


def load(path: Path) -> list[dict]:
    with path.open(encoding="utf-8") as handle:
        return json.load(handle)


def main() -> None:
    canonical = {item["id"]: item for item in load(FIXTURES)}
    demo = load(SITE / "deep-link-demo-data.json")
    assert len(demo) == len(canonical) == 7
    assert {item["id"] for item in demo} == set(canonical)
    assert len({item["id"] for item in demo}) == len(demo)
    for item in demo:
        expected = canonical[item["id"]]
        for field in (
            "input",
            "expected_package_name",
            "expected_parse",
            "expected_local_ids",
            "expected_local_risk_hints",
        ):
            assert item[field] == expected[field], f"{item['id']}: {field} drifted"
        assert item["risk_label"] == expected["expected_risk_label"]
        assert all(item.get(field) for field in ("section", "title", "summary", "button", "interpretation"))

    for name in ("deep-link-demo.html", "deep-link-preview.html", "deep-link-demo.css", "deep-link-demo.js", "assets/deep-link-lecture-poster.svg"):
        assert (SITE / name).is_file(), f"missing demo asset: {name}"
    for name in ("deep-link-demo.html", "deep-link-preview.html"):
        markup = (SITE / name).read_text(encoding="utf-8")
        assert 'data-policy" content="test-only-no-external-launch"' in markup
        assert "deep-link-demo.js" in markup
        assert "deep-link-demo.css" in markup

    print("DEEP LINK DEMO CHECK PASSED: 7 canonical fixtures, 2 pages, local assets")


if __name__ == "__main__":
    main()
