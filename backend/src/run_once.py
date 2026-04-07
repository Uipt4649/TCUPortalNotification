from __future__ import annotations

import argparse
import os
from pathlib import Path

from dotenv import load_dotenv

from firestore_writer import (
    init_firestore,
    list_device_tokens,
    send_push_to_tokens,
    update_portal_status,
    upsert_notices,
)
from tcu_portal_scraper import (
    ScraperConfig,
    create_session_state,
    scrape_notices_with_status,
)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--init-session",
        action="store_true",
        help="Open browser and save authenticated session state for SSO login.",
    )
    return parser.parse_args()


def main() -> int:
    args = parse_args()

    env_path = Path(__file__).resolve().parents[1] / ".env"
    if env_path.exists():
        load_dotenv(env_path)

    required = [
        "PORTAL_LOGIN_URL",
        "PORTAL_NOTICE_PAGE_URL",
        "PORTAL_USER_ID",
        "PORTAL_PASSWORD",
        "PORTAL_USER_ID_SELECTOR",
        "PORTAL_PASSWORD_SELECTOR",
        "PORTAL_LOGIN_BUTTON_SELECTOR",
        "PORTAL_NOTICE_ITEM_SELECTOR",
        "PORTAL_NOTICE_TITLE_SELECTOR",
        "PORTAL_NOTICE_DATE_SELECTOR",
        "PORTAL_NOTICE_LINK_SELECTOR",
        "PORTAL_NOTICE_BODY_SELECTOR",
        "FIRESTORE_COLLECTION",
    ]
    missing = [k for k in required if not os.getenv(k)]
    if missing:
        print(f"[ERROR] Missing env vars: {', '.join(missing)}")
        print("Create backend/.env from backend/.env.example and fill required values.")
        return 1

    config = ScraperConfig(
        portal_login_url=os.environ["PORTAL_LOGIN_URL"],
        portal_notice_page_url=os.environ["PORTAL_NOTICE_PAGE_URL"],
        portal_user_id=os.environ["PORTAL_USER_ID"],
        portal_password=os.environ["PORTAL_PASSWORD"],
        user_id_selector=os.environ["PORTAL_USER_ID_SELECTOR"],
        password_selector=os.environ["PORTAL_PASSWORD_SELECTOR"],
        login_button_selector=os.environ["PORTAL_LOGIN_BUTTON_SELECTOR"],
        login_entry_selector=os.getenv("PORTAL_LOGIN_ENTRY_SELECTOR", ""),
        notice_item_selector=os.environ["PORTAL_NOTICE_ITEM_SELECTOR"],
        notice_title_selector=os.environ["PORTAL_NOTICE_TITLE_SELECTOR"],
        notice_date_selector=os.environ["PORTAL_NOTICE_DATE_SELECTOR"],
        notice_link_selector=os.environ["PORTAL_NOTICE_LINK_SELECTOR"],
        notice_body_selector=os.environ["PORTAL_NOTICE_BODY_SELECTOR"],
        session_state_path=os.getenv("PORTAL_SESSION_STATE_PATH", "./secrets/portal_session.json"),
    )

    if args.init_session:
        create_session_state(config)
        return 0

    db = init_firestore()
    scrape_limit = int(os.getenv("SCRAPE_LIMIT", "200"))
    if scrape_limit < 1:
        scrape_limit = 200

    scrape_result = scrape_notices_with_status(config, limit=scrape_limit)
    notices = scrape_result.notices
    print(f"[INFO] scraped notices: {len(notices)}")

    status_transition = update_portal_status(
        db,
        auth_required=scrape_result.auth_required,
        reason=scrape_result.reason,
    )

    if scrape_result.auth_required:
        if status_transition.get("became_auth_required", False):
            tokens = list_device_tokens(db)
            push = send_push_to_tokens(
                db,
                tokens=tokens,
                title="再ログインが必要です",
                body="ポータルセッションが切れました。再認証を行ってください。",
                data={"kind": "auth_required"},
            )
            print(f"[INFO] auth alert push sent={push['sent']} failed={push['failed']} targets={len(tokens)}")
        print("[WARN] Portal auth required. Session expired or login page detected.")
        if scrape_result.reason:
            print(f"[DEBUG] reason={scrape_result.reason}")
        print("[NEXT] Run: python src/run_once.py --init-session")
        print("[NEXT] Then run: python src/run_once.py")
        return 0

    if not notices:
        print("[WARN] No notices found. Check selectors against portal HTML.")
        if scrape_result.reason:
            print(f"[DEBUG] reason={scrape_result.reason}")
        return 0

    result = upsert_notices(
        db=db,
        notices=notices,
        collection_name=os.environ["FIRESTORE_COLLECTION"],
    )
    print(f"[INFO] created={result['created']} updated={result['updated']}")

    created_notices = result.get("created_notices", [])
    if created_notices:
        tokens = list_device_tokens(db)
        latest = created_notices[0]
        section = latest.section or "ポータル通知"
        push = send_push_to_tokens(
            db,
            tokens=tokens,
            title=f"新着 [{section}] {latest.title}",
            body=((f"{latest.sender} / " if latest.sender else "") + (latest.published_at or "新しいお知らせがあります。"))[:120],
            data={"kind": "new_notice"},
        )
        print(f"[INFO] push sent={push['sent']} failed={push['failed']} targets={len(tokens)}")
    else:
        print("[INFO] No new notice documents. Push skipped.")

    for idx, n in enumerate(notices[:3], start=1):
        print(f"[sample {idx}] {n.published_at} | {n.title}")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
