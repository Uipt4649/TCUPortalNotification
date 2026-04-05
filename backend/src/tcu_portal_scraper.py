from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
import re
from typing import List, Optional, Set, Tuple

from playwright.sync_api import Page, sync_playwright


@dataclass
class ScraperConfig:
    portal_login_url: str
    portal_notice_page_url: str
    portal_user_id: str
    portal_password: str
    user_id_selector: str
    password_selector: str
    login_button_selector: str
    login_entry_selector: str
    notice_item_selector: str
    notice_title_selector: str
    notice_date_selector: str
    notice_link_selector: str
    notice_body_selector: str
    session_state_path: str


@dataclass
class Notice:
    title: str
    published_at: str
    body: str
    source_url: str
    fetched_at: str
    section: str = ""


@dataclass
class ScrapeResult:
    notices: List[Notice]
    auth_required: bool
    reason: str = ""


NOISE_TITLES = {
    "topページ",
    "講義から検索",
    "教員から検索",
    "カリキュラムから検索",
    "全文検索",
    "top",
}

NOISE_TITLE_CONTAINS = [
    "受信一覧",
    "掲示一覧",
    "履修照会",
    "gpa/席次",
    "回答する",
    "検索",
    "top",
]

SECTION_HINTS = [
    "大学からのお知らせ",
    "あなた宛のお知らせ",
    "教員からのお知らせ",
    "誰でも投稿",
    "講義のお知らせ",
]


def scrape_notices_with_status(config: ScraperConfig, limit: int = 20) -> ScrapeResult:
    with sync_playwright() as playwright:
        browser = playwright.chromium.launch(headless=True)
        try:
            context = _create_context_with_optional_session(browser, config.session_state_path)
            page = context.new_page()
            _login_if_needed(page, config)
            if _is_auth_page(page):
                return ScrapeResult(
                    notices=[],
                    auth_required=True,
                    reason="microsoft_login_page_detected_after_session",
                )
            # Try current page first (after SSO login), then fallback URLs.
            notices = _extract_notices(page, config, limit)
            if notices:
                return ScrapeResult(notices=notices, auth_required=False)

            candidate_urls = [
                config.portal_notice_page_url,
                "https://websrv.tcu.ac.jp/tcu_web_v3/top.do",
            ]
            for url in candidate_urls:
                try:
                    page.goto(url, wait_until="domcontentloaded")
                    page.wait_for_timeout(1200)
                    if _is_auth_page(page):
                        return ScrapeResult(
                            notices=[],
                            auth_required=True,
                            reason="microsoft_login_page_detected_on_notice_page",
                        )
                    notices = _extract_notices(page, config, limit)
                    if notices:
                        return ScrapeResult(notices=notices, auth_required=False)
                except Exception:
                    continue
            return ScrapeResult(
                notices=[],
                auth_required=False,
                reason="no_notice_found_after_navigation",
            )
        finally:
            browser.close()


def scrape_notices(config: ScraperConfig, limit: int = 20) -> List[Notice]:
    return scrape_notices_with_status(config, limit).notices


def create_session_state(config: ScraperConfig) -> None:
    state_path = Path(config.session_state_path)
    state_path.parent.mkdir(parents=True, exist_ok=True)

    with sync_playwright() as playwright:
        browser = playwright.chromium.launch(headless=False)
        context = browser.new_context()
        page = context.new_page()
        page.goto(config.portal_login_url, wait_until="domcontentloaded")

        print("\n[ACTION REQUIRED]")
        print("ブラウザが開いたので、手動でログインを完了してください。")
        print("ログイン後にポータル内ページが表示されたら、ターミナルへ戻って Enter を押してください。")
        input("Enter を押すとセッションを保存します: ")

        context.storage_state(path=str(state_path))
        browser.close()
        print(f"[INFO] session state saved: {state_path}")


def _login(page: Page, config: ScraperConfig) -> None:
    page.goto(config.portal_login_url, wait_until="domcontentloaded")
    _try_open_credential_form(page, config.login_entry_selector)

    # Microsoft Entra ID (login.microsoftonline.com) flow
    if "login.microsoftonline.com" in page.url or page.locator("#i0116").count() > 0:
        _login_microsoft_flow(page, config.portal_user_id, config.portal_password)
        return

    user_selector = _first_existing_selector(
        page,
        [
            config.user_id_selector,
            "input[name='loginId']",
            "input[name='userId']",
            "input[name='userid']",
            "input[id*='user']",
            "input[type='text']",
        ],
    )
    password_selector = _first_existing_selector(
        page,
        [
            config.password_selector,
            "input[name='password']",
            "input[type='password']",
        ],
    )
    submit_selector = _first_existing_selector(
        page,
        [
            config.login_button_selector,
            "input[type='submit']",
            "button[type='submit']",
            "button:has-text('ログイン')",
            "input[value*='ログイン']",
        ],
    )

    if not user_selector or not password_selector or not submit_selector:
        # Debugging support: keep a snapshot for selector tuning.
        page.screenshot(path="debug_login_page.png", full_page=True)
        try:
            html = page.content()
            with open("debug_login_page.html", "w", encoding="utf-8") as f:
                f.write(html)
        except Exception:
            pass
        raise RuntimeError(
            "Login form selectors not found. Check backend/debug_login_page.png and backend/debug_login_page.html and update .env selectors."
        )

    page.fill(user_selector, config.portal_user_id)
    page.fill(password_selector, config.portal_password)
    page.click(submit_selector)
    page.wait_for_load_state("networkidle")


