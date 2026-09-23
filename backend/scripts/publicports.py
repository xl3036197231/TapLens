"""Make the temporary TapLens Codespaces integration ports public.

This development helper intentionally delegates authentication and permission
checks to the GitHub CLI already available inside the Codespace.
"""

from __future__ import annotations

import os
import subprocess


def main() -> None:
    codespace_name = os.environ.get("CODESPACE_NAME")
    if not codespace_name:
        raise SystemExit("CODESPACE_NAME is unavailable; run this inside GitHub Codespaces")

    subprocess.run(
        [
            "gh",
            "codespace",
            "ports",
            "visibility",
            "8000:public",
            "8765:public",
            "-c",
            codespace_name,
        ],
        check=True,
    )


if __name__ == "__main__":
    main()
