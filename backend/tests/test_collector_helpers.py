import pytest

from app.sandbox.collector import (
    is_sensitive_field,
    normalize_method,
    origin_from_url,
    sanitize_url,
)


def test_sanitize_url_removes_query_and_fragment() -> None:
    assert (
        sanitize_url("https://Public.Example/path?token=secret#section")
        == "https://public.example/path"
    )


def test_sanitize_url_removes_embedded_credentials() -> None:
    assert sanitize_url("https://user:secret@public.example/path") == (
        "https://public.example/path"
    )


def test_origin_hides_path_and_query() -> None:
    assert origin_from_url("https://public.example:8443/path?token=secret") == (
        "https://public.example:8443"
    )


def test_origin_formats_ipv6_literal() -> None:
    assert origin_from_url("https://[2606:4700:4700::1111]/path") == (
        "https://[2606:4700:4700::1111]"
    )


@pytest.mark.parametrize(
    ("name", "field_type"),
    [
        ("password", "password"),
        ("identity_number", "text"),
        ("student_id", "text"),
        ("phone", "tel"),
        ("csrf_token", "hidden"),
    ],
)
def test_sensitive_field_detection(name: str, field_type: str) -> None:
    assert is_sensitive_field(name, field_type)


def test_normal_field_is_not_marked_sensitive() -> None:
    assert not is_sensitive_field("display_name", "text")


def test_unknown_http_method_is_normalized() -> None:
    assert normalize_method("PROPFIND") == "OTHER"
