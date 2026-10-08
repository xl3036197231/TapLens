from app.sandbox.collector import _is_fixture_resource
from app.sandbox.fictional_fixture import fixture_for_url


def test_only_exact_known_fictional_urls_receive_fixture_mapping() -> None:
    mapped = fixture_for_url("https://campus.example.test/go/campus")

    assert mapped is not None
    assert mapped.site_path == "/go/campus"
    rejected = (
        "http://campus.example.test/go/campus",
        "https://campus.example.test/go/campus?source=poster",
        "https://campus.example.test/go/campus?",
        "https://campus.example.test/go/campus#fragment",
        "https://campus.example.test/go/campus#",
        "https://campus.example.test./go/campus",
        "https://campus.example.test:443/go/campus",
        "https://user@campus.example.test/go/campus",
        "https://campus.example.test/go/other",
        "https://other.example.test/go/campus",
    )
    assert all(fixture_for_url(url) is None for url in rejected)


def test_fixture_navigation_can_read_only_its_exact_internal_site_path() -> None:
    base_url = "http://nginx:8080/controlled"

    assert _is_fixture_resource(
        "http://nginx:8080/controlled/assets/example-campus-mark.svg",
        base_url,
    )
    assert not _is_fixture_resource(
        "https://nginx:8080/controlled/campus-login.html",
        base_url,
    )
    assert not _is_fixture_resource(
        "http://nginx:8080/controlled-elsewhere/page.html",
        base_url,
    )
    assert not _is_fixture_resource(
        "http://nginx:8080/controlled/%2e%2e/api/healthz",
        base_url,
    )
    assert not _is_fixture_resource(
        "http://example.com/controlled/campus-login.html",
        base_url,
    )
