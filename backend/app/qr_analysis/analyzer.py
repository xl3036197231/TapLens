from urllib.parse import parse_qs, unquote, urlsplit

from app.qr_analysis.catalog import CatalogCase
from app.qr_analysis.schemas import ServerEvidenceItem


class StaticQrAnalyzer:
    """Deterministic parser with no network or platform handlers."""

    def analyze(self, case: CatalogCase) -> tuple[list[ServerEvidenceItem], list[str]]:
        profile = case.analyzer_profile
        facts = {
            "intent": self._intent,
            "wifi": self._wifi,
            "sms": self._sms,
            "phone": self._phone,
            "email": self._email,
            "vcard": self._vcard,
            "apk_url": self._apk,
            "app_store": self._app_store,
            "plain_text": self._plain,
            "invalid": self._invalid,
            "http_claim_mismatch": self._claim_mismatch,
        }.get(profile)
        if facts is None:
            raise ValueError("unsupported QR analyzer profile")
        observations = facts(case)
        items = [
            ServerEvidenceItem(
                id=f"C{index:02d}",
                source="cloud",
                observation_mode="server_static",
                **observation,
            )
            for index, observation in enumerate(observations, start=1)
        ]
        return items, ["服务端只解析仓库固定文本；未访问目标、启动应用或执行系统动作。"]

    @staticmethod
    def _intent(case: CatalogCase) -> list[dict[str, str]]:
        payload = case.payload
        package = _intent_value(payload, "package")
        expected = case.expected_claim.get("expected_package_name")
        fallback = _intent_value(payload, "S.browser_fallback_url")
        return [
            {
                "kind": "intent_package_mismatch" if package != expected else "intent_package_match",
                "title": "目标包名不匹配" if package != expected else "目标包名匹配",
                "detail": "固定样例声明的目标包名与 TapLens 预期包名不同。" if package != expected else "固定样例声明的目标包名与预期包名一致。",
            },
            {
                "kind": "intent_fallback_present",
                "title": "存在浏览器 fallback",
                "detail": f"固定样例包含{urlsplit(unquote(fallback or '')).scheme.upper() or '未知协议'} fallback；服务端未访问该地址。",
            },
        ]

    @staticmethod
    def _wifi(case: CatalogCase) -> list[dict[str, str]]:
        fields = _delimited_fields(case.payload.removeprefix("WIFI:"))
        return [{"kind": "wifi_configuration", "title": "Wi-Fi 配置载荷", "detail": f"固定样例声明{fields.get('T', '未知')}加密，包含SSID和密码字段；服务端未连接网络。"}]

    @staticmethod
    def _sms(_: CatalogCase) -> list[dict[str, str]]:
        return [{"kind": "sms_action", "title": "预填短信载荷", "detail": "固定样例包含收件人与正文；具体值未进入证据，服务端未发送短信。"}]

    @staticmethod
    def _phone(_: CatalogCase) -> list[dict[str, str]]:
        return [{"kind": "phone_action", "title": "电话载荷", "detail": "固定样例包含电话号码；具体号码未进入证据，服务端未拨号。"}]

    @staticmethod
    def _email(case: CatalogCase) -> list[dict[str, str]]:
        query = parse_qs(urlsplit(case.payload).query)
        return [{"kind": "email_action", "title": "预填邮件载荷", "detail": f"固定样例包含收件人，{'包含' if query else '不包含'}主题或正文参数；具体值未进入证据，服务端未打开邮件应用。"}]

    @staticmethod
    def _vcard(case: CatalogCase) -> list[dict[str, str]]:
        fields = {line.partition(":")[0].split(";")[0] for line in case.payload.splitlines() if ":" in line}
        sensitive = len(fields & {"FN", "TEL", "EMAIL", "ADR", "ORG"})
        return [{"kind": "contact_card", "title": "联系人卡片", "detail": f"固定样例为 vCard，包含{sensitive}类敏感字段；具体值未进入证据，服务端未导入联系人。"}]

    @staticmethod
    def _apk(case: CatalogCase) -> list[dict[str, str]]:
        parsed = urlsplit(case.payload)
        return [{"kind": "apk_url", "title": "APK 下载地址", "detail": f"固定样例为{parsed.scheme.upper()}地址，路径表现为APK文件；服务端未做DNS或HTTP访问，也未下载文件。"}]

    @staticmethod
    def _app_store(_: CatalogCase) -> list[dict[str, str]]:
        return [{"kind": "app_store", "title": "应用商店载荷", "detail": "固定样例声明应用商店包名；服务端未打开商店或安装应用。"}]

    @staticmethod
    def _plain(case: CatalogCase) -> list[dict[str, str]]:
        return [{"kind": "plain_text", "title": "普通文本", "detail": f"固定样例是短文本，长度区间为{_length_bucket(len(case.payload))}；正文未复制到证据。"}]

    @staticmethod
    def _invalid(_: CatalogCase) -> list[dict[str, str]]:
        return [{"kind": "invalid_content", "title": "无法识别的格式", "detail": "固定样例不构成受支持的URL或系统动作格式；服务端未执行任何动作。"}]

    @staticmethod
    def _claim_mismatch(case: CatalogCase) -> list[dict[str, str]]:
        parsed = urlsplit(case.payload)
        claimed = case.expected_claim.get("claimed_app", "声明平台")
        return [{"kind": "http_claim_mismatch", "title": "宣传目标与载荷不一致", "detail": f"固定样例声称打开{claimed}，canonical payload 属于{parsed.hostname or '未知主机'}的HTTP(S)链接；服务端未访问该链接。"}]


def _intent_value(payload: str, key: str) -> str | None:
    marker = f"{key}="
    for part in payload.split(";"):
        if part.startswith(marker):
            return part[len(marker):]
    return None


def _delimited_fields(value: str) -> dict[str, str]:
    return {key: field for part in value.split(";") if ":" in part for key, _, field in [part.partition(":")]}


def _length_bucket(length: int) -> str:
    if length <= 50:
        return "1–50字符"
    if length <= 200:
        return "51–200字符"
    return "201字符以上"
