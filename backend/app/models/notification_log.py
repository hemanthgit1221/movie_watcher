"""FCM notification log model."""

from __future__ import annotations

from datetime import datetime

from sqlalchemy import DateTime, ForeignKey, String, UniqueConstraint
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.db.base import Base


class NotificationLog(Base):
    __tablename__ = "notification_logs"
    __table_args__ = (
        UniqueConstraint(
            "watcher_id",
            "device_id",
            "opened_event_id",
            name="uq_notification_dedupe",
        ),
    )

    id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
    watcher_id: Mapped[int] = mapped_column(ForeignKey("watchers.id", ondelete="CASCADE"), nullable=False)
    device_id: Mapped[int] = mapped_column(ForeignKey("devices.id", ondelete="CASCADE"), nullable=False)
    opened_event_id: Mapped[str] = mapped_column(String(64), nullable=False)
    sent_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
    fcm_message_id: Mapped[str | None] = mapped_column(String(256), nullable=True)
    status: Mapped[str] = mapped_column(String(32), nullable=False)

    watcher: Mapped["Watcher"] = relationship(back_populates="notification_logs")
