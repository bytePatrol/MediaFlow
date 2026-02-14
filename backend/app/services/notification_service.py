import json
import logging
from typing import Optional, List, Dict, Any

from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select

from app.models.notification_config import NotificationConfig
from app.models.notification_log import NotificationLog
from app.database import async_session_factory

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
                    await self._log_dispatch(
                        event=event,
                        channel_type=config.type,
                        channel_name=config.name,
                        data=data,
                        status="sent",
                    )
                except Exception as e:
                    logger.error(f"Notification dispatch failed for {config.name}: {e}")
                    await self._log_dispatch(
                        event=event,
                        channel_type=config.type,
                        channel_name=config.name,
                        data=data,
                        status="failed",
                        error_message=str(e),
                    )

    async def _log_dispatch(
        self,
        event: str,
        channel_type: str,
        channel_name: str,
        data: Dict[str, Any],
        status: str = "sent",
        error_message: Optional[str] = None,
    ):
        """Log a notification dispatch to the notification_logs table."""
        try:
            async with async_session_factory() as log_session:
                log_entry = NotificationLog(
                    event=event,
                    channel_type=channel_type,
                    channel_name=channel_name,
                    payload_json=json.dumps(data, default=str),
                    status=status,
                    error_message=error_message,
                )
                log_session.add(log_entry)
                await log_session.commit()
        except Exception as e:
            logger.error(f"Failed to log notification dispatch: {e}")

    async def _dispatch(self, config: NotificationConfig, event: str, data: Dict[str, Any]):
        if config.type == "webhook":
            await self._send_webhook(config.config_json, event, data)
        elif config.type == "email":
            await self._send_email(config.config_json, event, data)
        elif config.type == "discord":
            await self._send_discord(config.config_json or {}, event, data)
        elif config.type == "slack":
            await self._send_slack(config.config_json or {}, event, data)
        elif config.type == "telegram":
            await self._send_telegram(config.config_json or {}, event, data)
        elif config.type == "push":
            logger.info(f"Push notification: {event} - {data}")
        # Update trigger tracking
        from datetime import datetime as dt
        config.last_triggered_at = dt.utcnow()
        config.trigger_count = (config.trigger_count or 0) + 1

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

    async def _send_discord(self, config: dict, event: str, data: Dict[str, Any]):
        """Send notification to Discord via webhook."""
        import httpx
        url = config.get("webhook_url") or config.get("url")
        if not url:
            return

        subject = self._format_subject(event, data)
        body_text = self._format_plain_body(event, data)

        # Discord embed
        color_map = {"job.completed": 0x38a169, "job.failed": 0xe53e3e, "server.offline": 0xe53e3e,
                     "server.online": 0x38a169, "cloud.spend_cap_reached": 0xf59e0b}
        color = color_map.get(event, 0x256af4)

        payload = {
            "embeds": [{
                "title": subject,
                "description": body_text,
                "color": color,
                "footer": {"text": "MediaFlow"},
                "timestamp": __import__("datetime").datetime.utcnow().isoformat() + "Z",
            }]
        }
        try:
            async with httpx.AsyncClient(timeout=10.0) as client:
                resp = await client.post(url, json=payload)
                resp.raise_for_status()
        except Exception as e:
            logger.error(f"Discord webhook failed: {e}")
            raise

    async def _send_slack(self, config: dict, event: str, data: Dict[str, Any]):
        """Send notification to Slack via webhook."""
        import httpx
        url = config.get("webhook_url") or config.get("url")
        if not url:
            return

        subject = self._format_subject(event, data)
        body_text = self._format_plain_body(event, data)

        # Slack Block Kit
        payload = {
            "blocks": [
                {"type": "header", "text": {"type": "plain_text", "text": subject}},
                {"type": "section", "text": {"type": "mrkdwn", "text": body_text}},
                {"type": "context", "elements": [
                    {"type": "mrkdwn", "text": f"_MediaFlow • {event}_"}
                ]},
            ]
        }
        try:
            async with httpx.AsyncClient(timeout=10.0) as client:
                resp = await client.post(url, json=payload)
                resp.raise_for_status()
        except Exception as e:
            logger.error(f"Slack webhook failed: {e}")
            raise

    async def _send_telegram(self, config: dict, event: str, data: Dict[str, Any]):
        """Send notification via Telegram Bot API."""
        import httpx
        bot_token = config.get("bot_token")
        chat_id = config.get("chat_id")
        if not bot_token or not chat_id:
            return

        subject = self._format_subject(event, data)
        body_text = self._format_plain_body(event, data)
        text = f"*{subject}*\n\n{body_text}"

        url = f"https://api.telegram.org/bot{bot_token}/sendMessage"
        payload = {"chat_id": chat_id, "text": text, "parse_mode": "Markdown"}
        try:
            async with httpx.AsyncClient(timeout=10.0) as client:
                resp = await client.post(url, json=payload)
                resp.raise_for_status()
        except Exception as e:
            logger.error(f"Telegram send failed: {e}")
            raise

    @staticmethod
    def _format_subject(event: str, data: Dict[str, Any]) -> str:
        event_labels = {
            "job.completed": "Transcode Job Completed",
            "job.failed": "Transcode Job Failed",
            "analysis.completed": "Analysis Completed",
            "server.offline": "Server Offline",
            "server.online": "Server Online",
            "cloud.deploy_completed": "Cloud GPU Deployed",
            "cloud.teardown_completed": "Cloud GPU Torn Down",
            "cloud.spend_cap_reached": "Spend Cap Reached",
            "queue.stalled": "Queue Stalled",
            "sync.completed": "Library Sync Completed",
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
    def _format_plain_body(event: str, data: Dict[str, Any]) -> str:
        """Plain text body for Discord/Slack/Telegram."""
        if event == "job.completed":
            output_size = data.get("output_size")
            duration = data.get("duration")
            size_str = f"{output_size / (1024*1024):.1f} MB" if output_size else "N/A"
            dur_str = f"{duration:.1f}s" if duration else "N/A"
            return f"Job #{data.get('job_id', 'N/A')} completed • Output: {size_str} • Duration: {dur_str}"
        elif event == "job.failed":
            return f"Job #{data.get('job_id', 'N/A')} failed: {data.get('error', 'Unknown error')}"
        elif event == "analysis.completed":
            return (f"Analysis found {data.get('recommendations_generated', 0)} recommendations, "
                    f"{data.get('total_estimated_savings', 0) / 1_000_000_000:.1f} GB potential savings")
        elif event == "server.offline":
            return f"Worker server \"{data.get('server_name', 'Unknown')}\" went offline"
        elif event == "server.online":
            return f"Worker server \"{data.get('server_name', 'Unknown')}\" came back online"
        elif event == "cloud.deploy_completed":
            return f"Cloud GPU deployed: {data.get('hostname', 'Unknown')} at ${data.get('hourly_cost', 0):.2f}/hr"
        elif event == "cloud.teardown_completed":
            return f"Cloud GPU torn down. Total cost: ${data.get('total_cost', 0):.2f}"
        elif event == "cloud.spend_cap_reached":
            return f"Spend cap reached: ${data.get('current_cost', 0):.2f} (cap: ${data.get('cap', 0):.2f})"
        elif event == "sync.completed":
            return f"Library sync completed: {data.get('items_synced', 0)} items found"
        elif event == "queue.stalled":
            return f"Queue stalled: {data.get('waiting_jobs', 0)} jobs waiting, no workers available"
        else:
            return f"{event}: {data}"

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

    @staticmethod
    async def test_discord(config: Dict[str, Any]) -> str:
        service = NotificationService.__new__(NotificationService)
        try:
            await service._send_discord(config, "test", {"message": "Test notification from MediaFlow."})
            return "Test Discord notification sent successfully"
        except Exception as e:
            return f"Test Discord notification failed: {e}"

    @staticmethod
    async def test_slack(config: Dict[str, Any]) -> str:
        service = NotificationService.__new__(NotificationService)
        try:
            await service._send_slack(config, "test", {"message": "Test notification from MediaFlow."})
            return "Test Slack notification sent successfully"
        except Exception as e:
            return f"Test Slack notification failed: {e}"

    @staticmethod
    async def test_telegram(config: Dict[str, Any]) -> str:
        service = NotificationService.__new__(NotificationService)
        try:
            await service._send_telegram(config, "test", {"message": "Test notification from MediaFlow."})
            return "Test Telegram notification sent successfully"
        except Exception as e:
            return f"Test Telegram notification failed: {e}"
