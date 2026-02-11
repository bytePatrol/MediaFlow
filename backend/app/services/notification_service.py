import logging
from typing import Optional, List, Dict, Any

from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select

from app.models.notification_config import NotificationConfig

logger = logging.getLogger(__name__)


class NotificationService:
    def __init__(self, session: AsyncSession):
        self.session = session

    async def send_notification(self, event: str, data: Dict[str, Any]):
        result = await self.session.execute(
            select(NotificationConfig).where(NotificationConfig.is_enabled == True)
        )
        configs = result.scalars().all()

        for config in configs:
            events = config.events or []
            if event in events or "*" in events:
                await self._dispatch(config, event, data)

    async def _dispatch(self, config: NotificationConfig, event: str, data: Dict[str, Any]):
        if config.type == "webhook":
            await self._send_webhook(config.config_json, event, data)
        elif config.type == "email":
            await self._send_email(config.config_json, event, data)
        elif config.type == "push":
            logger.info(f"Push notification: {event} - {data}")

    async def _send_webhook(self, config: dict, event: str, data: Dict[str, Any]):
        import httpx
        url = config.get("url")
        if not url:
            return
        try:
            async with httpx.AsyncClient(timeout=10.0) as client:
                await client.post(url, json={"event": event, "data": data})
        except Exception as e:
            logger.error(f"Webhook failed: {e}")

    async def _send_email(self, config: dict, event: str, data: Dict[str, Any]):
        logger.info(f"Email notification: {event} to {config.get('to', 'unknown')}")
