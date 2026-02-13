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
                try:
                    await self._dispatch(config, event, data)
                except Exception as e:
                    logger.error(f"Notification dispatch failed for {config.name}: {e}")

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
        import aiosmtplib
        from email.mime.text import MIMEText
        from email.mime.multipart import MIMEMultipart

        smtp_host = config.get("smtp_host")
        smtp_port = config.get("smtp_port", 587)
        username = config.get("smtp_username")
        password = config.get("smtp_password")
        from_addr = config.get("from_address", username)
        to_addr = config.get("to_address")
        use_tls = config.get("use_tls", True)

        if not smtp_host or not to_addr:
            logger.warning("Email notification skipped: missing smtp_host or to_address")
            return

        subject = self._format_subject(event, data)
        body = self._format_body(event, data)

        msg = MIMEMultipart("alternative")
        msg["Subject"] = subject
        msg["From"] = from_addr or ""
        msg["To"] = to_addr
        msg.attach(MIMEText(body, "html"))

        try:
            await aiosmtplib.send(
                msg,
                hostname=smtp_host,
                port=smtp_port,
                username=username,
                password=password,
                start_tls=use_tls,
            )
            logger.info(f"Email sent to {to_addr}: {subject}")
        except Exception as e:
            logger.error(f"Email send failed: {e}")
            raise

    @staticmethod
    def _format_subject(event: str, data: Dict[str, Any]) -> str:
        event_labels = {
            "job.completed": "Transcode Job Completed",
            "job.failed": "Transcode Job Failed",
        }
        label = event_labels.get(event, event.replace(".", " ").title())
        job_id = data.get("job_id", "")
        if job_id:
            return f"[MediaFlow] {label} - Job #{job_id}"
        return f"[MediaFlow] {label}"

    @staticmethod
    def _format_body(event: str, data: Dict[str, Any]) -> str:
        job_id = data.get("job_id", "N/A")

        if event == "job.completed":
            output_size = data.get("output_size")
            duration = data.get("duration")
            size_str = f"{output_size / (1024*1024):.1f} MB" if output_size else "N/A"
            dur_str = f"{duration:.1f}s" if duration else "N/A"
            return f"""
            <div style="font-family: -apple-system, sans-serif; max-width: 500px; margin: 0 auto;">
                <h2 style="color: #38a169;">Transcode Completed</h2>
                <table style="width: 100%; border-collapse: collapse;">
                    <tr><td style="padding: 8px 0; color: #888;">Job ID</td><td style="padding: 8px 0;">#{job_id}</td></tr>
                    <tr><td style="padding: 8px 0; color: #888;">Output Size</td><td style="padding: 8px 0;">{size_str}</td></tr>
                    <tr><td style="padding: 8px 0; color: #888;">Duration</td><td style="padding: 8px 0;">{dur_str}</td></tr>
                </table>
                <p style="color: #666; font-size: 12px; margin-top: 24px;">Sent by MediaFlow</p>
            </div>
            """
        elif event == "job.failed":
            error = data.get("error", "Unknown error")
            return f"""
            <div style="font-family: -apple-system, sans-serif; max-width: 500px; margin: 0 auto;">
                <h2 style="color: #e53e3e;">Transcode Failed</h2>
                <table style="width: 100%; border-collapse: collapse;">
                    <tr><td style="padding: 8px 0; color: #888;">Job ID</td><td style="padding: 8px 0;">#{job_id}</td></tr>
                    <tr><td style="padding: 8px 0; color: #888;">Error</td><td style="padding: 8px 0; color: #e53e3e;">{error}</td></tr>
                </table>
                <p style="color: #666; font-size: 12px; margin-top: 24px;">Sent by MediaFlow</p>
            </div>
            """
        else:
            return f"""
            <div style="font-family: -apple-system, sans-serif; max-width: 500px; margin: 0 auto;">
                <h2>{event.replace(".", " ").title()}</h2>
                <pre style="background: #f5f5f5; padding: 12px; border-radius: 6px; overflow: auto;">{data}</pre>
                <p style="color: #666; font-size: 12px; margin-top: 24px;">Sent by MediaFlow</p>
            </div>
            """

    @staticmethod
    async def test_email(config: Dict[str, Any]) -> str:
        """Send a test email and return status message."""
        service = NotificationService.__new__(NotificationService)
        try:
            await service._send_email(config, "test", {
                "job_id": 0,
                "message": "This is a test notification from MediaFlow.",
            })
            return "Test email sent successfully"
        except Exception as e:
            return f"Test email failed: {e}"

    @staticmethod
    async def test_webhook(config: Dict[str, Any]) -> str:
        """Send a test webhook and return status message."""
        service = NotificationService.__new__(NotificationService)
        try:
            await service._send_webhook(config, "test", {
                "message": "This is a test notification from MediaFlow.",
            })
            return "Test webhook sent successfully"
        except Exception as e:
            return f"Test webhook failed: {e}"
