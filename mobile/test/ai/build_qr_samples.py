"""Generate and decode-verify Day 4 synthetic QR PNGs with OpenCV.

Requires: pip install opencv-python-headless (or an existing cv2 install).
Live Codespaces URLs are accepted only through --url and written outside this
fixture directory; never commit the resulting PNG or the temporary URL.
"""

from __future__ import annotations

import argparse
import json
import re
from pathlib import Path
from urllib.parse import urlsplit

import cv2


HERE = Path(__file__).resolve().parents[3] / "shared" / "datasets" / "qr"
MANIFEST = HERE / "manifest.json"
REPO_ROOT = HERE.parents[2]


def _decode(path: Path) -> str:
    image = cv2.imread(str(path), cv2.IMREAD_GRAYSCALE)
    if image is None:
        raise ValueError(f"missing or invalid PNG: {path}")
    value, _, _ = cv2.QRCodeDetector().detectAndDecode(image)
    if not value:
        raise ValueError(f"QR cannot be decoded: {path}")
    return value


def _render(payload: str, path: Path, *, overwrite: bool = False) -> None:
    if path.exists() and not overwrite:
        if _decode(path) == payload:
            return
        raise ValueError(f"refusing to overwrite different QR: {path}")
    matrix = cv2.QRCodeEncoder_create().encode(payload)
    matrix = cv2.copyMakeBorder(matrix, 4, 4, 4, 4, cv2.BORDER_CONSTANT, value=255)
    matrix = cv2.resize(matrix, None, fx=12, fy=12, interpolation=cv2.INTER_NEAREST)
    path.parent.mkdir(parents=True, exist_ok=True)
    if not cv2.imwrite(str(path), matrix):
        raise ValueError(f"could not write PNG: {path}")
    if _decode(path) != payload:
        raise ValueError(f"generated QR payload mismatch: {path}")


def _cases() -> list[dict]:
    cases = json.loads(MANIFEST.read_text(encoding="utf-8"))["cases"]
    if len({case["id"] for case in cases}) != len(cases):
        raise ValueError("duplicate QR case ID")
    if len({case["png"] for case in cases}) != len(cases):
        raise ValueError("duplicate QR PNG path")
    for case in cases:
        relative = Path(case["png"])
        if relative.is_absolute() or relative.parts[0] != "png" or ".." in relative.parts:
            raise ValueError("QR PNG path must remain in png/")
    return cases


def _live_url(url: str) -> str:
    parsed = urlsplit(url)
    hostname = parsed.hostname or ""
    if (
        parsed.scheme != "https"
        or not re.fullmatch(r"[a-z0-9-]+-8765\.app\.github\.dev", hostname)
        or parsed.path != "/go/campus"
        or parsed.port is not None
        or parsed.username is not None
        or parsed.password is not None
        or parsed.query
        or parsed.fragment
    ):
        raise ValueError("expected today's HTTPS Codespaces controlled /go/campus URL")
    return url


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    command = parser.add_subparsers(dest="command", required=True)
    command.add_parser("generate-static")
    command.add_parser("verify")
    live = command.add_parser("generate-live")
    live.add_argument("--url", required=True)
    live.add_argument("--output", required=True, type=Path)
    live.add_argument("--overwrite", action="store_true")
    args = parser.parse_args()

    if args.command == "generate-live":
        url = _live_url(args.url)
        output = args.output.resolve()
        if output == REPO_ROOT or REPO_ROOT in output.parents:
            raise ValueError("live QR must be saved outside the repository")
        _render(url, output, overwrite=args.overwrite)
        print("LIVE QR VERIFIED: 1 temporary controlled URL; do not commit the PNG")
        return

    cases = _cases()
    for case in cases:
        path = HERE / case["png"]
        if args.command == "generate-static":
            _render(case["payload"], path)
        if _decode(path) != case["payload"]:
            raise ValueError(f"manifest/PNG mismatch: {case['id']}")
    print(f"STATIC QR VERIFIED: {len(cases)} manifest payloads match PNGs")


if __name__ == "__main__":
    main()
