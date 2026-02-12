import httpx
import logging

from fastapi import APIRouter, Depends, Query, HTTPException
from fastapi.responses import Response
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select
from sqlalchemy.orm import joinedload
from typing import Optional, List

from app.database import get_session
from app.models.media_item import MediaItem
from app.services.library_service import LibraryService
from app.schemas.media import MediaItemResponse, LibraryStatsResponse, LibrarySectionResponse

logger = logging.getLogger(__name__)

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
    tags: Optional[str] = None,
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
        tags=tags,
        sort_by=sort_by,
        sort_order=sort_order,
    )
    return result


@router.get("/item-ids")
async def get_library_item_ids(
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
    tags: Optional[str] = None,
    session: AsyncSession = Depends(get_session),
):
    service = LibraryService(session)
    return await service.get_item_ids(
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
        tags=tags,
    )


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


@router.get("/thumb/{item_id}")
async def get_thumbnail(item_id: int, session: AsyncSession = Depends(get_session)):
    """Proxy Plex thumbnail with authentication."""
    result = await session.execute(
        select(MediaItem)
        .options(joinedload(MediaItem.library))
        .where(MediaItem.id == item_id)
    )
    item = result.unique().scalar_one_or_none()
    if not item or not item.thumb_url:
        raise HTTPException(status_code=404, detail="Thumbnail not found")

    # Get the Plex token via library → server
    from app.models.plex_server import PlexServer
    server_result = await session.execute(
        select(PlexServer).where(PlexServer.id == item.library.plex_server_id)
    )
    server = server_result.scalar_one_or_none()
    if not server:
        raise HTTPException(status_code=404, detail="Plex server not found")

    separator = "&" if "?" in item.thumb_url else "?"
    plex_url = f"{item.thumb_url}{separator}X-Plex-Token={server.token}"

    try:
        async with httpx.AsyncClient(timeout=10) as client:
            resp = await client.get(plex_url)
            if resp.status_code != 200:
                raise HTTPException(status_code=502, detail="Failed to fetch thumbnail from Plex")
            return Response(
                content=resp.content,
                media_type=resp.headers.get("content-type", "image/jpeg"),
                headers={"Cache-Control": "public, max-age=86400"},
            )
    except httpx.RequestError as e:
        logger.warning(f"Thumbnail fetch failed for item {item_id}: {e}")
        raise HTTPException(status_code=502, detail="Failed to fetch thumbnail")
