from __future__ import annotations

import hashlib
from typing import Any, Dict, Iterable, List

import firebase_admin
from firebase_admin import credentials, firestore, messaging

from tcu_portal_scraper import Notice


def init_firestore() -> firestore.Client:
    if not firebase_admin._apps:
        cred = credentials.ApplicationDefault()
        firebase_admin.initialize_app(cred)
    return firestore.client()


def upsert_notices(
    db: firestore.Client, notices: Iterable[Notice], collection_name: str
) -> Dict[str, Any]:
    created = 0
    updated = 0
    created_notices: List[Notice] = []

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
            created_notices.append(notice)

    return {"created": created, "updated": updated, "created_notices": created_notices}


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


def update_portal_status(
    db: firestore.Client,
    *,
    auth_required: bool,
    reason: str,
) -> None:
    db.collection("system_status").document("portal_auth").set(
        {
            "authRequired": auth_required,
            "reason": reason,
            "checkedAt": firestore.SERVER_TIMESTAMP,
        },
        merge=True,
    )


def list_device_tokens(db: firestore.Client, limit: int = 500) -> List[str]:
    docs = db.collection("device_tokens").limit(limit).stream()
    tokens: List[str] = []
    for doc in docs:
        data = doc.to_dict() or {}
        token = str(data.get("token") or doc.id).strip()
        if token:
            tokens.append(token)
    return tokens


def send_push_to_tokens(
    db: firestore.Client,
    *,
    tokens: List[str],
    title: str,
    body: str,
    data: Dict[str, str] | None = None,
) -> Dict[str, int]:
    if not tokens:
        return {"sent": 0, "failed": 0}

    multicast = messaging.MulticastMessage(
        notification=messaging.Notification(title=title, body=body),
        data=data or {},
        tokens=tokens,
    )
    response = messaging.send_each_for_multicast(multicast)

    # Remove invalid tokens to keep delivery quality.
    for idx, r in enumerate(response.responses):
        if r.success:
            continue
        err = str(r.exception or "")
        if "registration-token-not-registered" in err or "invalid-registration-token" in err:
            token = tokens[idx]
            db.collection("device_tokens").document(token).delete()

    return {"sent": response.success_count, "failed": response.failure_count}
