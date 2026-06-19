"""FCM batch send + notification_logs idempotency."""

from __future__ import annotations

import asyncio
from dataclasses import dataclass
from datetime import UTC, datetime, timedelta

import structlog
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.config import get_settings
from app.models.device import Device
from app.models.notification_log import NotificationLog
from app.models.subscription import Subscription
from app.models.watcher import Watcher
from app.services.notification_enqueue import enqueue_watcher_opened

log = structlog.get_logger(__name__)


@dataclass(frozen=True)
class NotifyPayload:
    title: str
    body: str
    data: dict[str, str]


@dataclass(frozen=True)
class NotifySummary:
    opened_event_id: str
    attempted: int
    sent: int
    skipped_existing: int
    dry_run: bool
    queued: bool = False


def build_open_payload(watcher: Watcher) -> NotifyPayload:
    """Legacy payload — includes booking_url (deprecated)."""
    return build_open_payload_secure(watcher, make_opened_event_id(watcher.id))


def build_open_payload_secure(watcher: Watcher, opened_event_id: str) -> NotifyPayload:
    title = f"Tickets OPEN — {watcher.movie_title}"
    body = f"{watcher.theatre_name} ({watcher.city_name}) is now bookable!"
    data = {
        "type": "booking_open",
        "watcher_id": str(watcher.id),
        "movie_id": watcher.bms_movie_id,
        "opened_event_id": opened_event_id,
        "sent_at": datetime.now(tz=UTC).isoformat(),
        "movie": watcher.movie_title,
        "theatre": watcher.theatre_name,
        "city": watcher.city_name,
    }
    return NotifyPayload(title=title, body=body, data=data)


def make_opened_event_id(watcher_id: int, opened_at: datetime | None = None) -> str:
    _ = opened_at
    return f"w{watcher_id}-open"


async def _subscriber_rows(
    db: AsyncSession,
    watcher_id: int,
    *,
    allowed_device_ids: frozenset[int] | None = None,
) -> list[tuple[Subscription, Device]]:
    stmt = (
        select(Subscription, Device)
        .join(Device, Subscription.device_id == Device.id)
        .where(
            Subscription.watcher_id == watcher_id,
            Subscription.is_active.is_(True),
            Device.is_active.is_(True),
        )
    )
    rows = (await db.execute(stmt)).all()
    if allowed_device_ids is None:
        return list(rows)
    return [(sub, device) for sub, device in rows if device.id in allowed_device_ids]


async def _write_in_app_watcher_logs(
    db: AsyncSession,
    *,
    watcher_id: int,
    opened_event_id: str,
    device_ids: list[int],
    sent_at: datetime,
    status: str,
) -> int:
    """Persist inbox rows for web / no-FCM subscribers."""
    written = 0
    for device_id in device_ids:
        dup = (
            await db.execute(
                select(NotificationLog.id).where(
                    NotificationLog.watcher_id == watcher_id,
                    NotificationLog.device_id == device_id,
                    NotificationLog.opened_event_id == opened_event_id,
                )
            )
        ).scalar_one_or_none()
        if dup is not None:
            continue
        db.add(
            NotificationLog(
                watcher_id=watcher_id,
                device_id=device_id,
                opened_event_id=opened_event_id,
                sent_at=sent_at,
                status=status,
            )
        )
        written += 1
    return written


async def notify_watcher_opened(
    db: AsyncSession,
    watcher_id: int,
    *,
    fcm_enabled: bool,
    dry_run: bool,
    allowed_device_ids: frozenset[int] | None = None,
    open_cooldown_minutes: int = 60,
) -> NotifySummary | None:
    watcher = await db.get(Watcher, watcher_id)
    if watcher is None:
        return None

    now = datetime.now(tz=UTC)
    if watcher.opened_at is None:
        watcher.status = "opened"
        watcher.opened_at = now
        watcher.last_detector_state = "OPEN"
        watcher.consecutive_failures = 0
    opened_event_id = make_opened_event_id(watcher.id, watcher.opened_at)
    watcher.next_check_at = now + timedelta(minutes=max(1, open_cooldown_minutes))

    rows = await _subscriber_rows(db, watcher_id, allowed_device_ids=allowed_device_ids)

    attempted = 0
    sent = 0
    skipped = 0
    tokens: list[str] = []
    token_map: list[tuple[int, int]] = []
    in_app_only_device_ids: list[int] = []

    for sub, device in rows:
        dup = (
            await db.execute(
                select(NotificationLog.id).where(
                    NotificationLog.watcher_id == watcher_id,
                    NotificationLog.device_id == device.id,
                    NotificationLog.opened_event_id == opened_event_id,
                )
            )
        ).scalar_one_or_none()
        if dup is not None:
            skipped += 1
            continue
        token = (device.fcm_token or "").strip()
        if not token:
            in_app_only_device_ids.append(device.id)
            continue
        tokens.append(token)
        token_map.append((sub.id, device.id))
        attempted += 1

    in_app_status = "dry_run" if dry_run else "in_app_only"
    await _write_in_app_watcher_logs(
        db,
        watcher_id=watcher_id,
        opened_event_id=opened_event_id,
        device_ids=in_app_only_device_ids,
        sent_at=now,
        status=in_app_status,
    )

    settings = get_settings()
    use_queue = settings.fcm_use_queue or settings.redis_required
    if use_queue and fcm_enabled and not dry_run:
        await enqueue_watcher_opened(
            db,
            watcher_id=watcher_id,
            opened_event_id=opened_event_id,
        )
        return NotifySummary(
            opened_event_id=opened_event_id,
            attempted=attempted,
            sent=0,
            skipped_existing=skipped,
            dry_run=False,
            queued=True,
        )

    payload = build_open_payload_secure(watcher, opened_event_id)

    if dry_run or not fcm_enabled:
        for _, device_id in token_map:
            log_row = NotificationLog(
                watcher_id=watcher_id,
                device_id=device_id,
                opened_event_id=opened_event_id,
                sent_at=now,
                status="dry_run" if dry_run else "skipped_fcm_disabled",
            )
            db.add(log_row)
        return NotifySummary(
            opened_event_id=opened_event_id,
            attempted=attempted,
            sent=0,
            skipped_existing=skipped,
            dry_run=dry_run or not fcm_enabled,
        )

    batch_size = settings.notification_batch_size
    for i in range(0, len(tokens), batch_size):
        chunk_tokens = tokens[i : i + batch_size]
        chunk_map = token_map[i : i + batch_size]
        results = await send_multicast_batch(chunk_tokens, payload)
        for (_, device_id), result in zip(chunk_map, results, strict=False):
            ok, stale = result
            if stale:
                device_row = await db.get(Device, device_id)
                if device_row is not None:
                    device_row.is_active = False
                    device_row.fcm_token = None
                    log.info("fcm_token_deactivated", device_id=device_id)
            log_row = NotificationLog(
                watcher_id=watcher_id,
                device_id=device_id,
                opened_event_id=opened_event_id,
                sent_at=now,
                status="success" if ok else ("stale_token" if stale else "failed"),
            )
            db.add(log_row)
            if ok:
                sent += 1

    summary = NotifySummary(
        opened_event_id=opened_event_id,
        attempted=attempted,
        sent=sent,
        skipped_existing=skipped,
        dry_run=False,
    )
    log.info(
        "watcher_notify_complete",
        watcher_id=watcher_id,
        opened_event_id=opened_event_id,
        attempted=attempted,
        sent=sent,
        skipped=skipped,
    )
    return summary