def _extract_notices(page: Page, config: ScraperConfig, limit: int) -> List[Notice]:
    notices: List[Notice] = []

    section_rows = _extract_rows_from_known_sections(page)
    if section_rows:
        notices = _build_notices_from_rows(section_rows, config, limit)
        notices = _dedupe_notices(notices)
        notices = _filter_noise_notices(notices)
        if notices:
            return notices[:limit]

    rows = page.query_selector_all(config.notice_item_selector)
    if not rows:
        # Common fallbacks for legacy campus portals
        fallback_selectors = [
            "div:has-text('大学からのお知らせ') a",
            "div:has-text('あなた宛のお知らせ') a",
            "div:has-text('教員からのお知らせ') a",
            "div:has-text('誰でも投稿') a",
            "div:has-text('講義のお知らせ') a",
            "div:has(> h3) a",
            ".public_inf a",
            "#main a",
            "table a",
            "li a",
        ]
        for selector in fallback_selectors:
            rows = page.query_selector_all(selector)
            if rows:
                break

    if not rows:
        # Keep artifacts for selector tuning
        page.screenshot(path="debug_notice_page.png", full_page=True)
        try:
            with open("debug_notice_page.html", "w", encoding="utf-8") as f:
                f.write(page.content())
        except Exception:
            pass
        return []

    notices = _build_notices_from_rows(rows, config, limit)
    notices = _dedupe_notices(notices)
    return _filter_noise_notices(notices)


def _safe_inner_text(element: Optional[object]) -> str:
    if element is None:
        return ""
    try:
        return element.inner_text()  # type: ignore[attr-defined]
    except Exception:
        return ""


def _first_existing_selector(page: Page, selectors: List[str]) -> str:
    for selector in selectors:
        if not selector:
            continue
        try:
            if page.locator(selector).count() > 0:
                return selector
        except Exception:
            continue
    return ""


def _try_open_credential_form(page: Page, login_entry_selector: str) -> None:
    # Some portal pages show only a "ログイン" transition button first.
    if page.locator("input[type='password']").count() > 0:
        return

    candidates = [
        login_entry_selector,
        "#loginButton",
        "input#loginButton",
        "input[value='ログイン']",
        "button:has-text('ログイン')",
    ]

    for selector in candidates:
        if not selector:
            continue
        try:
            if page.locator(selector).count() == 0:
                continue
            page.click(selector, timeout=4000)
            page.wait_for_load_state("domcontentloaded")
            page.wait_for_timeout(800)
            if page.locator("input[type='password']").count() > 0:
                return
        except Exception:
            continue

    # Fallback: this portal often exposes credential inputs on login.do directly.
    try:
        page.goto("https://websrv.tcu.ac.jp/tcu_web_v3/login.do", wait_until="domcontentloaded")
        page.wait_for_timeout(800)
    except Exception:
        pass


def _login_microsoft_flow(page: Page, user_id: str, password: str) -> None:
    # Step 1: user id (email/student account)
    if page.locator("#i0116").count() > 0:
        page.fill("#i0116", user_id)
        page.click("#idSIButton9")
        page.wait_for_load_state("domcontentloaded")
        page.wait_for_timeout(1200)

    # Step 2: password
    if page.locator("#i0118").count() > 0:
        page.fill("#i0118", password)
        page.click("#idSIButton9")
        page.wait_for_load_state("domcontentloaded")
        page.wait_for_timeout(1200)

    # Step 3: "Stay signed in?" prompt (optional)
    if page.locator("#idSIButton9").count() > 0 and (
        "kmsi" in page.url.lower() or "stay signed in" in page.content().lower()
    ):
        page.click("#idSIButton9")
        page.wait_for_load_state("networkidle")


