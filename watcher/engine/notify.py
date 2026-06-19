"""Bridge gate_allowed → FCM + watcher pause (Phase 7)."""

from __future__ import annotations

import structlog

from engine.config import WatcherSettings

log = structlog.get_logger(__name__)


def parse_allowed_device_ids(raw: str) -> frozenset[int] | None:
    text = (raw or "").strip()
    if not text:
        return None
    out: set[int] = set()
    for part in text.split(","):
        part = part.strip()
        if part.isdigit():
            out.add(int(part))
    return frozenset(out) if out else None


async def dispatch_open_notifications(watcher_id: int, settings: WatcherSettings) -> None:
    """Persist notification_logs and optionally send FCM."""
    from app.services.fcm_service import notify_watcher_opened
    from engine.db_session import get_sessionmaker

    sm = get_sessionmaker()
    async with sm() as session:
        async with session.begin():
            summary = await notify_watcher_opened(
                session,
                watcher_id,
                fcm_enabled=settings.fcm_enabled,
                dry_run=settings.dry_run,
                allowed_device_ids=parse_allowed_device_ids(settings.fcm_allowed_device_ids),
                open_cooldown_minutes=settings.open_notify_cooldown_minutes,
            )
    if summary is None:
        log.warning("notify_skipped_missing_watcher", watcher_id=watcher_id)
        return
    log.info(
        "notify_dispatch_done",
        watcher_id=watcher_id,
        opened_event_id=summary.opened_event_id,
        sent=summary.sent,
        attempted=summary.attempted,
    )
