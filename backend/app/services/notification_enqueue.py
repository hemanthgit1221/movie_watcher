"""Queue publish helpers for watcher OPEN events."""

from __future__ import annotations

from datetime import UTC, datetime

from sqlalchemy.ext.asyncio import AsyncSession

from app.models.ops import NotificationEvent
from app.queue.notification_queue import WatcherOpenedEvent, publish_watcher_opened


async def enqueue_watcher_opened(
    db: AsyncSession,
    *,
    watcher_id: int,
    opened_event_id: str,
) -> NotificationEvent:
    row = NotificationEvent(
        watcher_id=watcher_id,
        opened_event_id=opened_event_id,
        status="pending",
        created_at=datetime.now(tz=UTC),
    )
    db.add(row)
    await db.flush()
    await publish_watcher_opened(
        WatcherOpenedEvent(
            event_id=row.id,
            watcher_id=watcher_id,
            opened_event_id=opened_event_id,
        )
    )
    return row
