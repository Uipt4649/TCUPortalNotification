from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
import re
from typing import Any, Dict, List, Optional, Set, Tuple

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
    sender: str = ""
    read_at: str = ""
    received_at_epoch: int = 0


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

NOISE_HREF_CONTAINS = [
    "logout",
]

SECTION_HINTS = [
    "大学からのお知らせ",
    "あなた宛のお知らせ",
    "教員からのお知らせ",
    "誰でも投稿",
    "講義のお知らせ",
]

TARGET_SECTIONS = [
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
            list_notices, parse_reason = _open_and_parse_message_list_page(page, config, limit)
            if _is_auth_page(page):
                return ScrapeResult(
                    notices=[],
                    auth_required=True,
                    reason="microsoft_login_page_detected_on_notice_page",
                )
            if list_notices:
                return ScrapeResult(
                    notices=list_notices[:limit],
                    auth_required=False,
                    reason=parse_reason,
                )
            return ScrapeResult(
                notices=[],
                auth_required=False,
                reason="showall_table_not_found_or_empty",
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
    fetched_at = datetime.now(timezone.utc).isoformat()

    for ctx in _iter_page_contexts(page):
        extracted = _extract_candidates_from_context(ctx)
        for item in extracted:
            title = _normalize_text(str(item.get("title", "")))
            if not title:
                continue
            href = _normalize_href(str(item.get("href", "")))
            row_text = _normalize_text(str(item.get("rowText", "")))
            published_at = _extract_date_like_text(row_text)
            section = _normalize_section(str(item.get("section", "")), row_text, title)
            body = _build_body_from_row_text(row_text, title, published_at)

            notices.append(
                Notice(
                    title=title,
                    published_at=published_at,
                    body=body,
                    source_url=href,
                    fetched_at=fetched_at,
                    section=section,
                    sender="",
                    read_at="",
                    received_at_epoch=_parse_datetime_epoch(published_at),
                )
            )

    notices = _dedupe_notices(notices)
    notices = _filter_noise_notices(notices)
    if notices:
        return notices[:limit]

    # Keep artifacts for selector tuning
    page.screenshot(path="debug_notice_page.png", full_page=True)
    try:
        with open("debug_notice_page.html", "w", encoding="utf-8") as f:
            f.write(page.content())
    except Exception:
        pass
    return []


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
        source_lower = (notice.source_url or "").lower()
        if any(token in source_lower for token in NOISE_HREF_CONTAINS):
            continue
        if len(normalized_title) <= 1:
            continue
        filtered.append(notice)
    return filtered


def _iter_page_contexts(page: Page) -> List[Any]:
    contexts: List[Any] = []
    try:
        contexts.extend(page.frames)
    except Exception:
        pass
    if not contexts:
        contexts.append(page)
    return contexts


def _extract_candidates_from_context(ctx: Any) -> List[Dict[str, str]]:
    script = """
() => {
  const hints = ["大学からのお知らせ","あなた宛のお知らせ","教員からのお知らせ","誰でも投稿","講義のお知らせ","だれでも投稿","教務メッセージ","講義情報"];
  const normalize = (s) => (s || "").replace(/\\s+/g, " ").trim();
  const rows = [];
  const anchors = Array.from(document.querySelectorAll("a"));

  const detectUniqueHint = (text) => {
    const normalizedText = normalize(text);
    const found = hints.filter((h) => normalizedText.includes(h));
    if (found.length === 1) return found[0];
    return "";
  };

  const findSection = (anchor) => {
    let node = anchor;
    for (let depth = 0; depth < 7 && node; depth += 1) {
      const directHeader = Array.from(node.querySelectorAll(":scope > h1, :scope > h2, :scope > h3, :scope > h4, :scope > .title, :scope > .heading"))
        .map((el) => normalize(el.textContent || ""))
        .join(" ");
      const directHit = detectUniqueHint(directHeader);
      if (directHit) return directHit;

      const ownTextHit = detectUniqueHint(node.textContent || "");
      if (ownTextHit) return ownTextHit;
      node = node.parentElement;
    }
    return "";
  };

  for (const a of anchors) {
    const title = normalize(a.textContent || "");
    const href = normalize(a.getAttribute("href") || "");
    if (!title) continue;
    const container = a.closest("li, tr, div, td") || a;
    const rowText = normalize((a.parentElement ? a.parentElement.textContent : "") || title);
    rows.push({
      title,
      href,
      rowText,
      section: findSection(a),
    });
  }
  return rows;
}
"""
    try:
        raw = ctx.evaluate(script)
        if isinstance(raw, list):
            return [r for r in raw if isinstance(r, dict)]
    except Exception:
        return []
    return []


def _extract_message_list_notices(page: Page, limit: int) -> List[Notice]:
    script = """
() => {
  const norm = (s) => (s || "").replace(/\\s+/g, " ").trim();
  const dateRe = /\\d{4}\\/\\d{1,2}\\/\\d{1,2}(\\s+\\d{1,2}:\\d{2}(:\\d{2})?)?/;
  const results = [];

  const tables = Array.from(document.querySelectorAll("table"));
  for (const table of tables) {
    const rows = Array.from(table.querySelectorAll("tr"));
    if (!rows.length) continue;

    // Header can be built by either <th> or <td class="label"> in this portal.
    let headerCells = Array.from(rows[0].querySelectorAll("th, td")).map((c) => norm(c.textContent || ""));
    let headerRowIndex = 0;
    if (!headerCells.some((h) => h.includes("受信日時")) && rows.length > 1) {
      const second = Array.from(rows[1].querySelectorAll("th, td")).map((c) => norm(c.textContent || ""));
      if (second.some((h) => h.includes("受信日時")) || second.some((h) => h.includes("種別"))) {
        headerCells = second;
        headerRowIndex = 1;
      }
    }

    const findIdx = (headers, preds) => headers.findIndex((h) => preds.some((p) => h.includes(p)));
    const idx = {
      title: findIdx(headerCells, ["タイトル", "件名"]),
      kind: findIdx(headerCells, ["種別"]),
      sender: findIdx(headerCells, ["送信者", "送信元", "差出人"]),
      receivedAt: findIdx(headerCells, ["受信日時", "受信日"]),
      readAt: findIdx(headerCells, ["既読日時", "既読日"]),
    };
    if (idx.title < 0 || idx.kind < 0 || idx.receivedAt < 0) continue;

    for (const tr of rows.slice(headerRowIndex + 1)) {
      const tds = Array.from(tr.querySelectorAll("td"));
      if (!tds.length) continue;
      const at = (i) => (i >= 0 && i < tds.length ? tds[i] : null);
      const titleCell = at(idx.title);
      const kindCell = at(idx.kind);
      const senderCell = at(idx.sender);
      const receivedCell = at(idx.receivedAt);
      const readCell = at(idx.readAt);
      if (!titleCell || !kindCell || !receivedCell) continue;

      const a = titleCell.querySelector("a");
      const title = norm((a ? a.textContent : titleCell.textContent) || "");
      if (!title) continue;
      const href = norm((a && a.getAttribute("href")) || "") || window.location.href;
      const kind = norm(kindCell.textContent || "");
      const sender = norm((senderCell && senderCell.textContent) || "");
      const receivedAt = norm(receivedCell.textContent || "");
      const readAt = norm((readCell && readCell.textContent) || "");

      if (!dateRe.test(receivedAt)) continue;
      results.push({
        title,
        href,
        kind,
        sender,
        receivedAt,
        readAt,
      });
    }
  }
  return results;
}
"""
    raw: List[Dict[str, str]] = []
    for ctx in _iter_page_contexts(page):
        try:
            out = ctx.evaluate(script)
            if isinstance(out, list):
                raw.extend([r for r in out if isinstance(r, dict)])
        except Exception:
            continue

    fetched_at = datetime.now(timezone.utc).isoformat()
    notices: List[Notice] = []
    for item in raw:
        title = _normalize_text(str(item.get("title", "")))
        if not title:
            continue
        received_at = _normalize_text(str(item.get("receivedAt", "")))
        kind = _normalize_kind(_normalize_text(str(item.get("kind", "")))
        )
        if not kind:
            continue
        sender = _normalize_text(str(item.get("sender", "")))
        read_at = _normalize_text(str(item.get("readAt", "")))
        href = _normalize_href(str(item.get("href", "")))
        epoch = _parse_datetime_epoch(received_at)
        notices.append(
            Notice(
                title=title,
                published_at=received_at,
                body=f"送信者: {sender}" if sender else "",
                source_url=href,
                fetched_at=fetched_at,
                section=kind,
                sender=sender,
                read_at=read_at,
                received_at_epoch=epoch,
            )
        )

    notices = _dedupe_notices(notices)
    notices = _filter_noise_notices(notices)
    notices.sort(key=lambda n: n.received_at_epoch, reverse=True)
    if not notices:
        try:
            page.screenshot(path="debug_showall_page.png", full_page=True)
            with open("debug_showall_page.html", "w", encoding="utf-8") as f:
                f.write(page.content())
        except Exception:
            pass
    return notices[:limit]


def _is_message_list_page(page: Page) -> bool:
    script = """
() => {
  const norm = (s) => (s || "").replace(/\\s+/g, " ").trim();
  const headers = Array.from(document.querySelectorAll("th, tr.label td, tr.label th")).map((el) => norm(el.textContent || ""));
  const hasKind = headers.some((h) => h.includes("種別"));
  const hasSender = headers.some((h) => h.includes("送信者") || h.includes("送信元") || h.includes("差出人"));
  const hasReceived = headers.some((h) => h.includes("受信日時") || h.includes("受信日"));
  return hasKind && hasSender && hasReceived;
}
"""
    for ctx in _iter_page_contexts(page):
        try:
            if bool(ctx.evaluate(script)):
                return True
        except Exception:
            continue
    return False


def _scrape_sections_by_navigation(page: Page, config: ScraperConfig, limit: int) -> List[Notice]:
    all_notices: List[Notice] = []
    for section in TARGET_SECTIONS:
        try:
            page.goto(config.portal_login_url, wait_until="domcontentloaded")
            page.wait_for_timeout(900)
        except Exception:
            pass

        clicked = _click_section_link(page, section)
        if not clicked:
            continue

        page.wait_for_timeout(900)
        section_rows = _extract_notice_rows_with_dates(page)
        fetched_at = datetime.now(timezone.utc).isoformat()

        for row in section_rows:
            title = _normalize_text(str(row.get("title", "")))
            if not title:
                continue
            published_at = _normalize_text(str(row.get("date", "")))
            body = _normalize_text(str(row.get("body", "")))
            href = _normalize_href(str(row.get("href", "")))
            all_notices.append(
                Notice(
                    title=title,
                    published_at=published_at,
                    body=body,
                    source_url=href,
                    fetched_at=fetched_at,
                    section=section,
                    sender="",
                    read_at="",
                    received_at_epoch=_parse_datetime_epoch(published_at),
                )
            )

    all_notices = _dedupe_notices(all_notices)
    all_notices = _filter_noise_notices(all_notices)
    return all_notices[:limit]


def _click_section_link(page: Page, section: str) -> bool:
    selectors = [
        f"a:has-text('{section}')",
        f"*:has-text('{section}') a",
    ]
    for selector in selectors:
        try:
            loc = page.locator(selector).first
            if loc.count() == 0:
                continue
            loc.click(timeout=2500)
            return True
        except Exception:
            continue
    return False


def _extract_notice_rows_with_dates(page: Page) -> List[Dict[str, str]]:
    script = """
() => {
  const norm = (s) => (s || "").replace(/\\s+/g, " ").trim();
  const dateRe = /(\\d{4}\\/\\d{1,2}\\/\\d{1,2})|(\\d{1,2}\\/\\d{1,2}\\s*\\([^)]+\\))/;
  const rows = [];
  const candidates = Array.from(document.querySelectorAll("li, tr, div"));

  for (const el of candidates) {
    const text = norm(el.textContent || "");
    if (!dateRe.test(text)) continue;
    const a = el.querySelector("a");
    if (!a) continue;
    const title = norm(a.textContent || "");
    if (!title) continue;
    const href = norm(a.getAttribute("href") || "");
    const dateMatch = text.match(dateRe);
    rows.push({
      title,
      href,
      date: dateMatch ? norm(dateMatch[0]) : "",
      body: text.replace(title, "").replace(dateMatch ? dateMatch[0] : "", "").trim(),
    });
  }
  return rows;
}
"""
    out: List[Dict[str, str]] = []
    for ctx in _iter_page_contexts(page):
        try:
            raw = ctx.evaluate(script)
            if isinstance(raw, list):
                out.extend([r for r in raw if isinstance(r, dict)])
        except Exception:
            continue
    return out


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


def _normalize_href(href: str) -> str:
    if not href:
        return ""
    href = href.strip()
    if href.startswith("#"):
        return ""
    if href.startswith("/"):
        return "https://websrv.tcu.ac.jp" + href
    if href.startswith("http://") or href.startswith("https://"):
        return href
    if href.lower().startswith("javascript:"):
        return ""
    return href


def _normalize_section(raw_section: str, row_text: str, title: str) -> str:
    # Prefer raw_section from nearest section block.
    source = f"{raw_section}"
    fallback = f"{row_text} {title}"
    if "大学からのお知らせ" in source:
        return "大学からのお知らせ"
    if "あなた宛のお知らせ" in source:
        return "あなた宛のお知らせ"
    if "教員からのお知らせ" in source or "教務メッセージ" in source:
        return "教員からのお知らせ"
    if "誰でも投稿" in source or "だれでも投稿" in source:
        return "誰でも投稿"
    if "講義のお知らせ" in source or "講義情報" in source:
        return "講義のお知らせ"

    # Fallback heuristics only when we have a single section-like signal.
    fallback_hits = 0
    hit = "その他"
    if "大学からのお知らせ" in fallback:
        fallback_hits += 1
        hit = "大学からのお知らせ"
    if "あなた宛のお知らせ" in fallback:
        fallback_hits += 1
        hit = "あなた宛のお知らせ"
    if "教員からのお知らせ" in fallback or "教務メッセージ" in fallback:
        fallback_hits += 1
        hit = "教員からのお知らせ"
    if "誰でも投稿" in fallback or "だれでも投稿" in fallback:
        fallback_hits += 1
        hit = "誰でも投稿"
    if "講義のお知らせ" in fallback or "講義情報" in fallback:
        fallback_hits += 1
        hit = "講義のお知らせ"
    if fallback_hits == 1:
        return hit
    return "その他"


def _normalize_kind(raw: str) -> str:
    value = _normalize_text(raw)
    if "大学からのお知らせ" in value:
        return "大学からのお知らせ"
    if "あなた宛のお知らせ" in value:
        return "あなた宛のお知らせ"
    if "教員からのお知らせ" in value:
        return "教員からのお知らせ"
    if "誰でも投稿" in value or "だれでも投稿" in value:
        return "誰でも投稿"
    if "講義のお知らせ" in value:
        return "講義のお知らせ"
    if "伝言" in value:
        return "伝言"
    return ""


def _parse_datetime_epoch(text: str) -> int:
    value = _normalize_text(text)
    patterns = [
        "%Y/%m/%d %H:%M:%S",
        "%Y/%m/%d %H:%M",
        "%Y-%m-%d %H:%M:%S",
        "%Y-%m-%d %H:%M",
        "%Y/%m/%d",
    ]
    for fmt in patterns:
        try:
            dt = datetime.strptime(value, fmt).replace(tzinfo=timezone.utc)
            return int(dt.timestamp())
        except Exception:
            continue
    return 0


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


def _open_and_parse_message_list_page(
    page: Page,
    config: ScraperConfig,
    limit: int,
) -> Tuple[List[Notice], str]:
    candidates = [
        (config.portal_notice_page_url, "config_url"),
        (
            "https://websrv.tcu.ac.jp/tcu_web_v3/top.do?buttonName=showContent&menulv1=0000000001&menuIndex=0&contenam=wbasmgjr&kjnmnNo=90",
            "wbasmgjr_url",
        ),
    ]

    for url, label in candidates:
        try:
            page.goto(url, wait_until="domcontentloaded")
            page.wait_for_timeout(2200)
            if _is_auth_page(page):
                return ([], f"{label}_auth_required")
            notices = _extract_message_list_notices(page, limit)
            if notices:
                return (notices, f"{label}_table_parsed")
        except Exception:
            continue

    # Last fallback: open top page and follow the actual menu anchor.
    try:
        page.goto(config.portal_login_url, wait_until="domcontentloaded")
        page.wait_for_timeout(1500)
        if _is_auth_page(page):
            return ([], "top_page_auth_required")

        menu_url = _find_message_list_menu_url(page)
        if menu_url:
            page.goto(menu_url, wait_until="domcontentloaded")
            page.wait_for_timeout(2200)
            if _is_auth_page(page):
                return ([], "menu_url_auth_required")
            notices = _extract_message_list_notices(page, limit)
            if notices:
                return (notices, "menu_url_table_parsed")
    except Exception:
        pass

    return ([], "message_list_not_found")


def _find_message_list_menu_url(page: Page) -> str:
    script = """
() => {
  const abs = (href) => {
    try { return new URL(href, window.location.href).toString(); } catch (_) { return ""; }
  };
  const norm = (s) => (s || "").replace(/\\s+/g, " ").trim();
  const anchors = Array.from(document.querySelectorAll("a"));
  for (const a of anchors) {
    const title = norm(a.getAttribute("title") || "");
    const text = norm(a.textContent || "");
    const href = norm(a.getAttribute("href") || "");
    if (!href) continue;
    if (title.includes("メッセージ受信一覧") || text.includes("メッセージ受信一覧")) {
      return abs(href);
    }
  }
  return "";
}
"""
    try:
        out = page.evaluate(script)
        if isinstance(out, str):
            return _normalize_text(out)
    except Exception:
        pass
    return ""


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
