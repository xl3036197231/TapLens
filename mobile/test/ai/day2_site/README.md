# Day 2 controlled test site

These pages are local, fictional fixtures for B's Playwright sandbox. They are
not a real phishing site and must not be deployed publicly.

| Case | Entry page | Expected behavior | Expected result |
|---|---|---|---|
| `day2-short-link-high-risk` | `short-link.html` | Redirects to `campus-login.html`; page exposes a fictional campus login form with a password field | High risk |
| `day2-safe-info` | `safe-info.html` | Stable informational page, no form, no external action | Low risk |
| `day2-insufficient` | `insufficient-evidence.html` | Page explicitly reports that the target content is unavailable and provides no verifiable behavior | Insufficient evidence |

The short-link case uses only `example.test` language and test-only values. The
form action is relative and must be blocked by the sandbox; no form submission
should leave the local test service.

B can serve this directory with any local static server and map the entry paths
to the URLs listed in `day2-scenarios.json`.
