#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Render the official Anthropic System Prompts page in a real browser and
extract the visible text verbatim, without summarizing or rewriting.

Uses Selenium with the local Chrome installation (no driver download).
"""
import os
import sys
import time
from pathlib import Path

# Ensure the console can print the verbatim unicode content we extracted.
try:
    sys.stdout.reconfigure(encoding="utf-8")
except Exception:  # noqa: BLE001
    pass

from selenium import webdriver
from selenium.webdriver.chrome.options import Options
from selenium.webdriver.common.by import By
from selenium.webdriver.support import expected_conditions as EC
from selenium.webdriver.support.ui import WebDriverWait

URL = "https://docs.anthropic.com/en/release-notes/system-prompts"
OUT_PATH = Path(r"D:\Proyecto Behavior AI Exodo\exodo-app\exodo-backend\src\config\claude_system_prompt_raw.txt")
SCREENSHOT_PATH = OUT_PATH.with_suffix(".png")
RENDERED_HTML_PATH = OUT_PATH.with_name("claude_system_prompt_rendered.html")

CHROME_PATHS = [
    r"C:\Program Files\Google\Chrome\Application\chrome.exe",
    r"C:\Program Files (x86)\Google\Chrome\Application\chrome.exe",
    os.path.expandvars(r"%LOCALAPPDATA%\Google\Chrome\Application\chrome.exe"),
]


def find_chrome() -> str | None:
    for p in CHROME_PATHS:
        if Path(p).exists():
            return p
    return None


def open_all_accordions(driver: webdriver.Chrome) -> int:
    """Click every collapsed AccordionTrigger to reveal the prompt text."""
    opened = 0
    selectors = [
        'button[aria-expanded="false"][data-cds="AccordionTrigger"]',
        'button[aria-expanded="false"]',
        '[data-cds="AccordionTrigger"][aria-expanded="false"]',
    ]
    for sel in selectors:
        try:
            triggers = driver.find_elements(By.CSS_SELECTOR, sel)
        except Exception:  # noqa: BLE001
            triggers = []
        for t in triggers:
            try:
                if t.is_displayed():
                    driver.execute_script(
                        "arguments[0].scrollIntoView({block: 'center'});", t
                    )
                    t.click()
                    opened += 1
                    time.sleep(0.1)
            except Exception:  # noqa: BLE001
                # Force-click via JS to bypass overlay/intercept.
                try:
                    driver.execute_script("arguments[0].click();", t)
                    opened += 1
                except Exception:  # noqa: BLE001
                    pass
    return opened


def main() -> int:
    chrome_path = find_chrome()
    if not chrome_path:
        print("[error] Chrome not found in standard locations", file=sys.stderr)
        return 1

    print(f"[chrome] using {chrome_path}", flush=True)

    opts = Options()
    opts.binary_location = chrome_path
    opts.add_argument("--headless=new")
    opts.add_argument("--disable-gpu")
    opts.add_argument("--no-sandbox")
    opts.add_argument("--disable-dev-shm-usage")
    opts.add_argument("--window-size=1920,4000")
    opts.add_argument("--lang=en-US")
    opts.add_argument(
        "user-agent=Mozilla/5.0 (Windows NT 10.0; Win64; x64) "
        "AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0.0.0 Safari/537.36"
    )

    driver = webdriver.Chrome(options=opts)
    try:
        print(f"[nav] {URL}", flush=True)
        driver.get(URL)

        WebDriverWait(driver, 60).until(
            lambda d: d.execute_script("return document.body && document.body.innerText.length > 200;")
        )
        # Let React stream every chunk.
        time.sleep(4)
        driver.execute_script("window.scrollTo(0, document.body.scrollHeight);")
        time.sleep(2)
        driver.execute_script("window.scrollTo(0, 0);")
        time.sleep(1)

        opened = open_all_accordions(driver)
        print(f"[ui] opened {opened} accordions", flush=True)
        # Allow expanded content to paint.
        time.sleep(2)
        driver.execute_script("window.scrollTo(0, document.body.scrollHeight);")
        time.sleep(1)
        driver.execute_script("window.scrollTo(0, 0);")
        time.sleep(1)

        rendered = driver.page_source
        RENDERED_HTML_PATH.write_text(rendered, encoding="utf-8")
        print(f"[save] rendered HTML ({len(rendered):,} bytes)", flush=True)

        try:
            driver.save_screenshot(str(SCREENSHOT_PATH))
            print(f"[save] screenshot -> {SCREENSHOT_PATH}", flush=True)
        except Exception as exc:  # noqa: BLE001
            print(f"[save] screenshot failed: {exc}", flush=True)

        # Extract the visible article text, preserving paragraph breaks.
        text = driver.execute_script(
            r"""
            const root = document.querySelector('main') || document.querySelector('article') || document.body;
            if (!root) return '';
            const SKIP = new Set(['SCRIPT','STYLE','NOSCRIPT','TEMPLATE','NAV','FOOTER','HEADER','ASIDE']);
            const BLOCK = /^(P|DIV|LI|H[1-6]|TR|TD|TH|BR|HR|UL|OL|PRE)$/i;
            function walk(node) {
                if (!node) return '';
                if (node.nodeType === Node.TEXT_NODE) return node.nodeValue || '';
                if (node.nodeType !== Node.ELEMENT_NODE) return '';
                if (SKIP.has(node.tagName)) return '';
                if (node.getAttribute && node.getAttribute('aria-hidden') === 'true') return '';
                if (node.dataset && node.dataset.cds === 'SearchModal') return '';
                let out = '';
                for (const child of node.childNodes) {
                    out += walk(child);
                    if (child.nodeType === Node.ELEMENT_NODE && BLOCK.test(child.tagName)) {
                        out += '\n';
                    }
                }
                return out;
            }
            return walk(root)
                .replace(/[ \t]+\n/g, '\n')
                .replace(/\n{3,}/g, '\n\n')
                .trim();
            """
        )

        OUT_PATH.write_text(text, encoding="utf-8")
        chars = len(text)
        print(f"[save] extracted text -> {OUT_PATH} ({chars:,} chars)", flush=True)
        print("[preview] first 30 lines:", flush=True)
        for i, line in enumerate(text.splitlines()[:30], 1):
            print(f"  {i:>2}| {line}", flush=True)
        return 0
    finally:
        driver.quit()


if __name__ == "__main__":
    raise SystemExit(main())
