"""In-app notification feed (booking-open inbox + admin broadcasts)."""

from __future__ import annotations

from fastapi import APIRouter, Depends, Query
from pydantic import BaseModel
from sqlalchemy import select

from app.api.deps import DbSession, get_current_device
from app.models.admin import AdminBroadcast
from app.models.device import Device
from app.services.device_inbox_service import list_device_notifications
from app.services.user_scope_service import device_ids_for_scope

router = APIRouter(prefix="/notifications", tags=["notifications"])


class BroadcastOut(BaseModel):
    id: int
    title: str
    description: str
    image_url: str | None = None
    sent_at: str | None = None


class InboxItemOut(BaseModel):
    type: str
    id: int
    title: str
    body: str
    sent_at: str | None = None
    watcher_id: int | None = None
    movie_id: str | None = None
    opened_event_id: str | None = None
    status: str | None = None
    image_url: str | None = None


@router.get("/inbox", response_model=list[InboxItemOut])
async def list_inbox(
    db: DbSession,
    device: Device = Depends(get_current_device),
    limit: int = Query(50, ge=1, le=100),
) -> list[InboxItemOut]:
    """Unified inbox for web/mobile: booking-open events + admin broadcasts."""
    scope_ids = await device_ids_for_scope(db, device)
    rows = await list_device_notifications(
        db,
        device.id,
        device_ids=scope_ids,
        limit=limit,
    )
    return [InboxItemOut(**r) for r in rows]


@router.get("/broadcasts", response_model=list[BroadcastOut])
async def list_broadcasts(
    db: DbSession,
    _device: Device = Depends(get_current_device),
) -> list[BroadcastOut]:
    """Marketing messages from admin — visible in-app (web + mobile)."""
    rows = (
        await db.execute(
            select(AdminBroadcast)
            .where(AdminBroadcast.status == "sent")
            .order_by(AdminBroadcast.sent_at.desc().nullslast(), AdminBroadcast.id.desc())
            .limit(50)
        )
    ).scalars().all()
    return [
        BroadcastOut(
            id=r.id,
            title=r.title,
            description=r.description,
            image_url=r.image_url,
            sent_at=r.sent_at.isoformat() if r.sent_at else None,
        )
        for r in rows
    ]
