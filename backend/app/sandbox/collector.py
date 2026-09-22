import asyncio
from collections.abc import Awaitable, Callable
from dataclasses import dataclass
from pathlib import Path
from urllib.parse import SplitResult, urljoin, urlsplit, urlunsplit

from playwright.async_api import (
    Download,
    Error as PlaywrightError,
    Page,
    Request,
    Response,
    Route,
    TimeoutError as PlaywrightTimeoutError,
    async_playwright,
)

from app.sandbox.url_policy import (
    UnsafeTargetError,
    resolve_and_validate_target,
    validate_target_url,
)


RequestAuthorizer = Callable[[str], Awaitable[None]]
SAFE_HTTP_METHODS = {"GET", "HEAD", "OPTIONS"}
PASSIVE_SCHEMES = {"about", "blob", "data"}
SENSITIVE_FIELD_TOKENS = {
    "card",
    "credential",
    "email",
    "identity",
    "idcard",
    "national_id",
    "password",
    "phone",
    "student_id",
    "token",
}


class CollectorError(RuntimeError):
    def __init__(self, code: str, message: str) -> None:
        super().__init__(message)
        self.code = code
        self.message = message


@dataclass(frozen=True)
class CollectorLimits:
    navigation_timeout_ms: int = 15000
    max_requests: int = 200
    max_redirects: int = 10
    max_forms: int = 30
    max_fields_per_form: int = 50
    max_text_length: int = 2000


@dataclass(frozen=True)
class CollectorResult:
    final_url: str
    title: str
    text_summary: str
    redirects: list[dict[str, object]]
    requests: list[dict[str, object]]
    forms: list[dict[str, object]]
    blocked_actions: list[dict[str, object]]
    screenshot_path: Path
    limitations: list[str]


class DeepScanCollector:
    def __init__(
        self,
        *,
        artifact_directory: Path,
        limits: CollectorLimits | None = None,
        request_authorizer: RequestAuthorizer | None = None,
    ) -> None:
        self.artifact_directory = artifact_directory
        self.limits = limits or CollectorLimits()
        self.request_authorizer = request_authorizer or authorize_public_http_request

    async def collect(self, *, task_id: str, target_url: str) -> CollectorResult:
        self.artifact_directory.mkdir(parents=True, exist_ok=True)
        screenshot_path = self.artifact_directory / f"{task_id}.png"
        requests: list[dict[str, object]] = []
        redirects: list[dict[str, object]] = []
        blocked_actions: list[dict[str, object]] = []
        limitations: list[str] = []
        background_tasks: set[asyncio.Task[None]] = set()

        async with async_playwright() as playwright:
            browser = await playwright.chromium.launch(headless=True)
            context = await browser.new_context(
                accept_downloads=False,
                ignore_https_errors=False,
                service_workers="block",
            )
            page = await context.new_page()

            async def handle_route(route: Route) -> None:
                request = route.request
                scheme = urlsplit(request.url).scheme.casefold()
                if scheme in PASSIVE_SCHEMES:
                    await route.continue_()
                    return
                if scheme not in {"http", "https"}:
                    blocked_actions.append(
                        blocked_action("external_protocol", request.url, "阻止非HTTP外部协议")
                    )
                    await route.abort("blockedbyclient")
                    return
                if request.method.upper() not in SAFE_HTTP_METHODS:
                    blocked_actions.append(
                        blocked_action("business_post", request.url, "阻止可能改变业务状态的请求")
                    )
                    await route.abort("blockedbyclient")
                    return
                if len(requests) >= self.limits.max_requests:
                    if "请求数量达到上限，后续请求已阻止。" not in limitations:
                        limitations.append("请求数量达到上限，后续请求已阻止。")
                    await route.abort("blockedbyclient")
                    return
                try:
                    await self.request_authorizer(request.url)
                except UnsafeTargetError as exc:
                    blocked_actions.append(blocked_action("external_protocol", request.url, exc.message))
                    await route.abort("blockedbyclient")
                    return
                await route.continue_()

            async def close_popup(popup: Page) -> None:
                blocked_actions.append(blocked_action("popup", popup.url or None, "阻止页面打开新窗口"))
                await popup.close()

            def schedule(coroutine: Awaitable[None]) -> None:
                task = asyncio.create_task(coroutine)
                background_tasks.add(task)
                task.add_done_callback(background_tasks.discard)

            def record_request(request: Request) -> None:
                if len(requests) < self.limits.max_requests:
                    requests.append(
                        {
                            "origin": origin_from_url(request.url),
                            "method": normalize_method(request.method),
                            "resource_type": request.resource_type[:40],
                            "status_code": None,
                        }
                    )
            def record_response(response: Response) -> None:
                request = response.request
                for item in reversed(requests):
                    if item["origin"] == origin_from_url(request.url) and item["status_code"] is None:
                        item["status_code"] = response.status
                        break
                location = response.headers.get("location")
                if 300 <= response.status < 400 and location and len(redirects) < self.limits.max_redirects:
                    redirects.append(
                        {
                            "from_url": sanitize_url(response.url),
                            "to_url": sanitize_url(urljoin(response.url, location)),
                            "status_code": response.status,
                        }
                    )

            async def cancel_download(download: Download) -> None:
                blocked_actions.append(blocked_action("download", None, "阻止文件下载"))
                await download.cancel()

            await context.route("**/*", handle_route)
            context.on("request", record_request)
            context.on("response", record_response)
            page.on("download", lambda download: schedule(cancel_download(download)))
            context.on("page", lambda popup: schedule(close_popup(popup)) if popup != page else None)

            try:
                await page.goto(
                    target_url,
                    wait_until="domcontentloaded",
                    timeout=self.limits.navigation_timeout_ms,
                )
                forms = await extract_forms(
                    page,
                    max_forms=self.limits.max_forms,
                    max_fields=self.limits.max_fields_per_form,
                )
                title = (await page.title())[:300]
                text_summary = await extract_text_summary(page, self.limits.max_text_length)
                await page.screenshot(path=str(screenshot_path), full_page=True)
                final_url = sanitize_url(page.url)
            except PlaywrightTimeoutError as exc:
                raise CollectorError("CLOUD_TASK_TIMEOUT", "云端页面加载超时") from exc
            except PlaywrightError as exc:
                raise CollectorError("CLOUD_BROWSER_ERROR", "云端浏览器分析失败") from exc
            finally:
                if background_tasks:
                    await asyncio.gather(*background_tasks, return_exceptions=True)
                await context.close()
                await browser.close()

        return CollectorResult(
            final_url=final_url,
            title=title,
            text_summary=text_summary,
            redirects=redirects,
            requests=requests,
            forms=forms,
            blocked_actions=blocked_actions,
            screenshot_path=screenshot_path,
            limitations=limitations,
        )


