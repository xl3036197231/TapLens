from dataclasses import dataclass
from urllib.parse import urlsplit


@dataclass(frozen=True)
class FictionalFixture:
    scheme: str
    host: str
    path: str
    site_path: str


# These exact fictional inputs map to the repository's controlled campus page,
# served by the nginx service in compose.yaml. Unknown .test hosts still use
# normal DNS and SSRF validation.
_FIXTURES = {
    ("https", "scholarship.example.test", "/apply"): FictionalFixture(
        scheme="https",
        host="scholarship.example.test",
        path="/apply",
        site_path="/go/campus",
    ),
    ("https", "campus.example.test", "/go/campus"): FictionalFixture(
        scheme="https",
        host="campus.example.test",
        path="/go/campus",
        site_path="/go/campus",
    ),
    ("https", "short.example.test", "/go/campus"): FictionalFixture(
        scheme="https",
        host="short.example.test",
        path="/go/campus",
        site_path="/go/campus",
    ),
}

DEFAULT_FIXTURE_BASE_URL = "http://nginx:8080/controlled"
SIMULATED_FIXTURE_LIMITATION = (
    "模拟云端证据：虚构测试 URL 已映射到 TapLens 仓库内置受控页面；"
    "未解析或访问原始虚构域名，结果不代表该域名的真实网页行为。"
)


def fixture_for_url(url: str) -> FictionalFixture | None:
    """Return a fixture only for an exact, credential-free reserved test URL."""
    try:
        parsed = urlsplit(url)
        port = parsed.port
    except ValueError:
        return None

    if (
        parsed.scheme.casefold() != "https"
        or parsed.username is not None
        or parsed.password is not None
        or "?" in url
        or "#" in url
        or port is not None
        or parsed.hostname is None
    ):
        return None

    return _FIXTURES.get(
        (parsed.scheme.casefold(), parsed.hostname.casefold(), parsed.path)
    )
