from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select
from typing import List

from app.database import get_session
from app.models.watch_folder import WatchFolder
from app.schemas.watch_folder import WatchFolderCreate, WatchFolderUpdate, WatchFolderResponse

router = APIRouter()


@router.get("/", response_model=List[WatchFolderResponse])
async def list_watch_folders(session: AsyncSession = Depends(get_session)):
    result = await session.execute(select(WatchFolder).order_by(WatchFolder.created_at.desc()))
    return result.scalars().all()


@router.post("/", response_model=WatchFolderResponse)
async def create_watch_folder(data: WatchFolderCreate, session: AsyncSession = Depends(get_session)):
    folder = WatchFolder(**data.model_dump())
    session.add(folder)
    await session.commit()
    await session.refresh(folder)
    return folder


@router.put("/{folder_id}", response_model=WatchFolderResponse)
async def update_watch_folder(folder_id: int, data: WatchFolderUpdate, session: AsyncSession = Depends(get_session)):
    result = await session.execute(select(WatchFolder).where(WatchFolder.id == folder_id))
    folder = result.scalar_one_or_none()
    if not folder:
        raise HTTPException(status_code=404, detail="Watch folder not found")
    for key, value in data.model_dump(exclude_unset=True).items():
        setattr(folder, key, value)
    await session.commit()
    await session.refresh(folder)
    return folder


@router.delete("/{folder_id}")
async def delete_watch_folder(folder_id: int, session: AsyncSession = Depends(get_session)):
    result = await session.execute(select(WatchFolder).where(WatchFolder.id == folder_id))
    folder = result.scalar_one_or_none()
    if not folder:
        raise HTTPException(status_code=404, detail="Watch folder not found")
    await session.delete(folder)
    await session.commit()
    return {"status": "deleted"}


@router.post("/{folder_id}/toggle", response_model=WatchFolderResponse)
async def toggle_watch_folder(folder_id: int, session: AsyncSession = Depends(get_session)):
    result = await session.execute(select(WatchFolder).where(WatchFolder.id == folder_id))
    folder = result.scalar_one_or_none()
    if not folder:
        raise HTTPException(status_code=404, detail="Watch folder not found")
    folder.is_enabled = not folder.is_enabled
    await session.commit()
    await session.refresh(folder)
    return folder
