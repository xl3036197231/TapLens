from functools import partial
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import urlsplit


DEFAULT_REDIRECT_FROM = "/go/campus"
DEFAULT_REDIRECT_TO = "/campus-login.html"


class ControlledSiteRequestHandler(SimpleHTTPRequestHandler):
    def __init__(
        self,
        *args,
        directory: str,
        redirect_from: str,
        redirect_to: str,
        **kwargs,
    ) -> None:
        self.redirect_from = redirect_from
        self.redirect_to = redirect_to
        super().__init__(*args, directory=directory, **kwargs)

    def do_GET(self) -> None:
        if urlsplit(self.path).path == self.redirect_from:
            self.send_response(302)
            self.send_header("Location", self.redirect_to)
            self.send_header("Cache-Control", "no-store")
            self.end_headers()
            return
        super().do_GET()

    def log_message(self, format: str, *args: object) -> None:
        return


def create_controlled_site_server(
    *,
    directory: Path,
    port: int,
    redirect_from: str = DEFAULT_REDIRECT_FROM,
    redirect_to: str = DEFAULT_REDIRECT_TO,
) -> ThreadingHTTPServer:
    resolved_directory = directory.resolve(strict=True)
    if not resolved_directory.is_dir():
        raise ValueError("controlled site directory must be a directory")
    if not redirect_from.startswith("/") or not redirect_to.startswith("/"):
        raise ValueError("redirect paths must be absolute paths")
    handler = partial(
        ControlledSiteRequestHandler,
        directory=str(resolved_directory),
        redirect_from=redirect_from,
        redirect_to=redirect_to,
    )
    server = ThreadingHTTPServer(("127.0.0.1", port), handler)
    server.daemon_threads = True
    return server
