"""Server-side notification inbox for devices."""

from __future__ import annotations

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.admin import AdminBroadcast
from app.models.notification_log import NotificationLog
from app.models.watcher import Watcher


async def list_device_notifications(
    db: AsyncSession,
    device_id: int,
    *,
    device_ids: list[int] | None = None,
    limit: int = 50,
) -> list[dict]:
    """Booking-open logs for device(s) plus recent admin broadcasts."""
    out: list[dict] = []
    scope = device_ids if device_ids else [device_id]

    stmt = (
        select(NotificationLog, Watcher)
        .join(Watcher, NotificationLog.watcher_id == Watcher.id)
        .where(NotificationLog.device_id.in_(scope))
        .order_by(NotificationLog.sent_at.desc())
        .limit(limit)
    )
    for log_row, watcher in (await db.execute(stmt)).all():
        out.append(
            {
                "type": "booking_open",
                "id": log_row.id,
                "title": f"Tickets OPEN — {watcher.movie_title}",
                "body": f"{watcher.theatre_name} ({watcher.city_name})",
                "sent_at": log_row.sent_at.isoformat(),
                "watcher_id": watcher.id,
                "movie_id": watcher.bms_movie_id,
                "opened_event_id": log_row.opened_event_id,
                "status": log_row.status,
            }
        )

    broadcasts = (
        await db.execute(
            select(AdminBroadcast)
            .where(AdminBroadcast.status == "sent")
            .order_by(AdminBroadcast.sent_at.desc().nullslast())
            .limit(20)
        )
    ).scalars().all()
    for b in broadcasts:
        out.append(
            {
                "type": "admin_broadcast",
                "id": b.id,
                "title": b.title,
                "body": b.description,
                "sent_at": b.sent_at.isoformat() if b.sent_at else None,
                "image_url": b.image_url,
                "status": b.status,
            }
        )

    out.sort(key=lambda x: x.get("sent_at") or "", reverse=True)
    return out[:limit]
