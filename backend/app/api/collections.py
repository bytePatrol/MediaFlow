from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy.ext.asyncio import AsyncSession
from typing import List

from app.database import get_session
from app.schemas.collection import (
    CollectionInfo,
    CollectionCreateRequest,
    CollectionAddRequest,
    CollectionCreateResponse,
)
from app.services.collection_service import CollectionService

router = APIRouter()


@router.get("/", response_model=List[CollectionInfo])
async def list_collections(
    server_id: int = Query(..., description="Plex server ID"),
    session: AsyncSession = Depends(get_session),
):
    service = CollectionService(session)
    try:
        return await service.list_collections(server_id)
    except ValueError as e:
        raise HTTPException(status_code=404, detail=str(e))


@router.post("/", response_model=CollectionCreateResponse)
async def create_collection(
    data: CollectionCreateRequest, session: AsyncSession = Depends(get_session)
):
    service = CollectionService(session)
    try:
        return await service.create_collection(
            data.server_id, data.library_id, data.title, data.media_item_ids
        )
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Failed to create collection: {e}")


@router.post("/{collection_id}/add", response_model=CollectionCreateResponse)
async def add_to_collection(
    collection_id: str,
    data: CollectionAddRequest,
    session: AsyncSession = Depends(get_session),
):
    service = CollectionService(session)
    try:
        return await service.add_to_collection(
            data.server_id, collection_id, data.media_item_ids
        )
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Failed to add to collection: {e}")
