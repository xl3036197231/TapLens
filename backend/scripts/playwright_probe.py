import asyncio
import json
from pathlib import Path

from playwright.async_api import async_playwright


BACKEND_ROOT = Path(__file__).resolve().parents[1]
DEMO_PAGE = BACKEND_ROOT / "fixtures/demo_page.html"
SCREENSHOT_PATH = BACKEND_ROOT / "artifacts/playwright-probe.png"


async def run_probe() -> dict[str, object]:
    SCREENSHOT_PATH.parent.mkdir(parents=True, exist_ok=True)

    async with async_playwright() as playwright:
        browser = await playwright.chromium.launch(headless=True)
        context = await browser.new_context()
        page = await context.new_page()
        await page.goto(DEMO_PAGE.as_uri(), wait_until="domcontentloaded")

        form_fields = await page.locator("form input").evaluate_all(
            """
            elements => elements.map(element => ({
              name: element.getAttribute('name') || '',
              type: element.getAttribute('type') || 'text'
            }))
            """
        )
        result: dict[str, object] = {
            "title": await page.title(),
            "final_url": page.url,
            "form_fields": form_fields,
            "screenshot": str(SCREENSHOT_PATH),
        }
        await page.screenshot(path=str(SCREENSHOT_PATH), full_page=True)
        await context.close()
        await browser.close()

    return result


if __name__ == "__main__":
    print(json.dumps(asyncio.run(run_probe()), ensure_ascii=False, indent=2))
