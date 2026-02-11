from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select
from typing import List

from app.database import get_session
from app.models.notification_config import NotificationConfig

router = APIRouter()


@router.get("/")
async def list_notification_configs(session: AsyncSession = Depends(get_session)):
    result = await session.execute(select(NotificationConfig).order_by(NotificationConfig.name))
    return result.scalars().all()


@router.post("/")
async def create_notification_config(data: dict, session: AsyncSession = Depends(get_session)):
    config = NotificationConfig(
        type=data["type"],
        name=data["name"],
        config_json=data.get("config"),
        events=data.get("events", []),
        is_enabled=data.get("is_enabled", True),
    )
    session.add(config)
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