def _platform_configs(payload: NotifyPayload) -> tuple[object | None, object | None]:
    """Android/iOS delivery settings aligned with Flutter notification channels."""
    try:
        from firebase_admin import messaging
    except ImportError:
        return None, None

    ntype = payload.data.get("type", "")
    if ntype in ("booking_open", "admin_broadcast"):
        android = messaging.AndroidConfig(
            priority="high",
            notification=messaging.AndroidNotification(
                channel_id="moovaa_booking_alerts",
                sound="default",
                priority="high",
                default_vibrate_timings=True,
                default_light_settings=True,
                ticker=payload.title,
            ),
        )
        apns = messaging.APNSConfig(
            payload=messaging.APNSPayload(
                aps=messaging.Aps(
                    sound="default",
                    badge=1,
                    alert=messaging.ApsAlert(title=payload.title, body=payload.body),
                ),
            ),
        )
        return android, apns

    android = messaging.AndroidConfig(
        priority="normal",
        notification=messaging.AndroidNotification(
            channel_id="moovaa_reminders",
            sound="default",
            default_vibrate_timings=True,
        ),
    )
    apns = messaging.APNSConfig(
        payload=messaging.APNSPayload(
            aps=messaging.Aps(
                sound="default",
                alert=messaging.ApsAlert(title=payload.title, body=payload.body),
            ),
        ),
    )
    return android, apns


def _is_stale_fcm_error(exc: BaseException | None) -> bool:
    if exc is None:
        return False
    msg = str(exc).upper()
    return any(
        token in msg
        for token in (
            "UNREGISTERED",
            "NOT_FOUND",
            "INVALID_ARGUMENT",
            "REGISTRATION_TOKEN_NOT_REGISTERED",
        )
    )


async def send_multicast_batch(
    tokens: list[str], payload: NotifyPayload
) -> list[tuple[bool, bool]]:
    """Returns list of (success, stale_token)."""
    if not tokens:
        return []

    def _sync_multicast() -> list[tuple[bool, bool]]:
        try:
            import firebase_admin
            from firebase_admin import credentials, messaging
        except ImportError:
            log.error("firebase_admin_not_installed")
            return [(False, False)] * len(tokens)

        if not firebase_admin._apps:
            cred = credentials.ApplicationDefault()
            firebase_admin.initialize_app(cred)

        android, apns = _platform_configs(payload)
        message = messaging.MulticastMessage(
            notification=messaging.Notification(title=payload.title, body=payload.body),
            data=payload.data,
            tokens=tokens,
            android=android,
            apns=apns,
        )
        response = messaging.send_each_for_multicast(message)
        results: list[tuple[bool, bool]] = []
        for idx, resp in enumerate(response.responses):
            if resp.success:
                results.append((True, False))
            else:
                err = resp.exception
                stale = _is_stale_fcm_error(err)
                log.warning("fcm_multicast_failed", index=idx, error=str(err), stale=stale)
                results.append((False, stale))
        return results

    try:
        return await asyncio.to_thread(_sync_multicast)
    except Exception as e:  # noqa: BLE001
        log.warning("fcm_multicast_batch_failed", error=str(e))
        return [(False, False)] * len(tokens)


async def resolve_booking_url(db: AsyncSession, watcher_id: int, device_id: int) -> str | None:
    """Resolve booking URL server-side for notification tap."""
    sub = (
        await db.execute(
            select(Subscription)
            .join(Watcher, Subscription.watcher_id == Watcher.id)
            .where(
                Subscription.watcher_id == watcher_id,
                Subscription.device_id == device_id,
                Subscription.is_active.is_(True),
            )
        )
    ).scalar_one_or_none()
    if sub is None:
        return None
    watcher = await db.get(Watcher, watcher_id)
    if watcher is None:
        return None
    return watcher.booking_url
