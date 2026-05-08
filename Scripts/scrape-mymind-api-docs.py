#!/usr/bin/env python3
import argparse
import hashlib
import html.parser
import json
import os
import re
import shutil
import sys
import time
import urllib.parse
import urllib.request
from dataclasses import dataclass, field
from pathlib import Path


START_URL = "https://access.mymind.com/api"
DOC_HOST = "access.mymind.com"
DOC_PREFIX = "/api"
USER_AGENT = "MyMenuMindDocsScraper/1.0 (+local archive)"
ASSET_HOSTS = {
    "static.accelerator.net",
}
DISCOVERY_URLS = [
    "https://access.mymind.com/robots.txt",
    "https://access.mymind.com/sitemap.xml",
    "https://access.mymind.com/api/sitemap.xml",
    "https://access.mymind.com/api/llms.txt",
]


@dataclass
class LinkSet:
    pages: set[str] = field(default_factory=set)
    assets: set[str] = field(default_factory=set)


class LinkExtractor(html.parser.HTMLParser):
    def __init__(self, base_url: str):
        super().__init__(convert_charrefs=True)
        self.base_url = base_url
        self.links = LinkSet()

    def handle_starttag(self, tag, attrs):
        attrs = dict(attrs)
        for attr in ["href", "src", "poster", "data-src"]:
            value = attrs.get(attr)
            if value:
                self._add(value, tag, attr)

        if "srcset" in attrs:
            for part in attrs["srcset"].split(","):
                url = part.strip().split(" ")[0]
                if url:
                    self._add(url, tag, "srcset")

    def _add(self, value: str, tag: str, attr: str):
        url = normalize_url(urllib.parse.urljoin(self.base_url, value))
        if not url:
            return

        if is_doc_page(url):
            self.links.pages.add(url)
        elif is_allowed_asset(url):
            self.links.assets.add(url)


class TextExtractor(html.parser.HTMLParser):
    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.skip_depth = 0
        self.parts = []

    def handle_starttag(self, tag, attrs):
        attrs = dict(attrs)
        classes = set(attrs.get("class", "").split())
        if tag in {"script", "style", "svg"} or "docs-sidebar" in classes:
            self.skip_depth += 1
        elif tag in {"h1", "h2", "h3", "p", "tr", "li", "pre", "div", "section"}:
            self.parts.append("\n")

    def handle_endtag(self, tag):
        if self.skip_depth:
            self.skip_depth -= 1
        elif tag in {"h1", "h2", "h3", "p", "tr", "li", "pre", "div", "section"}:
            self.parts.append("\n")

    def handle_data(self, data):
        if self.skip_depth:
            return
        text = data.strip()
        if text:
            self.parts.append(text)

    def text(self):
        text = " ".join(self.parts)
        text = re.sub(r"[ \t\r\f\v]+", " ", text)
        text = re.sub(r"\n\s+", "\n", text)
        text = re.sub(r"\n{3,}", "\n\n", text)
        return text.strip() + "\n"


def normalize_url(url: str) -> str | None:
    parsed = urllib.parse.urlparse(url)
    if parsed.scheme not in {"http", "https"}:
        return None

    parsed = parsed._replace(fragment="")
    parsed = parsed._replace(path=urllib.parse.quote(urllib.parse.unquote(parsed.path), safe="/:@"))
    if parsed.query:
        query_pairs = urllib.parse.parse_qsl(parsed.query, keep_blank_values=True)
        parsed = parsed._replace(query=urllib.parse.urlencode(query_pairs, doseq=True))

    return urllib.parse.urlunparse(parsed)


def normalize_discovered_url(value: str, base_url: str) -> str | None:
    value = value.strip().strip("\"'`")
    if not value or value.startswith(("#", "mailto:", "tel:", "javascript:", "data:")):
        return None
    return normalize_url(urllib.parse.urljoin(base_url, value))


def is_doc_page(url: str) -> bool:
    parsed = urllib.parse.urlparse(url)
    return parsed.scheme in {"http", "https"} and parsed.netloc == DOC_HOST and parsed.path.startswith(DOC_PREFIX)


