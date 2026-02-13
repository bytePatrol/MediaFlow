from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select
from typing import List

from app.database import get_session
from app.models.notification_config import NotificationConfig
from app.schemas.notification import (
    NotificationConfigCreate,
    NotificationConfigUpdate,
    NotificationConfigResponse,
    NOTIFICATION_EVENTS,
    NotificationEventInfo,
)
from app.services.notification_service import NotificationService

router = APIRouter()


@router.get("/events")
async def list_notification_events():
    return [NotificationEventInfo(event=k, description=v) for k, v in NOTIFICATION_EVENTS.items()]


@router.get("/", response_model=List[NotificationConfigResponse])
async def list_notification_configs(session: AsyncSession = Depends(get_session)):
    result = await session.execute(select(NotificationConfig).order_by(NotificationConfig.name))
    return result.scalars().all()


@router.post("/", response_model=NotificationConfigResponse)
async def create_notification_config(
    data: NotificationConfigCreate, session: AsyncSession = Depends(get_session)
):
    config = NotificationConfig(
        type=data.type,
        name=data.name,
        config_json=data.config,
        events=data.events,
        is_enabled=data.is_enabled,
    )
    session.add(config)
    await session.commit()
    await session.refresh(config)
    return config


@router.put("/{config_id}", response_model=NotificationConfigResponse)
async def update_notification_config(
    config_id: int,
    data: NotificationConfigUpdate,
    session: AsyncSession = Depends(get_session),
):
    result = await session.execute(
        select(NotificationConfig).where(NotificationConfig.id == config_id)
    )
    config = result.scalar_one_or_none()
    if not config:
        raise HTTPException(status_code=404, detail="Config not found")

    if data.name is not None:
        config.name = data.name
    if data.config is not None:
        config.config_json = data.config
    if data.events is not None:
        config.events = data.events
    if data.is_enabled is not None:
        config.is_enabled = data.is_enabled

    await session.commit()
    await session.refresh(config)
    return config


@router.delete("/{config_id}")
async def delete_notification_config(config_id: int, session: AsyncSession = Depends(get_session)):
    result = await session.execute(select(NotificationConfig).where(NotificationConfig.id == config_id))
    config = result.scalar_one_or_none()
    if not config:
        raise HTTPException(status_code=404, detail="Config not found")
    await session.delete(config)
    await session.commit()
    return {"status": "deleted"}


@router.post("/{config_id}/test")
async def test_notification(config_id: int, session: AsyncSession = Depends(get_session)):
    result = await session.execute(
        select(NotificationConfig).where(NotificationConfig.id == config_id)
    )
    config = result.scalar_one_or_none()
    if not config:
        raise HTTPException(status_code=404, detail="Config not found")

    config_data = config.config_json or {}
    if config.type == "email":
        message = await NotificationService.test_email(config_data)
    elif config.type == "webhook":
        message = await NotificationService.test_webhook(config_data)
    elif config.type == "discord":
        message = await NotificationService.test_discord(config_data)
    elif config.type == "slack":
        message = await NotificationService.test_slack(config_data)
    elif config.type == "telegram":
        message = await NotificationService.test_telegram(config_data)
    else:
        message = f"Test not supported for type: {config.type}"

    return {"status": "ok", "message": message}
