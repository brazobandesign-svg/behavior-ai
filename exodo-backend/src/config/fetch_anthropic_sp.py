#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Fetch the official Anthropic Claude system prompts page and extract the
verbatim prompt text without rewriting, summarizing, or interpreting it.

Strategy:
1. Download the raw HTML from the official release notes URL.
2. Save the raw HTML locally for auditing.
3. Try multiple extraction strategies in order:
   a) The page text rendered as Server Components (parsed HTML body).
   b) The encoded RSC payload (Next.js __next_f.push chunks), which
      contains the literal prompt strings.
4. Write the extracted text to the target file in UTF-8.
"""
import json
import re
import sys
import time
from pathlib import Path
from urllib.parse import urlparse

import requests
from bs4 import BeautifulSoup

URL = "https://docs.anthropic.com/en/release-notes/system-prompts"
ALT_URL = "https://platform.claude.com/docs/en/release-notes/system-prompts"
RAW_HTML_PATH = Path(r"D:\Proyecto Behavior AI Exodo\exodo-app\exodo-backend\src\config\claude_system_prompt_raw.html")
OUT_PATH = Path(r"D:\Proyecto Behavior AI Exodo\exodo-app\exodo-backend\src\config\claude_system_prompt_raw.txt")

HEADERS = {
    "User-Agent": (
        "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 "
        "(KHTML, like Gecko) Chrome/130.0.0.0 Safari/537.36"
    ),
    "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
    "Accept-Language": "en-US,en;q=0.9",
    "Cache-Control": "no-cache",
    "Pragma": "no-cache",
}


def fetch(url: str) -> str:
    print(f"[fetch] GET {url}", flush=True)
    resp = requests.get(url, headers=HEADERS, timeout=60, allow_redirects=True)
    resp.raise_for_status()
    print(f"[fetch] status={resp.status_code} bytes={len(resp.content)} final={resp.url}", flush=True)
    return resp.text


def extract_from_rsc(html: str) -> str:
    """Next.js streams server-component output in __next_f.push([...]) calls.
    Each pushed chunk is a list; the second element is a string payload that
    may contain the literal text content (e.g. system prompts)."""
    chunks = re.findall(r"self\.__next_f\.push\(\[1,(?P<body>\"(?:\\.|[^\"\\])*\")\]\)", html, flags=re.DOTALL)
    if not chunks:
        # Fallback: any 1,"..." payload inside the streaming script.
        chunks = re.findall(r"self\.__next_f\.push\(\[1,\"(?P<body>(?:\\.|[^\"\\])*)\"\]\)", html, flags=re.DOTALL)
    decoded_chunks = []
    for raw in chunks:
        try:
            decoded = json.loads(raw)
        except json.JSONDecodeError:
            try:
                decoded = json.loads("[" + raw + "]")
            except json.JSONDecodeError:
                continue
        decoded_chunks.append(decoded)

    if not decoded_chunks:
        return ""

    # Each chunk is a serialized React tree fragment. Strip the React
    # Server Component markers and keep only the printable human text.
    text = "\n".join(decoded_chunks)
    # Remove template tag wrappers such as $L1234, $@1, etc.
    text = re.sub(r"\$[A-Za-z_][\w]*", "", text)
    # Drop JSON-only braces and quoted React props that carry no prose.
    text = re.sub(r"\\\"", "\"", text)
    return text


def extract_from_html(html: str) -> str:
    soup = BeautifulSoup(html, "html.parser")
    for tag in soup(["script", "style", "noscript", "svg", "template"]):
        tag.decompose()
    main = soup.find("main") or soup.find("article") or soup.body
    if main is None:
        return ""
    return main.get_text(separator="\n", strip=True)


def main() -> int:
    last_error: Exception | None = None
    html = ""
    for url in (URL, ALT_URL):
        try:
            html = fetch(url)
            if len(html) > 50_000:
                break
        except Exception as exc:  # noqa: BLE001
            print(f"[fetch] failed {url}: {exc}", flush=True)
            last_error = exc
    if not html:
        print("[error] no HTML retrieved", file=sys.stderr)
        if last_error:
            raise last_error
        return 2

    RAW_HTML_PATH.write_text(html, encoding="utf-8")
    print(f"[save] raw html -> {RAW_HTML_PATH} ({len(html):,} bytes)", flush=True)

    body_text = extract_from_html(html)
    rsc_text = extract_from_rsc(html)

    # Prefer the largest non-empty candidate that actually contains prose
    # (heuristic: at least one English sentence about a model release).
    candidates = [t for t in (body_text, rsc_text) if t and len(t) > 200]
    if not candidates:
        print("[error] could not extract any content", file=sys.stderr)
        return 3

    # Pick the candidate that contains the most signal about Claude versions
    def score(t: str) -> int:
        signals = ("Claude", "system prompt", "You are Claude", "Helpful")
        return sum(t.count(s) for s in signals) * 10 + min(len(t), 200_000)

    best = max(candidates, key=score)

    OUT_PATH.write_text(best, encoding="utf-8")
    chars = len(best)
    print(f"[save] extracted text -> {OUT_PATH} ({chars:,} chars)", flush=True)
    print("[preview] first 30 lines:", flush=True)
    for i, line in enumerate(best.splitlines()[:30], 1):
        print(f"  {i:>2}| {line}", flush=True)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
