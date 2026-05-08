#!/usr/bin/env python3
import json
import re
import subprocess
import sys
import time
from pathlib import Path
from urllib.parse import urlparse


HEADERS = {
    "User-Agent": "MyMenuMindDocsAudit/1.0",
    "Accept": "text/html,application/xhtml+xml,application/json;q=0.9,*/*;q=0.8",
}


def slug_for_url(url: str) -> str:
    path = urlparse(url).path.strip("/").replace("/", "__") or "index"
    return path


def run_agent_browser(args, timeout=60) -> str:
    result = subprocess.run(
        ["agent-browser", *args],
        text=True,
        capture_output=True,
        timeout=timeout,
    )
    if result.returncode != 0:
        raise RuntimeError(result.stderr.strip() or result.stdout.strip())
    return result.stdout


def normalize(text: str) -> str:
    text = text.replace("\u00a0", " ")
    text = re.sub(r"\s+([.,:;!?])", r"\1", text)
    text = re.sub(r"\s+", " ", text)
    return text.strip().lower()


def page_title(rendered_text: str) -> str:
    nav_words = {
        "Introduction", "Authentication", "Access Control", "Rate Limits",
        "Error Handling", "RESOURCES", "Objects", "Spaces", "Tags",
        "Entities SOON", "TOOLS", "Convert", "Search", "REFERENCE",
        "Base Types", "SDKs WIP", "Supported Formats", "Markdown Support",
        "Prose WIP", "LLM Instructions WIP", "CODE LANGUAGE", "JavaScript",
        "Python", "Ruby", "PHP", "C#", "Swift", "Changelog", "API Terms",
    }
    for line in rendered_text.splitlines():
        stripped = line.strip()
        if stripped and stripped not in nav_words:
            return stripped
    return ""


def main():
    archive_dir = Path(sys.argv[1] if len(sys.argv) > 1 else "mymind-api-docs").resolve()
    manifest_path = archive_dir / "manifest.json"
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    pages = [record["url"] for record in manifest["records"] if record["kind"] == "page" and record["status"] < 400]

    rendered_dir = archive_dir / "rendered"
    snapshot_dir = archive_dir / "snapshots"
    full_snapshot_dir = archive_dir / "snapshots-full"
    rendered_dir.mkdir(parents=True, exist_ok=True)
    snapshot_dir.mkdir(parents=True, exist_ok=True)
    full_snapshot_dir.mkdir(parents=True, exist_ok=True)

    records = []
    failures = []
    headers_json = json.dumps(HEADERS, separators=(",", ":"))

    for url in pages:
        slug = slug_for_url(url)
        try:
            run_agent_browser(["--headers", headers_json, "open", url], timeout=60)
            try:
                run_agent_browser(["wait", "--load", "networkidle"], timeout=30)
            except Exception:
                # Static docs sometimes finish before networkidle resolves cleanly.
                time.sleep(0.5)

            rendered_text = ""
            for _ in range(3):
                rendered_raw = run_agent_browser(["eval", "document.body.innerText"], timeout=60)
                rendered_text = json.loads(rendered_raw)
                if rendered_text.strip():
                    break
                time.sleep(1)
            (rendered_dir / f"{slug}.txt").write_text(rendered_text + "\n", encoding="utf-8")

            snapshot_text = run_agent_browser(["snapshot", "-i", "-u"], timeout=60)
            (snapshot_dir / f"{slug}.txt").write_text(snapshot_text, encoding="utf-8")
            full_snapshot_text = run_agent_browser(["snapshot"], timeout=60)
            (full_snapshot_dir / f"{slug}.txt").write_text(full_snapshot_text, encoding="utf-8")

            local_text_path = archive_dir / "text" / f"{slug}.txt"
            local_text = local_text_path.read_text(encoding="utf-8") if local_text_path.exists() else ""
            local_norm = normalize(local_text)
            rendered_norm = normalize(rendered_text)

            local_covers_rendered = rendered_norm in local_norm
            rendered_covers_local = local_norm in rendered_norm
            overlap_ratio = 0.0
            if rendered_norm:
                rendered_tokens = set(rendered_norm.split())
                local_tokens = set(local_norm.split())
                overlap_ratio = len(rendered_tokens & local_tokens) / len(rendered_tokens)

            records.append({
                "url": url,
                "slug": slug,
                "page_title": page_title(rendered_text),
                "rendered_text_path": str((rendered_dir / f"{slug}.txt").relative_to(archive_dir)),
                "interactive_snapshot_path": str((snapshot_dir / f"{slug}.txt").relative_to(archive_dir)),
                "full_snapshot_path": str((full_snapshot_dir / f"{slug}.txt").relative_to(archive_dir)),
                "local_text_path": str(local_text_path.relative_to(archive_dir)) if local_text_path.exists() else None,
                "rendered_chars": len(rendered_text),
                "local_chars": len(local_text),
                "local_covers_rendered": local_covers_rendered,
                "rendered_covers_local": rendered_covers_local,
                "token_overlap_ratio": round(overlap_ratio, 4),
                "has_rendered_code": "const " in rendered_text or "func " in rendered_text or "curl " in rendered_text,
                "has_local_code": "const " in local_text or "func " in local_text or "curl " in local_text,
            })
        except Exception as error:
            failures.append({"url": url, "error": str(error)})

    report = {
        "created_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        "headers": HEADERS,
        "counts": {
            "pages": len(pages),
            "records": len(records),
            "failures": len(failures),
            "local_text_exact_mirrors": sum(1 for record in records if record["local_covers_rendered"] and record["rendered_covers_local"]),
            "rendered_code_pages": sum(1 for record in records if record["has_rendered_code"]),
            "local_code_pages": sum(1 for record in records if record["has_local_code"]),
        },
        "records": records,
        "failures": failures,
    }
    (archive_dir / "agent-browser-audit.json").write_text(json.dumps(report, indent=2, sort_keys=True) + "\n", encoding="utf-8")

    rendered_content = [
        "# mymind API Docs - Agent Browser Rendered Content",
        "",
        "This file is generated from live `document.body.innerText` after Agent Browser loads each docs page.",
        "",
    ]
    for record in records:
        rendered_path = archive_dir / record["rendered_text_path"]
        rendered_content.extend([
            "",
            f"## {record['url']}",
            "",
            rendered_path.read_text(encoding="utf-8").strip(),
            "",
        ])
    (archive_dir / "all-rendered-content.txt").write_text("\n".join(rendered_content).strip() + "\n", encoding="utf-8")

    print(json.dumps(report["counts"], indent=2, sort_keys=True))
    if failures:
        print(json.dumps(failures, indent=2), file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
