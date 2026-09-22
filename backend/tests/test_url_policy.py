import pytest

from app.sandbox.url_policy import (
    UnsafeTargetError,
    resolve_and_validate_target,
    validate_resolved_addresses,
    validate_target_url,
)


@pytest.mark.parametrize(
    "url",
    [
        "file:///etc/passwd",
        "ftp://public.example/file",
        "http://localhost/",
        "http://service.local/",
        "http://metadata.google.internal/",
        "http://127.0.0.1/",
        "http://10.0.0.1/",
        "http://172.16.0.1/",
        "http://192.168.1.1/",
        "http://169.254.169.254/latest/meta-data/",
        "http://[::1]/",
        "http://[fd00:ec2::254]/",
        "https://user:password@public.example/",
        "https://public.example:99999/",
        "https://single-label/",
    ],
)
def test_target_policy_blocks_unsafe_url(url: str) -> None:
    with pytest.raises(UnsafeTargetError):
        validate_target_url(url)


@pytest.mark.parametrize(
    ("url", "expected_host", "expected_port"),
    [
        ("https://public.example/path", "public.example", 443),
        ("http://public.example:8080/path", "public.example", 8080),
        ("https://PUBLIC.EXAMPLE./path", "public.example", 443),
        ("https://8.8.8.8/", "8.8.8.8", 443),
        ("https://[2606:4700:4700::1111]/", "2606:4700:4700::1111", 443),
    ],
)
def test_target_policy_accepts_public_http_target(
    url: str,
    expected_host: str,
    expected_port: int,
) -> None:
    target = validate_target_url(url)

    assert target.hostname == expected_host
    assert target.port == expected_port


def test_dns_policy_rejects_mixed_public_and_private_answers() -> None:
    with pytest.raises(UnsafeTargetError) as captured:
        validate_resolved_addresses(["8.8.8.8", "127.0.0.1"])

    assert captured.value.code == "CLOUD_PRIVATE_ADDRESS_BLOCKED"


def test_dns_policy_accepts_only_public_answers() -> None:
    validate_resolved_addresses(["8.8.8.8", "1.1.1.1", "2606:4700:4700::1111"])


def test_dns_policy_rejects_empty_answer() -> None:
    with pytest.raises(UnsafeTargetError) as captured:
        validate_resolved_addresses([])

    assert captured.value.code == "CLOUD_DNS_RESOLUTION_FAILED"


def test_exact_test_origin_allows_only_its_configured_port() -> None:
    allowed = ("http://127.0.0.1:8765",)
    target = validate_target_url(
        "http://127.0.0.1:8765/go/campus?token=redacted",
        allowed_test_origins=allowed,
    )

    assert resolve_and_validate_target(
        target,
        allowed_test_origins=allowed,
    ) == ("127.0.0.1",)

    with pytest.raises(UnsafeTargetError) as captured:
        validate_target_url(
            "http://127.0.0.1:8766/go/campus",
            allowed_test_origins=allowed,
        )

    assert captured.value.code == "CLOUD_PRIVATE_ADDRESS_BLOCKED"
