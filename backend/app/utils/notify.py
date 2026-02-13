import logging

logger = logging.getLogger(__name__)


async def fire_notification(event: str, data: dict):
    """Fire-and-forget notification dispatch with its own session."""
    from app.database import async_session_factory
    try:
        async with async_session_factory() as session:
            from app.services.notification_service import NotificationService
            service = NotificationService(session)
            await service.send_notification(event, data)
            await session.commit()
    except Exception as e:
        logger.warning(f"Notification dispatch failed for {event}: {e}")