def is_allowed_asset(url: str) -> bool:
    parsed = urllib.parse.urlparse(url)
    if parsed.scheme not in {"http", "https"}:
        return False
    if parsed.netloc not in ASSET_HOSTS:
        return False
    if parsed.netloc == DOC_HOST and parsed.path.startswith(DOC_PREFIX):
        return False
    return True


def url_to_path(output_dir: Path, url: str, content_type: str = "") -> Path:
    parsed = urllib.parse.urlparse(url)
    path = parsed.path.strip("/")
    if not path:
        path = "index"

    suffix = Path(path).suffix
    if path.endswith("/") or not suffix:
        if "html" in content_type or is_doc_page(url):
            path = path.rstrip("/") + ".html"
        else:
            path = path.rstrip("/") + ".bin"

    if parsed.query:
        query_hash = hashlib.sha256(parsed.query.encode("utf-8")).hexdigest()[:12]
        target = Path(path)
        path = str(target.with_name(f"{target.stem}__query_{query_hash}{target.suffix}"))

    safe_host = parsed.netloc.replace(":", "_")
    return output_dir / "raw" / safe_host / path


def text_path(output_dir: Path, url: str) -> Path:
    parsed = urllib.parse.urlparse(url)
    slug = parsed.path.strip("/").replace("/", "__") or "index"
    return output_dir / "text" / f"{slug}.txt"


def fetch(url: str, timeout: int, retries: int) -> tuple[int, str, bytes, str]:
    headers = {
        "User-Agent": USER_AGENT,
        "Accept": "text/html,application/xhtml+xml,application/json;q=0.9,text/css;q=0.8,*/*;q=0.7",
    }

    last_error = ""
    for attempt in range(retries + 1):
        request = urllib.request.Request(url, headers=headers, method="GET")
        try:
            with urllib.request.urlopen(request, timeout=timeout) as response:
                body = response.read()
                content_type = response.headers.get("Content-Type", "")
                final_url = normalize_url(response.geturl()) or url
                return response.status, content_type, body, final_url
        except urllib.error.HTTPError as error:
            body = error.read()
            content_type = error.headers.get("Content-Type", "")
            final_url = normalize_url(error.geturl()) or url
            return error.code, content_type, body, final_url
        except Exception as error:
            last_error = str(error)
            if attempt < retries:
                time.sleep(0.5 * (attempt + 1))

    raise RuntimeError(last_error)


def css_urls(css_text: str, base_url: str) -> set[str]:
    urls = set()
    for match in re.finditer(r"url\(([^)]+)\)", css_text):
        value = match.group(1).strip().strip("\"'")
        if not value or value.startswith("data:"):
            continue
        url = normalize_url(urllib.parse.urljoin(base_url, value))
        if url:
            urls.add(url)
    return urls


def urls_from_text(text: str, base_url: str) -> LinkSet:
    links = LinkSet()
    candidates = set()

    for match in re.finditer(r"https?://[^\s\"'`<>)]+", text):
        candidates.add(match.group(0))

    for match in re.finditer(r"['\"]((?:/api|/134|/fonts|https://static\.accelerator\.net)[^'\"<>\s]*)['\"]", text):
        candidates.add(match.group(1))

    for match in re.finditer(r"(?:href|src|poster|data-src)\s*=\s*['\"]([^'\"]+)['\"]", text):
        candidates.add(match.group(1))

    for candidate in candidates:
        url = normalize_discovered_url(candidate, base_url)
        if not url:
            continue
        if is_doc_page(url):
            links.pages.add(url)
        elif is_allowed_asset(url):
            links.assets.add(url)

    return links


def write_bytes(path: Path, body: bytes):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(body)


def write_text(path: Path, text: str):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text, encoding="utf-8")


