from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select
from typing import List

from app.database import get_session
from app.models.filter_preset import FilterPreset
from app.schemas.filter_preset import FilterPresetCreate, FilterPresetUpdate, FilterPresetResponse

router = APIRouter()


@router.get("/", response_model=List[FilterPresetResponse])
async def list_filter_presets(session: AsyncSession = Depends(get_session)):
    result = await session.execute(select(FilterPreset).order_by(FilterPreset.name))
    return result.scalars().all()


@router.post("/", response_model=FilterPresetResponse)
async def create_filter_preset(
    data: FilterPresetCreate, session: AsyncSession = Depends(get_session)
):
    preset = FilterPreset(name=data.name, filter_json=data.filter_json)
    session.add(preset)
    await session.commit()
    await session.refresh(preset)
    return preset


@router.put("/{preset_id}", response_model=FilterPresetResponse)
async def update_filter_preset(
    preset_id: int, data: FilterPresetUpdate, session: AsyncSession = Depends(get_session)
):
    result = await session.execute(select(FilterPreset).where(FilterPreset.id == preset_id))
    preset = result.scalar_one_or_none()
    if not preset:
        raise HTTPException(status_code=404, detail="Filter preset not found")
    if data.name is not None:
        preset.name = data.name
    if data.filter_json is not None:
        preset.filter_json = data.filter_json
    await session.commit()
    await session.refresh(preset)
    return preset


@router.delete("/{preset_id}")
async def delete_filter_preset(preset_id: int, session: AsyncSession = Depends(get_session)):
    result = await session.execute(select(FilterPreset).where(FilterPreset.id == preset_id))
    preset = result.scalar_one_or_none()
    if not preset:
        raise HTTPException(status_code=404, detail="Filter preset not found")
    await session.delete(preset)
    await session.commit()
    return {"status": "deleted"}
