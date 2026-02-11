from fastapi import APIRouter, Depends, Query, HTTPException
from sqlalchemy.ext.asyncio import AsyncSession
from typing import Optional, List

from app.database import get_session
from app.services.library_service import LibraryService
from app.schemas.media import MediaItemResponse, LibraryStatsResponse, LibrarySectionResponse

router = APIRouter()


@router.get("/items")
async def get_library_items(
    page: int = Query(1, ge=1),
    page_size: int = Query(50, ge=1, le=500),
    search: Optional[str] = None,
    library_id: Optional[int] = None,
    resolution: Optional[str] = None,
    video_codec: Optional[str] = None,
    audio_codec: Optional[str] = None,
    hdr_only: bool = False,
    min_bitrate: Optional[int] = None,
    max_bitrate: Optional[int] = None,
    min_size: Optional[int] = None,
    max_size: Optional[int] = None,
    sort_by: str = "title",
    sort_order: str = "asc",
    session: AsyncSession = Depends(get_session),
):
    service = LibraryService(session)
    result = await service.get_items(
        page=page,
        page_size=page_size,
        search=search,
        library_id=library_id,
        resolution=resolution,
        video_codec=video_codec,
        audio_codec=audio_codec,
        hdr_only=hdr_only,
        min_bitrate=min_bitrate,
        max_bitrate=max_bitrate,
        min_size=min_size,
        max_size=max_size,
        sort_by=sort_by,
        sort_order=sort_order,
    )
    return result


@router.get("/items/{item_id}", response_model=MediaItemResponse)
async def get_library_item(item_id: int, session: AsyncSession = Depends(get_session)):
    service = LibraryService(session)
    item = await service.get_item(item_id)
    if not item:
        raise HTTPException(status_code=404, detail="Media item not found")
    return item


@router.get("/sections", response_model=List[LibrarySectionResponse])
async def get_library_sections(session: AsyncSession = Depends(get_session)):
    service = LibraryService(session)
    return await service.get_sections()


@router.get("/stats", response_model=LibraryStatsResponse)
async def get_library_stats(session: AsyncSession = Depends(get_session)):
    service = LibraryService(session)
    return await service.get_stats()


@router.post("/export")
async def export_library(
    format: str = Query("csv", pattern="^(csv|json)$"),
    library_id: Optional[int] = None,
    session: AsyncSession = Depends(get_session),
):
    service = LibraryService(session)
    return await service.export_library(format=format, library_id=library_id)
