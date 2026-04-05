from __future__ import annotations

import hashlib
from typing import Dict, Iterable

import firebase_admin
from firebase_admin import credentials, firestore

from tcu_portal_scraper import Notice


def init_firestore() -> firestore.Client:
    if not firebase_admin._apps:
        cred = credentials.ApplicationDefault()
        firebase_admin.initialize_app(cred)
    return firestore.client()


def upsert_notices(
    db: firestore.Client, notices: Iterable[Notice], collection_name: str
) -> Dict[str, int]:
    created = 0
    updated = 0

    for notice in notices:
        doc_id = _build_notice_id(notice)
        ref = db.collection(collection_name).document(doc_id)
        payload = {
            "noticeId": doc_id,
            "title": notice.title,
            "body": notice.body,
            "publishedAtRaw": notice.published_at,
            "sourceUrl": notice.source_url,
            "section": notice.section,
            "type": infer_notice_type(notice),
            "createdAt": firestore.SERVER_TIMESTAMP,
            "updatedAt": firestore.SERVER_TIMESTAMP,
        }

        snapshot = ref.get()
        if snapshot.exists:
            ref.set(payload, merge=True)
            updated += 1
        else:
            ref.set(payload)
            created += 1

    return {"created": created, "updated": updated}


def infer_notice_type(notice: Notice) -> str:
    text = f"{notice.title} {notice.body} {notice.section}"
    text = text.lower()
    if "休講" in text:
        return "cancellation"
    if "補講" in text:
        return "makeupClass"
    if "教室変更" in text:
        return "roomChange"
    if "課題" in text or "レポート" in text:
        return "assignment"
    if "あなた宛" in text:
        return "general"
    return "general"


def _build_notice_id(notice: Notice) -> str:
    raw = f"{notice.title}|{notice.published_at}|{notice.source_url}"
    return hashlib.sha1(raw.encode("utf-8")).hexdigest()