def scrape(output_dir: Path, timeout: int, retries: int, max_urls: int):
    if output_dir.exists():
        shutil.rmtree(output_dir)

    (output_dir / "raw").mkdir(parents=True)
    (output_dir / "text").mkdir(parents=True)

    page_queue = [START_URL]
    asset_queue = []
    seen_pages = set()
    seen_assets = set()
    records = []
    failures = []
    discoveries = []

    for discovery_url in DISCOVERY_URLS:
        try:
            status, content_type, body, final_url = fetch(discovery_url, timeout=timeout, retries=retries)
        except Exception as error:
            discoveries.append({"url": discovery_url, "error": str(error)})
            continue

        discovery_path = output_dir / "discovery" / (urllib.parse.urlparse(discovery_url).path.strip("/").replace("/", "__") or "index")
        write_bytes(discovery_path, body)
        discovery_record = {
            "url": discovery_url,
            "final_url": final_url,
            "status": status,
            "content_type": content_type,
            "bytes": len(body),
            "local_path": str(discovery_path.relative_to(output_dir)),
        }

        if status < 400:
            text = body.decode("utf-8", errors="replace")
            links = urls_from_text(text, final_url)
            for page_url in sorted(links.pages):
                if page_url not in page_queue:
                    page_queue.append(page_url)
            discovery_record["discovered_pages"] = sorted(links.pages)
            discovery_record["discovered_assets"] = sorted(links.assets)

        discoveries.append(discovery_record)

    while (page_queue or asset_queue) and len(records) < max_urls:
        is_page = bool(page_queue)
        url = page_queue.pop(0) if is_page else asset_queue.pop(0)
        url = normalize_url(url)
        if not url:
            continue

        if is_page:
            if url in seen_pages:
                continue
            seen_pages.add(url)
        else:
            if url in seen_assets or not is_allowed_asset(url):
                continue
            seen_assets.add(url)

        try:
            status, content_type, body, final_url = fetch(url, timeout=timeout, retries=retries)
        except Exception as error:
            failures.append({"url": url, "error": str(error)})
            continue

        local_path = url_to_path(output_dir, final_url, content_type)
        write_bytes(local_path, body)

        record = {
            "url": url,
            "final_url": final_url,
            "status": status,
            "content_type": content_type,
            "bytes": len(body),
            "sha256": hashlib.sha256(body).hexdigest(),
            "kind": "page" if is_page else "asset",
            "local_path": str(local_path.relative_to(output_dir)),
        }
        records.append(record)

        if status >= 400:
            failures.append({"url": url, "status": status, "local_path": record["local_path"]})
            continue

        content_type_lower = content_type.lower()
        decoded = None
        if "html" in content_type_lower:
            decoded = body.decode("utf-8", errors="replace")
            extractor = LinkExtractor(final_url)
            extractor.feed(decoded)
            for page_url in sorted(extractor.links.pages):
                if page_url not in seen_pages and page_url not in page_queue:
                    page_queue.append(page_url)
            for asset_url in sorted(extractor.links.assets):
                if asset_url not in seen_assets and asset_url not in asset_queue and is_allowed_asset(asset_url):
                    asset_queue.append(asset_url)

            if is_page:
                write_text(text_path(output_dir, final_url), TextExtractor.from_html(decoded))

        if any(marker in content_type_lower for marker in ["html", "css", "javascript", "json", "text"]):
            decoded = decoded or body.decode("utf-8", errors="replace")
            links = urls_from_text(decoded, final_url)
            for page_url in sorted(links.pages):
                if page_url not in seen_pages and page_url not in page_queue:
                    page_queue.append(page_url)
            for asset_url in sorted(links.assets):
                if asset_url not in seen_assets and asset_url not in asset_queue and is_allowed_asset(asset_url):
                    asset_queue.append(asset_url)

        if "css" in content_type_lower:
            decoded = decoded or body.decode("utf-8", errors="replace")
            for asset_url in sorted(css_urls(decoded, final_url)):
                if asset_url not in seen_assets and asset_url not in asset_queue and is_allowed_asset(asset_url):
                    asset_queue.append(asset_url)

    hit_max_urls = bool(page_queue or asset_queue)
    if hit_max_urls:
        failures.append({
            "error": "max_urls reached before crawl queues drained",
            "remaining_page_queue": page_queue[:50],
            "remaining_asset_queue": asset_queue[:50],
        })

    fetched_pages = {
        record["url"]
        for record in records
        if record["kind"] == "page" and record["status"] < 400
    }
    discovered_pages = sorted(seen_pages | set(page_queue))
    unfetched_discovered_pages = sorted(set(discovered_pages) - fetched_pages)

    manifest = {
        "start_url": START_URL,
        "discovery_urls": DISCOVERY_URLS,
        "headers": {
            "User-Agent": USER_AGENT,
            "Accept": "text/html,application/xhtml+xml,application/json;q=0.9,text/css;q=0.8,*/*;q=0.7",
        },
        "created_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        "counts": {
            "pages": sum(1 for record in records if record["kind"] == "page"),
            "assets": sum(1 for record in records if record["kind"] == "asset"),
            "records": len(records),
            "failures": len(failures),
            "discovery_records": len(discoveries),
            "unfetched_discovered_pages": len(unfetched_discovered_pages),
        },
        "crawl_completed": not hit_max_urls and not unfetched_discovered_pages,
        "discovery_records": discoveries,
        "unfetched_discovered_pages": unfetched_discovered_pages,
        "records": records,
        "failures": failures,
    }
    write_text(output_dir / "manifest.json", json.dumps(manifest, indent=2, sort_keys=True) + "\n")

    all_content = [
        "# mymind API Docs - Extracted Content",
        "",
        f"Source: {START_URL}",
        "",
    ]
    for record in records:
        if record["kind"] != "page":
            continue
        page_text_path = text_path(output_dir, record["final_url"])
        if page_text_path.exists():
            all_content.extend([
                "",
                f"## {record['url']}",
                "",
                page_text_path.read_text(encoding="utf-8").strip(),
                "",
            ])

    for record in records:
        if record["local_path"].endswith("/api/scripts/code-examples.js"):
            code_examples_path = output_dir / record["local_path"]
            if code_examples_path.exists():
                all_content.extend([
                    "",
                    "## API Code Examples Source",
                    "",
                    code_examples_path.read_text(encoding="utf-8").strip(),
                    "",
                ])
    write_text(output_dir / "all-content.txt", "\n".join(all_content).strip() + "\n")

    index_lines = [
        "# mymind API Docs Archive",
        "",
        f"Start URL: {START_URL}",
        f"Fetched pages: {manifest['counts']['pages']}",
        f"Fetched assets: {manifest['counts']['assets']}",
        f"Failures: {manifest['counts']['failures']}",
        f"Crawl completed: {manifest['crawl_completed']}",
        "",
        "Combined extracted text: `all-content.txt`",
        "",
        "## Pages",
    ]
    for record in records:
        if record["kind"] == "page":
            index_lines.append(f"- [{record['url']}]({record['local_path']})")
    write_text(output_dir / "README.md", "\n".join(index_lines) + "\n")

    return manifest


def text_from_html(html: str) -> str:
    extractor = TextExtractor()
    extractor.feed(html)
    return extractor.text()


TextExtractor.from_html = staticmethod(text_from_html)


def main():
    parser = argparse.ArgumentParser(description="Archive the mymind API docs locally.")
    parser.add_argument("--output", default="mymind-api-docs", help="Output directory")
    parser.add_argument("--timeout", type=int, default=30, help="Request timeout in seconds")
    parser.add_argument("--retries", type=int, default=2, help="Retries for transient network errors")
    parser.add_argument("--max-urls", type=int, default=1000, help="Safety cap for fetched URLs")
    args = parser.parse_args()

    output_dir = Path(args.output).resolve()
    manifest = scrape(output_dir, args.timeout, args.retries, args.max_urls)
    print(json.dumps(manifest["counts"], indent=2, sort_keys=True))

    if manifest["failures"]:
        print(f"Wrote archive with {len(manifest['failures'])} failures: {output_dir}", file=sys.stderr)
        return 1

    print(f"Wrote complete archive: {output_dir}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
