# Day 2 controlled test site

These pages are local, fictional fixtures for B's Playwright sandbox. They are
not a real phishing site and must not be deployed publicly.

| Case | Entry page | Expected behavior | Expected result |
|---|---|---|---|
| `day2-short-link-high-risk` | `short-link.html` | Redirects to `campus-login.html`; the local-only demo submit then opens `community-hub.html` | High risk |
| `day2-demo-post-login` | `community-hub.html` | Local-only terminal-style route monitor; no credentials are submitted | Redirect target reached |
| `day2-safe-info` | `safe-info.html` | Stable informational page, no form, no external action | Low risk |
| `day2-insufficient` | `insufficient-evidence.html` | Page explicitly reports that the target content is unavailable and provides no verifiable behavior | Insufficient evidence |

The short-link case uses only `example.test` language and test-only values. The
form action is relative and must be blocked by the sandbox; no form submission
should leave the local test service.

All visual assets are local SVG fixtures under `assets/`; no external images,
fonts, analytics, or third-party branding are loaded. The prominent training
fixture notice is intentionally retained on the login page.

The login form uses a local `onsubmit` handler that prevents transmission and
navigates to `community-hub.html` only to demonstrate the post-login redirect.

B can serve this directory with any local static server and map the entry paths
to the URLs listed in `day2-scenarios.json`.
