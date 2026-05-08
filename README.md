# MyMenuMind

MyMenuMind is a native macOS menu bar app for mymind. It lets you search your mind, open the 10 most recent items, and save a quick note without opening a browser.

## Features

- Search mymind with the same query syntax used by `access.mymind.com`, including shortcuts like `tag:reading`, `type:image`, `"exact phrase"`, `cats || dogs`, `shoes -red`, `object:car`, `text:car`, and `format:pdf`.
- Show the top 10 recent items returned by the mymind objects API.
- Open the best available target for an item: raw asset URL, original source URL, top-level URL, then mymind object URL.
- Save quick notes as `text/markdown` mymind objects.
- Store credentials in the macOS Keychain instead of source files or `UserDefaults`.

## Requirements

- macOS 14 or newer
- Swift 6 toolchain / Xcode command line tools
- A mymind Extensions access key

## Run Locally

```sh
swift run MyMenuMind
```

The app runs as a menu bar accessory and does not show a Dock icon. Click the brain icon in the macOS menu bar to open it.

To create a local `.app` bundle:

```sh
Scripts/package-app.sh
```

The bundle is written to `.build/MyMenuMind.app`.

## Configure

Open `Settings` in the popover and set:

- `Access key ID`: the `kid` from the mymind Extensions access key.
- `Access key secret`: the base64-encoded secret from that access key.
- `Base URL`: defaults to `https://api.mymind.com`.
- `User-Agent`: defaults to `MyMenuMind/0.1.0`.
- `API Version`: defaults to `0.1`.
- `Object URL template`: defaults to `https://access.mymind.com/objects/{id}`.

The access key ID and secret are saved in macOS Keychain with device-local accessibility. Other settings are saved in `UserDefaults`.

Use the narrowest key permissions you can:

- Search and recent items require read access.
- Quick notes require write access.

## API Behavior

The implementation follows the official mymind API docs at `https://access.mymind.com/api`. When checking those docs from automation, use a real `GET` with browser-style headers; `HEAD` returns `405 Allow: GET`.

- Every request signs a fresh HS256 JWT using the access key secret.
- JWT header: `{ "alg": "HS256", "kid": "<access key id>" }`.
- JWT claims include uppercase `method`, request `path` without query string, `iat`, and `exp`.
- The signed JWT is sent as `Authorization: Bearer <jwt>`.
- `User-Agent` is sent on every request.
- `API-Version: 0.1` is sent on every request so the beta API is pinned.
- Search uses `GET /search?q=<query>&limit=<limit>`, then resolves matched IDs with `GET /objects?id=<id>...`.
- Recent items use `GET /objects?limit=10&contentAs=text/markdown`, assuming the API returns the most recently bumped objects first. The app keeps API order for equal or missing timestamps.
- Quick notes use `POST /objects`.

Quick notes are sent as JSON:

```json
{
  "content": {
    "type": "text/markdown",
    "body": "Your note"
  }
}
```

The item parser accepts common response envelopes:

- top-level arrays
- `{ "items": [...] }`
- `{ "data": [...] }`
- `{ "data": { "results": [...] } }`
- `{ "results": [...] }`
- `{ "cards": [...] }`

## Verify

```sh
swift test
Scripts/check-release-ready.sh
```

The release check runs tests, builds the app bundle, ensures local-only artifacts are not in the publishable file set, and scans publishable files for common secret patterns.

## Public Publishing Checklist

Before pushing this repository publicly:

1. Run `Scripts/check-release-ready.sh`.
2. Confirm `git status --short --ignored` shows `.env`, `.claude/`, `.build/`, and `mymind-api-docs/` as ignored.
3. Confirm only source, tests, docs, scripts, resources, and GitHub workflow files are staged.
4. Never paste a real mymind access key into issues, pull requests, commit messages, logs, or docs.

## Publish Hygiene

This repository intentionally ignores local and generated files:

- `.env` and `.env.*`
- `.claude/`
- `.build/`
- `.swiftpm/`
- `mymind-api-docs/`

Do not commit API keys or generated app bundles. If a mymind key is exposed anywhere public, rotate it immediately.

## Archive API Docs

The scraper and audit tools are kept in `Scripts/`; the generated archive is ignored by Git.

```sh
python3 Scripts/scrape-mymind-api-docs.py --output mymind-api-docs
python3 Scripts/audit-mymind-api-docs-with-agent-browser.py mymind-api-docs
```

The scraper uses real `GET` requests with browser-style headers, crawls every discovered `https://access.mymind.com/api...` page, downloads docs-owned static assets from `static.accelerator.net`, and writes `manifest.json`, raw HTML/assets, extracted page text, and `all-content.txt`.

Coverage behavior:

- Starts at `https://access.mymind.com/api`.
- Probes `robots.txt`, `sitemap.xml`, `/api/sitemap.xml`, and `/api/llms.txt` for additional route discovery.
- Parses HTML links, HTML comments, CSS `url(...)`, and string URLs inside downloaded HTML/CSS/JS.
- Recurses through every discovered `/api...` page until the queue is empty.
- Fails the run if `max_urls` is reached before queues drain.
- Records `crawl_completed`, `unfetched_discovered_pages`, hashes, statuses, and failures in `manifest.json`.

The Agent Browser audit writes `rendered/`, `snapshots/`, `snapshots-full/`, `agent-browser-audit.json`, and `all-rendered-content.txt`. Prefer `all-rendered-content.txt` or `snapshots-full/` when you need what Agent Browser sees, because some code examples and the LLM instructions block are injected by JavaScript after the raw HTML loads.
