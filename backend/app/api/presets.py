from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select
from typing import List

from app.database import get_session
from app.models.transcode_preset import TranscodePreset
from app.schemas.transcode import TranscodePresetResponse, TranscodePresetCreate, TranscodePresetUpdate

router = APIRouter()


@router.get("/", response_model=List[TranscodePresetResponse])
async def list_presets(session: AsyncSession = Depends(get_session)):
    result = await session.execute(select(TranscodePreset).order_by(TranscodePreset.is_builtin.desc(), TranscodePreset.name))
    return result.scalars().all()


@router.get("/{preset_id}", response_model=TranscodePresetResponse)
async def get_preset(preset_id: int, session: AsyncSession = Depends(get_session)):
    result = await session.execute(select(TranscodePreset).where(TranscodePreset.id == preset_id))
    preset = result.scalar_one_or_none()
    if not preset:
        raise HTTPException(status_code=404, detail="Preset not found")
    return preset


@router.post("/", response_model=TranscodePresetResponse)
async def create_preset(data: TranscodePresetCreate, session: AsyncSession = Depends(get_session)):
    preset = TranscodePreset(**data.model_dump())
    session.add(preset)
    await session.commit()
    await session.refresh(preset)
    return preset


@router.put("/{preset_id}", response_model=TranscodePresetResponse)
async def update_preset(
    preset_id: int, data: TranscodePresetUpdate, session: AsyncSession = Depends(get_session)
):
    result = await session.execute(select(TranscodePreset).where(TranscodePreset.id == preset_id))
    preset = result.scalar_one_or_none()
    if not preset:
        raise HTTPException(status_code=404, detail="Preset not found")
    if preset.is_builtin:
        raise HTTPException(status_code=400, detail="Cannot modify built-in presets")
    for key, value in data.model_dump(exclude_unset=True).items():
        setattr(preset, key, value)
    await session.commit()
    await session.refresh(preset)
    return preset


@router.delete("/{preset_id}")
async def delete_preset(preset_id: int, session: AsyncSession = Depends(get_session)):
    result = await session.execute(select(TranscodePreset).where(TranscodePreset.id == preset_id))
    preset = result.scalar_one_or_none()
    if not preset:
        raise HTTPException(status_code=404, detail="Preset not found")
    if preset.is_builtin:
        raise HTTPException(status_code=400, detail="Cannot delete built-in presets")
    await session.delete(preset)
    await session.commit()
    return {"status": "deleted"}
