from __future__ import annotations

import argparse
import os
from pathlib import Path

from dotenv import load_dotenv

from firestore_writer import init_firestore, upsert_notices
from tcu_portal_scraper import ScraperConfig, create_session_state, scrape_notices


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

    notices = scrape_notices(config)
    print(f"[INFO] scraped notices: {len(notices)}")
    if not notices:
        print("[WARN] No notices found. Check selectors against portal HTML.")
        return 0

    db = init_firestore()
    result = upsert_notices(
        db=db,
        notices=notices,
        collection_name=os.environ["FIRESTORE_COLLECTION"],
    )
    print(f"[INFO] created={result['created']} updated={result['updated']}")

    for idx, n in enumerate(notices[:3], start=1):
        print(f"[sample {idx}] {n.published_at} | {n.title}")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