def _filter_noise_notices(notices: List[Notice]) -> List[Notice]:
    filtered: List[Notice] = []
    for notice in notices:
        normalized_title = notice.title.strip().lower()
        if normalized_title in NOISE_TITLES:
            continue
        if any(word in normalized_title for word in NOISE_TITLE_CONTAINS):
            continue
        if notice.source_url and "changeTab" in notice.source_url:
            continue
        if len(normalized_title) <= 1:
            continue
        filtered.append(notice)
    return filtered


def _extract_rows_from_known_sections(page: Page) -> List[object]:
    rows: List[object] = []
    for hint in SECTION_HINTS:
        selectors = [
            f"div:has-text('{hint}') a",
            f"section:has-text('{hint}') a",
            f"td:has-text('{hint}') a",
        ]
        for selector in selectors:
            try:
                found = page.query_selector_all(selector)
                if found:
                    rows.extend(found)
            except Exception:
                continue
    return rows


def _build_notices_from_rows(rows: List[object], config: ScraperConfig, limit: int) -> List[Notice]:
    notices: List[Notice] = []
    fetched_at = datetime.now(timezone.utc).isoformat()

    for row in rows[: max(limit * 5, limit)]:
        # If the row itself is an anchor, use own text as title.
        if getattr(row, "evaluate", None):
            tag_name = ""
            try:
                tag_name = row.evaluate("el => el.tagName.toLowerCase()")
            except Exception:
                tag_name = ""
        else:
            tag_name = ""

        title = ""
        if tag_name == "a":
            title = _normalize_text(_safe_inner_text(row))
        if not title:
            title = _normalize_text(_safe_inner_text(row.query_selector(config.notice_title_selector)))
        if not title:
            title = _normalize_text(_safe_inner_text(row))
        if not title:
            continue

        row_text = _normalize_text(_safe_inner_text(row))
        published_at = _normalize_text(_safe_inner_text(row.query_selector(config.notice_date_selector)))
        if not published_at:
            published_at = _extract_date_like_text(row_text)
        body = _normalize_text(_safe_inner_text(row.query_selector(config.notice_body_selector)))
        if not body:
            body = _build_body_from_row_text(row_text, title, published_at)

        link_el = row.query_selector(config.notice_link_selector)
        if tag_name == "a":
            link_el = row
        source_url = ""
        if link_el:
            source_url = link_el.get_attribute("href") or ""
            if source_url and source_url.startswith("/"):
                source_url = "https://websrv.tcu.ac.jp" + source_url

        section = _guess_section(row_text)
        notices.append(
            Notice(
                title=title.strip(),
                published_at=(published_at or "").strip(),
                body=(body or "").strip(),
                source_url=source_url.strip(),
                fetched_at=fetched_at,
                section=section,
            )
        )

    return notices[:limit]


def _dedupe_notices(notices: List[Notice]) -> List[Notice]:
    seen: Set[Tuple[str, str]] = set()
    unique: List[Notice] = []
    for notice in notices:
        key = (notice.title.strip().lower(), notice.source_url.strip())
        if key in seen:
            continue
        seen.add(key)
        unique.append(notice)
    return unique


def _build_body_from_row_text(row_text: str, title: str, published_at: str) -> str:
    body = row_text
    if title:
        body = body.replace(title, "").strip()
    if published_at:
        body = body.replace(published_at, "").strip()
    return body[:200]


def _extract_date_like_text(text: str) -> str:
    # e.g. 4/5 (土) or 2026/04/05
    patterns = [
        r"\d{4}/\d{1,2}/\d{1,2}",
        r"\d{1,2}/\d{1,2}\s*\([^)]+\)",
        r"\d{1,2}/\d{1,2}",
    ]
    for pattern in patterns:
        match = re.search(pattern, text)
        if match:
            return match.group(0)
    return ""


def _normalize_text(text: str) -> str:
    return re.sub(r"\s+", " ", (text or "")).strip()


def _guess_section(text: str) -> str:
    for hint in SECTION_HINTS:
        if hint in text:
            return hint
    return ""


def _create_context_with_optional_session(browser: object, session_state_path: str):
    state_path = Path(session_state_path)
    if state_path.exists():
        return browser.new_context(storage_state=str(state_path))
    return browser.new_context()


def _login_if_needed(page: Page, config: ScraperConfig) -> None:
    page.goto(config.portal_login_url, wait_until="domcontentloaded")
    if "login.microsoftonline.com" in page.url or page.locator("#i0116").count() > 0:
        _login(page, config)
        return
    if page.locator("input[type='password']").count() > 0:
        _login(page, config)


def _is_auth_page(page: Page) -> bool:
    url = page.url.lower()
    if "login.microsoftonline.com" in url:
        return True
    try:
        if page.locator("#i0281").count() > 0:
            return True
    except Exception:
        pass
    return False
