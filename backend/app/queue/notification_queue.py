"""Redis-backed notification event queue."""

from __future__ import annotations

import json
from dataclasses import asdict, dataclass

import structlog

from app.core.redis_client import get_redis

log = structlog.get_logger(__name__)

QUEUE_KEY = "moovaa:notification_events"
DLQ_KEY = "moovaa:notification_events:dlq"


@dataclass
class WatcherOpenedEvent:
    event_id: int
    watcher_id: int
    opened_event_id: str


async def publish_watcher_opened(event: WatcherOpenedEvent) -> bool:
    redis = get_redis()
    if redis is None:
        log.warning("queue_unavailable_sync_fallback", watcher_id=event.watcher_id)
        return False
    payload = json.dumps(asdict(event))
    await redis.lpush(QUEUE_KEY, payload)
    log.info("notification_event_queued", watcher_id=event.watcher_id, event_id=event.event_id)
    return True


async def consume_watcher_opened(timeout_sec: int = 5) -> WatcherOpenedEvent | None:
    redis = get_redis()
    if redis is None:
        return None
    result = await redis.brpop(QUEUE_KEY, timeout=timeout_sec)
    if not result:
        return None
    _, raw = result
    data = json.loads(raw)
    return WatcherOpenedEvent(**data)


async def requeue_with_backoff(event: WatcherOpenedEvent, retry_count: int) -> None:
    redis = get_redis()
    if redis is None:
        return
    if retry_count >= 5:
        await redis.lpush(DLQ_KEY, json.dumps(asdict(event)))
        return
    await redis.lpush(QUEUE_KEY, json.dumps(asdict(event)))
