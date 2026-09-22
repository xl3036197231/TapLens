import ipaddress
import socket
from dataclasses import dataclass
from urllib.parse import SplitResult, urlsplit


MAX_URL_LENGTH = 2048
BLOCKED_HOSTNAMES = {
    "instance-data",
    "metadata.google.internal",
    "metadata.google",
}
BLOCKED_HOST_SUFFIXES = (
    ".internal",
    ".lan",
    ".local",
    ".localhost",
)
BLOCKED_INFRASTRUCTURE_IPS = {
    ipaddress.ip_address("168.63.129.16"),
    ipaddress.ip_address("169.254.169.254"),
}


class UnsafeTargetError(ValueError):
    def __init__(self, code: str, message: str) -> None:
        super().__init__(message)
        self.code = code
        self.message = message


@dataclass(frozen=True)
class ValidatedTarget:
    url: str
    scheme: str
    hostname: str
    port: int


def validate_target_url(
    url: str,
    *,
    allowed_test_origins: tuple[str, ...] = (),
) -> ValidatedTarget:
    if not url or len(url) > MAX_URL_LENGTH or any(character.isspace() for character in url):
        raise UnsafeTargetError("CLOUD_URL_INVALID", "URL为空、过长或包含空白字符")

    parsed = urlsplit(url)
    if parsed.scheme.lower() not in {"http", "https"}:
        raise UnsafeTargetError("CLOUD_SCHEME_BLOCKED", "云端分析只接受http或https URL")
    if parsed.username is not None or parsed.password is not None:
        raise UnsafeTargetError("CLOUD_URL_CREDENTIALS_BLOCKED", "URL不得包含用户名或密码")
    if not parsed.hostname:
        raise UnsafeTargetError("CLOUD_URL_INVALID", "URL缺少主机名")

    hostname = normalize_hostname(parsed.hostname)
    try:
        port = parsed.port or (443 if parsed.scheme.lower() == "https" else 80)
    except ValueError as exc:
        raise UnsafeTargetError("CLOUD_URL_INVALID", "URL端口无效") from exc

    target = ValidatedTarget(
        url=url,
        scheme=parsed.scheme.lower(),
        hostname=hostname,
        port=port,
    )
    if target_origin(target) not in allowed_test_origins:
        literal_address = parse_ip_literal(hostname)
        if literal_address is not None:
            reject_unsafe_ip(literal_address)
        else:
            reject_blocked_hostname(hostname)
    return target


def resolve_and_validate_target(
    target: ValidatedTarget,
    *,
    allowed_test_origins: tuple[str, ...] = (),
) -> tuple[str, ...]:
    if target_origin(target) in allowed_test_origins:
        return (target.hostname,)
    try:
        records = socket.getaddrinfo(
            target.hostname,
            target.port,
            type=socket.SOCK_STREAM,
        )
    except socket.gaierror as exc:
        raise UnsafeTargetError("CLOUD_DNS_RESOLUTION_FAILED", "目标域名解析失败") from exc

    addresses = tuple(sorted({record[4][0] for record in records}))
    validate_resolved_addresses(addresses)
    return addresses


def target_origin(target: ValidatedTarget) -> str:
    host = f"[{target.hostname}]" if ":" in target.hostname else target.hostname
    return f"{target.scheme}://{host}:{target.port}"


def validate_resolved_addresses(addresses: tuple[str, ...] | list[str]) -> None:
    if not addresses:
        raise UnsafeTargetError("CLOUD_DNS_RESOLUTION_FAILED", "目标域名没有可用地址")
    for address in addresses:
        try:
            parsed_address = ipaddress.ip_address(address)
        except ValueError as exc:
            raise UnsafeTargetError("CLOUD_DNS_RESOLUTION_FAILED", "DNS返回了无效地址") from exc
        reject_unsafe_ip(parsed_address)


def normalize_hostname(hostname: str) -> str:
    normalized = hostname.rstrip(".").casefold()
    try:
        return normalized.encode("idna").decode("ascii")
    except UnicodeError as exc:
        raise UnsafeTargetError("CLOUD_URL_INVALID", "主机名编码无效") from exc


def reject_blocked_hostname(hostname: str) -> None:
    if hostname == "localhost" or hostname in BLOCKED_HOSTNAMES:
        raise UnsafeTargetError("CLOUD_PRIVATE_ADDRESS_BLOCKED", "目标主机不允许进入云沙箱")
    if hostname.endswith(BLOCKED_HOST_SUFFIXES) or "." not in hostname:
        raise UnsafeTargetError("CLOUD_PRIVATE_ADDRESS_BLOCKED", "本地或内部主机名不允许进入云沙箱")


def parse_ip_literal(hostname: str) -> ipaddress.IPv4Address | ipaddress.IPv6Address | None:
    try:
        return ipaddress.ip_address(hostname)
    except ValueError:
        return None


def reject_unsafe_ip(address: ipaddress.IPv4Address | ipaddress.IPv6Address) -> None:
    comparable_address = address.ipv4_mapped if isinstance(address, ipaddress.IPv6Address) else None
    address_to_check = comparable_address or address
    if address_to_check in BLOCKED_INFRASTRUCTURE_IPS or not address_to_check.is_global:
        raise UnsafeTargetError("CLOUD_PRIVATE_ADDRESS_BLOCKED", "私网、保留或基础设施地址不允许进入云沙箱")
