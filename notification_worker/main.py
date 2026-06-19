"""Process notification queue events with FCM multicast."""

from __future__ import annotations

import asyncio
import sys

import structlog
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker

from app.config import get_settings
from app.core.logging_conf import configure_logging
from app.core.redis_client import close_redis, init_redis
from app.db.session import init_engine, make_engine
from app.models.device import Device
from app.models.notification_log import NotificationLog
from app.models.ops import NotificationEvent
from app.models.subscription import Subscription
from app.models.watcher import Watcher
from app.queue.notification_queue import consume_watcher_opened, requeue_with_backoff
from app.services.fcm_service import (
    NotifyPayload,
    _subscriber_rows,
    _write_in_app_watcher_logs,
    build_open_payload_secure,
    send_multicast_batch,
)

log = structlog.get_logger(__name__)


async def process_event(session: AsyncSession, event_id: int, watcher_id: int, opened_event_id: str) -> None:
    row = await session.get(NotificationEvent, event_id)
    if row is None:
        return
    row.status = "processing"
    await session.flush()

    watcher = await session.get(Watcher, watcher_id)
    if watcher is None:
        row.status = "failed"
        return

    payload = build_open_payload_secure(watcher, opened_event_id)
    rows = await _subscriber_rows(session, watcher_id)
    settings = get_settings()
    batch_size = settings.notification_batch_size

    tokens: list[tuple[int, int, str]] = []
    in_app_device_ids: list[int] = []
    for sub, device in rows:
        token = (device.fcm_token or "").strip()
        if token:
            tokens.append((sub.id, device.id, token))
        else:
            in_app_device_ids.append(device.id)

    await _write_in_app_watcher_logs(
        session,
        watcher_id=watcher_id,
        opened_event_id=opened_event_id,
        device_ids=in_app_device_ids,
        sent_at=row.created_at,
        status="in_app_only",
    )

    sent = 0
    for i in range(0, len(tokens), batch_size):
        chunk = tokens[i : i + batch_size]
        batch_tokens = [t[2] for t in chunk]
        results = await send_multicast_batch(batch_tokens, payload)
        for (sub_id, device_id, token), (ok, stale) in zip(chunk, results, strict=False):
            dup = (
                await session.execute(
                    select(NotificationLog.id).where(
                        NotificationLog.watcher_id == watcher_id,
                        NotificationLog.device_id == device_id,
                        NotificationLog.opened_event_id == opened_event_id,
                    )
                )
            ).scalar_one_or_none()
            if dup is not None:
                continue
            if stale:
                device_row = await session.get(Device, device_id)
                if device_row is not None:
                    device_row.is_active = False
                    device_row.fcm_token = None
            log_row = NotificationLog(
                watcher_id=watcher_id,
                device_id=device_id,
                opened_event_id=opened_event_id,
                sent_at=row.created_at,
                status="success" if ok else ("stale_token" if stale else "failed"),
            )
            session.add(log_row)
            if ok:
                sent += 1
            else:
                device = await session.get(Device, device_id)
                if device and "not-registered" in str(ok):
                    device.is_active = False

    row.status = "done"
    row.processed_at = row.created_at
    await session.commit()
    log.info("notification_batch_complete", watcher_id=watcher_id, sent=sent, total=len(tokens))


async def run_worker() -> None:
    configure_logging()
    settings = get_settings()
    init_engine(settings)
    await init_redis(settings.redis_url)
    engine = make_engine(settings)
    SessionLocal = async_sessionmaker(engine, expire_on_commit=False)

    log.info("notification_worker_started")
    while True:
        event = await consume_watcher_opened(timeout_sec=5)
        if event is None:
            await asyncio.sleep(0.5)
            continue
        try:
            async with SessionLocal() as session:
                await process_event(
                    session,
                    event.event_id,
                    event.watcher_id,
                    event.opened_event_id,
                )
        except Exception as exc:
            log.exception("notification_worker_error", error=str(exc))
            await requeue_with_backoff(event, retry_count=1)


def main() -> None:
    try:
        asyncio.run(run_worker())
    except KeyboardInterrupt:
        asyncio.run(close_redis())
        sys.exit(0)


if __name__ == "__main__":
    main()
