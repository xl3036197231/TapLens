import argparse
import contextlib
from pathlib import Path

from app.sandbox.test_site_server import create_controlled_site_server


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Serve a controlled local fixture with a real HTTP redirect",
    )
    parser.add_argument("--directory", required=True, type=Path)
    parser.add_argument("--port", type=int, default=8765)
    parser.add_argument("--redirect-from", default="/go/campus")
    parser.add_argument("--redirect-to", default="/campus-login.html")
    return parser.parse_args()


if __name__ == "__main__":
    arguments = parse_args()
    server = create_controlled_site_server(
        directory=arguments.directory,
        port=arguments.port,
        redirect_from=arguments.redirect_from,
        redirect_to=arguments.redirect_to,
    )
    address, port = server.server_address
    print(f"Controlled site: http://{address}:{port}")
    print(f"Redirect entry: http://{address}:{port}{arguments.redirect_from}")
    with contextlib.suppress(KeyboardInterrupt):
        server.serve_forever()
    server.server_close()