async def authorize_public_http_request(url: str) -> None:
    target = validate_target_url(url)
    await asyncio.to_thread(resolve_and_validate_target, target)


def build_request_authorizer(
    allowed_test_origins: tuple[str, ...],
) -> RequestAuthorizer:
    async def authorize(url: str) -> None:
        target = validate_target_url(
            url,
            allowed_test_origins=allowed_test_origins,
        )
        await asyncio.to_thread(
            resolve_and_validate_target,
            target,
            allowed_test_origins=allowed_test_origins,
        )

    return authorize


async def extract_forms(page: Page, *, max_forms: int, max_fields: int) -> list[dict[str, object]]:
    raw_forms = await page.locator("form").evaluate_all(
        """
        (forms, limits) => forms.slice(0, limits.maxForms).map(form => ({
          action: form.action || null,
          method: (form.method || 'get').toUpperCase(),
          fields: Array.from(form.querySelectorAll('input, select, textarea'))
            .slice(0, limits.maxFields)
            .map(field => ({
              name: field.getAttribute('name') || '',
              type: (field.getAttribute('type') || field.tagName || 'text').toLowerCase()
            }))
        }))
        """,
        {"maxForms": max_forms, "maxFields": max_fields},
    )
    normalized: list[dict[str, object]] = []
    for form in raw_forms:
        fields = [
            {
                "name": str(field["name"])[:100],
                "type": str(field["type"])[:40],
                "sensitive": is_sensitive_field(str(field["name"]), str(field["type"])),
            }
            for field in form["fields"]
        ]
        method = str(form["method"]).upper()
        normalized.append(
            {
                "action": sanitize_http_url(form["action"]) if form["action"] else None,
                "method": method if method in {"GET", "POST"} else "OTHER",
                "fields": fields,
            }
        )
    return normalized


async def extract_text_summary(page: Page, max_length: int) -> str:
    text = await page.locator("body").inner_text(timeout=2000)
    return " ".join(text.split())[:max_length]


def is_sensitive_field(name: str, field_type: str) -> bool:
    searchable = f"{name} {field_type}".casefold()
    return any(token in searchable for token in SENSITIVE_FIELD_TOKENS)


def sanitize_url(url: str) -> str:
    parsed = urlsplit(url)
    if parsed.scheme.casefold() not in {"http", "https"}:
        return f"{parsed.scheme.casefold()}:"
    return urlunsplit(
        (
            parsed.scheme.casefold(),
            safe_netloc(parsed),
            parsed.path,
            "",
            "",
        )
    )


def sanitize_http_url(url: str) -> str | None:
    parsed = urlsplit(url)
    if parsed.scheme.casefold() not in {"http", "https"} or not parsed.hostname:
        return None
    return sanitize_url(url)


def origin_from_url(url: str) -> str:
    parsed = urlsplit(url)
    if parsed.scheme.casefold() not in {"http", "https"} or not parsed.hostname:
        return f"{parsed.scheme.casefold()}:"
    default_port = 443 if parsed.scheme.casefold() == "https" else 80
    port = parsed.port or default_port
    port_suffix = "" if port == default_port else f":{port}"
    hostname = parsed.hostname.casefold()
    host = f"[{hostname}]" if ":" in hostname else hostname
    return f"{parsed.scheme.casefold()}://{host}{port_suffix}"


def safe_netloc(parsed: SplitResult) -> str:
    if not parsed.hostname:
        return ""
    hostname = parsed.hostname.casefold()
    host = f"[{hostname}]" if ":" in hostname else hostname
    try:
        port = parsed.port
    except ValueError:
        port = None
    return f"{host}:{port}" if port is not None else host


def normalize_method(method: str) -> str:
    normalized = method.upper()
    return normalized if normalized in {"GET", "HEAD", "OPTIONS", "POST", "PUT", "PATCH", "DELETE"} else "OTHER"


def blocked_action(action_type: str, target: str | None, reason: str) -> dict[str, object]:
    return {
        "type": action_type,
        "target": sanitize_url(target) if target else None,
        "reason": reason[:300],
    }
