#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Build a structured Markdown document from the raw Claude system prompt text.

The official Anthropic System Prompts release-notes page only ships the
full verbatim text for the two newest models (Claude Opus 5 and Claude
Fable 5). Older model versions are listed with a release date but their
prompt body is not published on this page — they are jump-to anchors
without content. This script reflects that reality accurately instead of
synthesizing fake "prompt bodies" for the older anchors.

Output: D:\\Proyecto Behavior AI Exodo\\exodo-app\\exodo-backend\\src\\config\\claude_system_prompts_official.md
"""
from __future__ import annotations

import re
from datetime import date
from pathlib import Path

RAW_PATH = Path(r"D:\Proyecto Behavior AI Exodo\exodo-app\exodo-backend\src\config\claude_system_prompt_raw.txt")
OUT_PATH = Path(r"D:\Proyecto Behavior AI Exodo\exodo-app\exodo-backend\src\config\claude_system_prompts_official.md")
RENDERED_HTML = Path(r"D:\Proyecto Behavior AI Exodo\exodo-app\exodo-backend\src\config\claude_system_prompt_rendered.html")

MODELS = ["Opus", "Sonnet", "Haiku", "Fable", "Mythos"]
MODEL_HEADER = re.compile(
    r"^Claude (?P<model>" + "|".join(MODELS) + r") (?P<version>[0-9][0-9.]*)\s*$"
)
DATE_HEADER = re.compile(
    r"^(?P<month>January|February|March|April|May|June|July|August|"
    r"September|October|November|December) (?P<day>\d{1,2}), (?P<year>\d{4})\s*$"
)
MONTH_ORDER = {
    "January": 1, "February": 2, "March": 3, "April": 4, "May": 5, "June": 6,
    "July": 7, "August": 8, "September": 9, "October": 10, "November": 11, "December": 12,
}

# Minimum body size to consider a section a real verbatim prompt.
# The official page emits 17-50 char placeholder "bodies" for older models
# that are actually just empty accordion sections; the real prompts are
# multi-KB. Anything under 500 chars is treated as a placeholder.
MIN_BODY_CHARS = 500


def parse_full_prompts(text: str) -> list[dict]:
    """Walk the raw text and pull out only sections that have a real body
    (>= MIN_BODY_CHARS characters). Each returned record has model,
    version, date, date_iso, body."""
    lines = text.splitlines()
    n = len(lines)
    records: list[dict] = []
    i = 0
    pending_model: str | None = None
    pending_version: str | None = None
    pending_date: str | None = None
    pending_date_iso: str | None = None
    pending_body: list[str] = []

    def flush() -> None:
        nonlocal pending_model, pending_version, pending_date, pending_date_iso, pending_body
        if (
            pending_model
            and pending_version
            and pending_date
            and pending_body
            and sum(len(s) for s in pending_body) >= MIN_BODY_CHARS
        ):
            records.append(
                {
                    "model": pending_model,
                    "version": pending_version,
                    "date": pending_date,
                    "date_iso": pending_date_iso or "",
                    "body": "\n".join(pending_body).rstrip(),
                }
            )
        pending_model = None
        pending_version = None
        pending_date = None
        pending_date_iso = None
        pending_body = []

    while i < n:
        line = lines[i]
        m_model = MODEL_HEADER.match(line)
        if m_model:
            flush()
            pending_model = m_model["model"]
            pending_version = m_model["version"]
            i += 1
            continue
        m_date = DATE_HEADER.match(line)
        if m_date:
            pending_date = m_date.group(0).strip()
            pending_date_iso = (
                f"{int(m_date['year']):04d}-{MONTH_ORDER[m_date['month']]:02d}-{int(m_date['day']):02d}"
            )
            i += 1
            if i < n and lines[i].strip() == "":
                i += 1
            while i < n and not MODEL_HEADER.match(lines[i]):
                pending_body.append(lines[i])
                i += 1
            flush()
            continue
        i += 1
    flush()
    return records


def parse_version_index(text: str) -> list[dict]:
    """Extract the table-of-contents-style index that appears at the bottom
    of the page: a list of `<Model> <version>` followed by one or more
    dates. No prompt body is shipped for these — they are just anchors."""
    lines = text.splitlines()
    n = len(lines)
    items: list[dict] = []
    i = 0
    # The index starts after the last </claude_behavior>.
    last_close = -1
    for k, line in enumerate(lines):
        if line.strip() == "</claude_behavior>":
            last_close = k
    if last_close >= 0:
        i = last_close + 1

    current: dict | None = None
    while i < n:
        line = lines[i]
        if (m := MODEL_HEADER.match(line)):
            if current is not None:
                items.append(current)
            current = {"model": m["model"], "version": m["version"], "dates": []}
            i += 1
            continue
        if current is not None and (m := DATE_HEADER.match(line)):
            current["dates"].append(
                f"{int(m['year']):04d}-{MONTH_ORDER[m['month']]:02d}-{int(m['day']):02d}"
            )
        # Stop when we reach the "Was this page helpful?" footer.
        if "Was this page helpful" in line:
            break
        i += 1
    if current is not None:
        items.append(current)
    return items


def model_sort_key(record: dict) -> tuple:
    family_order = {"Opus": 0, "Sonnet": 1, "Haiku": 2, "Fable": 3, "Mythos": 4}
    parts: list[int] = []
    for chunk in record["version"].split("."):
        try:
            parts.append(int(chunk))
        except ValueError:
            parts.append(0)
    while len(parts) < 3:
        parts.append(0)
    y, m, d = (int(x) for x in record["date_iso"].split("-"))
    return (family_order.get(record["model"], 99), -y, -m, -d, -parts[0], -parts[1], -parts[2])


def render(full: list[dict], index: list[dict], raw_meta: dict) -> str:
    today = date.today().isoformat()
    out: list[str] = []
    out.append("# Official Anthropic Claude System Prompts — Verbatim Reference")
    out.append("")
    out.append("> **Source of truth (verbatim, no edits):** `claude_system_prompt_raw.txt`")
    out.append("> **Captured from:** `https://docs.anthropic.com/en/release-notes/system-prompts`")
    out.append(f"> **Capture date:** {raw_meta['captured_at']}")
    out.append(
        f"> **Raw payload:** {raw_meta['chars']:,} chars / {raw_meta['lines']:,} lines / {raw_meta['bytes']:,} bytes (UTF-8)"
    )
    out.append(f"> **Document built:** {today}")
    out.append(
        "> **Fidelity rule:** every block under each `## Claude <Model> <Version>` heading is the "
        "**exact** text published by Anthropic in their Release Notes. No rephrasing, no "
        "summarization, no editorial commentary."
    )
    out.append("")
    out.append("---")
    out.append("")

    # What this page actually contains
    out.append("## What this document contains")
    out.append("")
    out.append(
        "The official Anthropic System Prompts release-notes page "
        "(`/docs/en/release-notes/system-prompts`) only ships the **full verbatim prompt text** "
        f"for the **{len(full)} most recent model** version"
        f"{'s' if len(full) != 1 else ''}:"
    )
    for r in full:
        out.append(f"- **Claude {r['model']} {r['version']}** — released {r['date']} ({len(r['body']):,} chars of prompt body)")
    out.append("")
    out.append(
        "All older model versions are listed on the same page as a **navigation index** (model "
        "name + release date) but their full prompt text is **not published** on this page — the "
        "official Anthropic site treats them as jump-to anchors without body content. This "
        "document reflects that reality: the older entries are reproduced below in the *Version "
        "index* section, with no synthesized prompt body."
    )
    out.append("")
    out.append("---")
    out.append("")

    # Page intro
    out.append("## Page header (verbatim)")
    out.append("")
    out.append("The page begins with the following description, which is part of Anthropic's "
                "official framing and is reproduced verbatim:")
    out.append("")
    intro = (
        "Claude's web interface (claude.ai) and mobile apps use a system prompt to provide "
        "up-to-date information, such as the current date, to Claude at the start of every "
        "conversation. The system prompt also encourages certain behaviors, such as always "
        "providing code snippets in Markdown. This prompt is periodically updated to improve "
        "Claude's responses. These system prompt updates do not apply to the Claude API. Where "
        "a model has multiple dated entries below, updates between versions are bolded. "
        "Starting with the Claude 4.6 generation, each model ID is a single fixed snapshot, "
        "so those models have one entry."
    )
    out.append("```text")
    out.append(intro)
    out.append("```")
    out.append("")
    out.append("---")
    out.append("")

    # Full prompt sections
    out.append("## Full verbatim prompts")
    out.append("")
    sorted_full = sorted(full, key=model_sort_key)
    for r in sorted_full:
        anchor = f"claude-{r['model'].lower()}-{r['version'].replace('.', '-')}-{r['date_iso']}"
        out.append(f"### Claude {r['model']} {r['version']}")
        out.append("")
        out.append(f"**Release date:** {r['date']} (`{r['date_iso']}`)  ")
        out.append(f"**Body size:** {len(r['body']):,} characters (verbatim from Anthropic)  ")
        out.append(f"**Anchor:** `#{anchor}`")
        out.append("")
        out.append("```text")
        out.append(r["body"].rstrip())
        out.append("```")
        out.append("")
        out.append("---")
        out.append("")

    # Version index
    out.append("## Version index (older model entries — no prompt body published)")
    out.append("")
    out.append(
        "The following entries appear on the official page as in-page navigation anchors. "
        "Each model name links to its own section header on the page, but **no verbatim prompt "
        "body is published for these versions on `/docs/en/release-notes/system-prompts`**. The "
        "date(s) listed below are the release date(s) referenced by Anthropic for that model "
        "snapshot."
    )
    out.append("")
    out.append("| Model | Release date(s) |")
    out.append("|---|---|")
    family_order = {"Opus": 0, "Sonnet": 1, "Haiku": 2, "Fable": 3, "Mythos": 4}

    def index_key(it: dict) -> tuple:
        parts: list[int] = []
        for chunk in it["version"].split("."):
            try:
                parts.append(int(chunk))
            except ValueError:
                parts.append(0)
        while len(parts) < 3:
            parts.append(0)
        return (
            family_order.get(it["model"], 99),
            -parts[0],
            -parts[1],
            -parts[2],
            it["model"],
        )

    for it in sorted(index, key=index_key):
        if not it["dates"]:
            dates = "—"
        else:
            dates = ", ".join(sorted(set(it["dates"]), reverse=True))
        out.append(f"| Claude {it['model']} {it['version']} | {dates} |")
    out.append("")
    out.append("---")
    out.append("")

    # Page footer
    out.append("## Page footer (verbatim)")
    out.append("")
    out.append("The page ends with a short feedback widget:")
    out.append("")
    out.append("```text")
    out.append("Was this page helpful?")
    out.append("```")
    out.append("")
    out.append("---")
    out.append("")

    # Provenance
    out.append("## Provenance & files")
    out.append("")
    out.append("| File | Path | Purpose |")
    out.append("|---|---|---|")
    out.append("| **Verbatim prompts (raw)** | `claude_system_prompt_raw.txt` | The exact text captured from the official page — single string per line, no scaffolding. |")
    out.append("| **This document** | `claude_system_prompts_official.md` | Human-readable version of the same content, organized by model and date. |")
    out.append("| **Raw HTML (unrendered)** | `claude_system_prompt_raw.html` | HTTP response straight from Anthropic (Next.js shell, ~1.5 MB). |")
    out.append("| **Rendered HTML** | `claude_system_prompt_rendered.html` | Same page after Selenium + Chrome hydration, with all accordions expanded. |")
    out.append("| **Screenshot** | `claude_system_prompt_raw.png` | Visual capture of the rendered page for audit. |")
    out.append("| **Capture script (worked)** | `render_anthropic_sp.py` | Re-runnable Selenium scraper. |")
    out.append("| **Capture script (failed)** | `fetch_anthropic_sp.py` | Reference only — the page is a SPA, not scrapable with `requests` alone. |")
    out.append("| **Build script (this doc)** | `build_sp_markdown.py` | Re-runnable: regenerates the Markdown from the raw text. |")
    out.append("")
    out.append("### How the capture was done")
    out.append("")
    out.append("1. `GET https://docs.anthropic.com/en/release-notes/system-prompts` with a desktop Chrome User-Agent (the request 302-redirects to `https://platform.claude.com/docs/en/release-notes/system-prompts`).")
    out.append("2. Render the page in headless Chrome via Selenium. The page is a Next.js Server Components app — `requests` alone only fetches the RSC shell, not the text.")
    out.append("3. Click every `button[aria-expanded=\"false\"]` to expand the Release Notes accordions so the full prompt body is in the DOM.")
    out.append("4. Walk the DOM with a custom recursive walker that preserves paragraph boundaries (`<p>`, `<div>`, `<li>`, headings) and strips `<script>`, `<style>`, `<nav>`, `<footer>`, `<header>`, `<aside>`, hidden nodes, and the search modal.")
    out.append("5. Save the literal text as UTF-8 (no BOM) at `claude_system_prompt_raw.txt`.")
    out.append("")
    out.append("### Why only 2 prompts are in the document")
    out.append("")
    out.append(
        "Anthropic's release-notes page is curated: it includes the **complete, current** "
        "system prompt for the two newest Claude web-app models (Opus 5 and Fable 5 as of "
        f"{raw_meta['captured_at']}). Older model versions are listed in a navigation index "
        "with their release dates, but their full prompts are not on this page. The HTML "
        "shows in-page anchor links (`#claude-opus-4`, `#claude-sonnet-4`, etc.) that scroll "
        "to a model-name header with no body content beneath it. This document preserves that "
        "structure faithfully instead of fabricating placeholder prompts."
    )
    out.append("")
    return "\n".join(out)


def main() -> int:
    raw = RAW_PATH.read_text(encoding="utf-8")
    full = parse_full_prompts(raw)
    index = parse_version_index(raw)
    print(f"[parse] {len(full)} full verbatim prompt sections (>= {MIN_BODY_CHARS} chars):", flush=True)
    for r in full:
        print(f"  - Claude {r['model']} {r['version']:>6} | {r['date']:>16} | {len(r['body']):>6} chars", flush=True)
    print(f"[parse] {len(index)} entries in version index:", flush=True)
    for it in index:
        dates = ",".join(it["dates"])
        print(f"  - Claude {it['model']:7} {it['version']:>6} | dates: {dates}", flush=True)

    raw_meta = {
        "captured_at": date.today().isoformat(),
        "chars": len(raw),
        "lines": len(raw.splitlines()),
        "bytes": len(raw.encode("utf-8")),
    }
    md = render(full, index, raw_meta)
    OUT_PATH.write_text(md, encoding="utf-8")
    print(
        f"[save] markdown -> {OUT_PATH} ({len(md):,} chars, {len(md.splitlines()):,} lines)",
        flush=True,
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
