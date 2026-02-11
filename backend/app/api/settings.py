from fastapi import APIRouter, Depends
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select

from app.database import get_session
from app.models.app_settings import AppSetting

router = APIRouter()


@router.get("/")
async def get_all_settings(session: AsyncSession = Depends(get_session)):
    result = await session.execute(select(AppSetting))
    settings = result.scalars().all()
    return {s.key: s.value for s in settings}


@router.get("/{key}")
async def get_setting(key: str, session: AsyncSession = Depends(get_session)):
    result = await session.execute(select(AppSetting).where(AppSetting.key == key))
    setting = result.scalar_one_or_none()
    if not setting:
        return {"key": key, "value": None}
    return {"key": setting.key, "value": setting.value}


@router.put("/{key}")
async def set_setting(key: str, value: dict, session: AsyncSession = Depends(get_session)):
    result = await session.execute(select(AppSetting).where(AppSetting.key == key))
    setting = result.scalar_one_or_none()
    if setting:
        setting.value = value.get("value")
    else:
        setting = AppSetting(key=key, value=value.get("value"))
        session.add(setting)
    await session.commit()
    return {"key": key, "value": setting.value}
