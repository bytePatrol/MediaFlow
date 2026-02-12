import logging

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, func, delete

from app.database import get_session
from app.models.custom_tag import CustomTag, MediaTag
from app.schemas.tag import TagResponse, TagCreate, TagUpdate, TagBrief, BulkTagRequest, BulkTagRemoveRequest

logger = logging.getLogger(__name__)

router = APIRouter()


@router.get("/", response_model=list[TagResponse])
async def list_tags(session: AsyncSession = Depends(get_session)):
    result = await session.execute(
        select(
            CustomTag.id,
            CustomTag.name,
            CustomTag.color,
            func.count(MediaTag.id).label("media_count"),
        )
        .outerjoin(MediaTag, MediaTag.tag_id == CustomTag.id)
        .group_by(CustomTag.id)
        .order_by(CustomTag.name)
    )
    rows = result.all()
    return [
        TagResponse(id=r.id, name=r.name, color=r.color, media_count=r.media_count)
        for r in rows
    ]


@router.post("/", response_model=TagResponse)
async def create_tag(body: TagCreate, session: AsyncSession = Depends(get_session)):
    existing = await session.execute(
        select(CustomTag).where(CustomTag.name == body.name)
    )
    if existing.scalar_one_or_none():
        raise HTTPException(status_code=409, detail="Tag name already exists")

    tag = CustomTag(name=body.name, color=body.color)
    session.add(tag)
    await session.commit()
    await session.refresh(tag)
    return TagResponse(id=tag.id, name=tag.name, color=tag.color, media_count=0)


@router.put("/{tag_id}", response_model=TagResponse)
async def update_tag(tag_id: int, body: TagUpdate, session: AsyncSession = Depends(get_session)):
    result = await session.execute(select(CustomTag).where(CustomTag.id == tag_id))
    tag = result.scalar_one_or_none()
    if not tag:
        raise HTTPException(status_code=404, detail="Tag not found")

    if body.name is not None:
        # Check uniqueness
        dup = await session.execute(
            select(CustomTag).where(CustomTag.name == body.name, CustomTag.id != tag_id)
        )
        if dup.scalar_one_or_none():
            raise HTTPException(status_code=409, detail="Tag name already exists")
        tag.name = body.name
    if body.color is not None:
        tag.color = body.color

    await session.commit()
    await session.refresh(tag)

    count_result = await session.execute(
        select(func.count()).select_from(MediaTag).where(MediaTag.tag_id == tag_id)
    )
    media_count = count_result.scalar() or 0

    return TagResponse(id=tag.id, name=tag.name, color=tag.color, media_count=media_count)


@router.delete("/{tag_id}")
async def delete_tag(tag_id: int, session: AsyncSession = Depends(get_session)):
    result = await session.execute(select(CustomTag).where(CustomTag.id == tag_id))
    tag = result.scalar_one_or_none()
    if not tag:
        raise HTTPException(status_code=404, detail="Tag not found")

    await session.delete(tag)
    await session.commit()
    return {"status": "deleted"}


@router.post("/apply")
async def bulk_apply_tags(body: BulkTagRequest, session: AsyncSession = Depends(get_session)):
    # Get existing assignments to avoid duplicates
    existing = await session.execute(
        select(MediaTag.media_item_id, MediaTag.tag_id).where(
            MediaTag.media_item_id.in_(body.media_item_ids),
            MediaTag.tag_id.in_(body.tag_ids),
        )
    )
    existing_pairs = {(r.media_item_id, r.tag_id) for r in existing.all()}

    added = 0
    for media_id in body.media_item_ids:
        for tag_id in body.tag_ids:
            if (media_id, tag_id) not in existing_pairs:
                session.add(MediaTag(media_item_id=media_id, tag_id=tag_id))
                added += 1

    await session.commit()
    return {"status": "applied", "added": added}


@router.post("/remove")
async def bulk_remove_tags(body: BulkTagRemoveRequest, session: AsyncSession = Depends(get_session)):
    result = await session.execute(
        delete(MediaTag).where(
            MediaTag.media_item_id.in_(body.media_item_ids),
            MediaTag.tag_id.in_(body.tag_ids),
        )
    )
    await session.commit()
    return {"status": "removed", "removed": result.rowcount}


@router.get("/items/{item_id}", response_model=list[TagBrief])
async def get_item_tags(item_id: int, session: AsyncSession = Depends(get_session)):
    result = await session.execute(
        select(CustomTag)
        .join(MediaTag, MediaTag.tag_id == CustomTag.id)
        .where(MediaTag.media_item_id == item_id)
        .order_by(CustomTag.name)
    )
    tags = result.scalars().all()
    return [TagBrief(id=t.id, name=t.name, color=t.color) for t in tags]
