import json
import logging
from typing import Optional, List, Dict, Any

from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, func, desc, asc, or_
from sqlalchemy.orm import joinedload

from app.models.media_item import MediaItem
from app.models.custom_tag import MediaTag, CustomTag
from app.models.plex_library import PlexLibrary
from app.models.plex_server import PlexServer
from app.schemas.media import MediaItemResponse, LibraryStatsResponse, LibrarySectionResponse
from app.schemas.tag import TagBrief

logger = logging.getLogger(__name__)


class LibraryService:
    def __init__(self, session: AsyncSession):
        self.session = session

    def _build_filter_query(self, query, search: Optional[str] = None,
                            library_id: Optional[int] = None,
                            resolution: Optional[str] = None,
                            video_codec: Optional[str] = None,
                            audio_codec: Optional[str] = None,
                            hdr_only: bool = False,
                            min_bitrate: Optional[int] = None,
                            max_bitrate: Optional[int] = None,
                            min_size: Optional[int] = None,
                            max_size: Optional[int] = None,
                            tags: Optional[str] = None):
        if search:
            query = query.where(
                or_(
                    MediaItem.title.ilike(f"%{search}%"),
                    MediaItem.file_path.ilike(f"%{search}%"),
                )
            )
        if library_id:
            query = query.where(MediaItem.plex_library_id == library_id)
        if resolution:
            resolutions = [r.strip() for r in resolution.split(",")]
            query = query.where(MediaItem.resolution_tier.in_(resolutions))
        if video_codec:
            codecs = [c.strip() for c in video_codec.split(",")]
            query = query.where(MediaItem.video_codec.in_(codecs))
        if audio_codec:
            codecs = [c.strip() for c in audio_codec.split(",")]
            query = query.where(MediaItem.audio_codec.in_(codecs))
        if hdr_only:
            query = query.where(MediaItem.is_hdr == True)
        if min_bitrate is not None:
            query = query.where(MediaItem.video_bitrate >= min_bitrate)
        if max_bitrate is not None:
            query = query.where(MediaItem.video_bitrate <= max_bitrate)
        if min_size is not None:
            query = query.where(MediaItem.file_size >= min_size)
        if max_size is not None:
            query = query.where(MediaItem.file_size <= max_size)
        if tags:
            tag_ids = [int(t.strip()) for t in tags.split(",") if t.strip()]
            if tag_ids:
                query = query.where(
                    MediaItem.id.in_(
                        select(MediaTag.media_item_id)
                        .where(MediaTag.tag_id.in_(tag_ids))
                        .group_by(MediaTag.media_item_id)
                        .having(func.count(func.distinct(MediaTag.tag_id)) == len(tag_ids))
                    )
                )
        return query

    async def get_items(self, page: int = 1, page_size: int = 50,
                        search: Optional[str] = None, library_id: Optional[int] = None,
                        resolution: Optional[str] = None, video_codec: Optional[str] = None,
                        audio_codec: Optional[str] = None, hdr_only: bool = False,
                        min_bitrate: Optional[int] = None, max_bitrate: Optional[int] = None,
                        min_size: Optional[int] = None, max_size: Optional[int] = None,
                        tags: Optional[str] = None,
                        sort_by: str = "title", sort_order: str = "asc") -> Dict[str, Any]:
        query = self._build_filter_query(
            select(MediaItem),
            search=search, library_id=library_id, resolution=resolution,
            video_codec=video_codec, audio_codec=audio_codec, hdr_only=hdr_only,
            min_bitrate=min_bitrate, max_bitrate=max_bitrate,
            min_size=min_size, max_size=max_size, tags=tags,
        )

        count_query = select(func.count()).select_from(query.subquery())
        total_result = await self.session.execute(count_query)
        total = total_result.scalar() or 0

        sort_column = getattr(MediaItem, sort_by, MediaItem.title)
        if sort_order == "desc":
            query = query.order_by(desc(sort_column))
        else:
            query = query.order_by(asc(sort_column))

        offset = (page - 1) * page_size
        query = query.options(joinedload(MediaItem.tags).joinedload(MediaTag.tag))
        query = query.offset(offset).limit(page_size)

        result = await self.session.execute(query)
        items = result.unique().scalars().all()

        item_responses = []
        for item in items:
            resp = MediaItemResponse.model_validate(item)
            lib_result = await self.session.execute(
                select(PlexLibrary.title).where(PlexLibrary.id == item.plex_library_id)
            )
            lib_title = lib_result.scalar_one_or_none()
            resp.library_title = lib_title
            resp.tags = [
                TagBrief(id=mt.tag.id, name=mt.tag.name, color=mt.tag.color)
                for mt in item.tags if mt.tag
            ]
            item_responses.append(resp)

        total_pages = (total + page_size - 1) // page_size

        return {
            "items": [r.model_dump() for r in item_responses],
            "total": total,
            "page": page,
            "page_size": page_size,
            "total_pages": total_pages,
        }

    async def get_item_ids(self, search: Optional[str] = None,
                           library_id: Optional[int] = None,
                           resolution: Optional[str] = None,
                           video_codec: Optional[str] = None,
                           audio_codec: Optional[str] = None,
                           hdr_only: bool = False,
                           min_bitrate: Optional[int] = None,
                           max_bitrate: Optional[int] = None,
                           min_size: Optional[int] = None,
                           max_size: Optional[int] = None,
                           tags: Optional[str] = None) -> Dict[str, Any]:
        query = self._build_filter_query(
            select(MediaItem.id),
            search=search, library_id=library_id, resolution=resolution,
            video_codec=video_codec, audio_codec=audio_codec, hdr_only=hdr_only,
            min_bitrate=min_bitrate, max_bitrate=max_bitrate,
            min_size=min_size, max_size=max_size, tags=tags,
        )
        result = await self.session.execute(query)
        ids = [row[0] for row in result.all()]

        size_query = self._build_filter_query(
            select(func.sum(MediaItem.file_size)),
            search=search, library_id=library_id, resolution=resolution,
            video_codec=video_codec, audio_codec=audio_codec, hdr_only=hdr_only,
            min_bitrate=min_bitrate, max_bitrate=max_bitrate,
            min_size=min_size, max_size=max_size, tags=tags,
        )
        size_result = await self.session.execute(size_query)
        total_size = size_result.scalar() or 0

        return {"ids": ids, "total": len(ids), "total_size": total_size}

    async def get_item(self, item_id: int) -> Optional[MediaItemResponse]:
        result = await self.session.execute(
            select(MediaItem).where(MediaItem.id == item_id)
        )
        item = result.scalar_one_or_none()
        if not item:
            return None
        resp = MediaItemResponse.model_validate(item)
        lib_result = await self.session.execute(
            select(PlexLibrary.title).where(PlexLibrary.id == item.plex_library_id)
        )
        resp.library_title = lib_result.scalar_one_or_none()
        return resp

    async def get_sections(self) -> List[Dict[str, Any]]:
        result = await self.session.execute(
            select(PlexLibrary, PlexServer.name)
            .join(PlexServer, PlexLibrary.plex_server_id == PlexServer.id)
            .order_by(PlexLibrary.title)
        )
        sections = []
        for lib, server_name in result.all():
            sections.append({
                "id": lib.id,
                "title": lib.title,
                "type": lib.type,
                "total_items": lib.total_items or 0,
                "total_size": lib.total_size or 0,
                "server_name": server_name,
                "server_id": lib.plex_server_id,
            })
        return sections

    async def get_stats(self) -> LibraryStatsResponse:
        total_result = await self.session.execute(select(func.count()).select_from(MediaItem))
        total_items = total_result.scalar() or 0

        size_result = await self.session.execute(select(func.sum(MediaItem.file_size)))
        total_size = size_result.scalar() or 0

        duration_result = await self.session.execute(select(func.sum(MediaItem.duration_ms)))
        total_duration = duration_result.scalar() or 0

        codec_result = await self.session.execute(
            select(MediaItem.video_codec, func.count())
            .group_by(MediaItem.video_codec)
        )
        codec_breakdown = {codec or "unknown": count for codec, count in codec_result.all()}

        res_result = await self.session.execute(
            select(MediaItem.resolution_tier, func.count())
            .group_by(MediaItem.resolution_tier)
        )
        resolution_breakdown = {res or "unknown": count for res, count in res_result.all()}

        hdr_result = await self.session.execute(
            select(func.count()).select_from(MediaItem).where(MediaItem.is_hdr == True)
        )
        hdr_count = hdr_result.scalar() or 0

        avg_result = await self.session.execute(select(func.avg(MediaItem.video_bitrate)))
        avg_bitrate = avg_result.scalar() or 0

        lib_result = await self.session.execute(
            select(PlexLibrary.id, PlexLibrary.title, PlexLibrary.type,
                   PlexLibrary.total_items, PlexLibrary.total_size)
        )
        libraries = [
            {"id": r[0], "title": r[1], "type": r[2], "total_items": r[3] or 0, "total_size": r[4] or 0}
            for r in lib_result.all()
        ]

        return LibraryStatsResponse(
            total_items=total_items,
            total_size=total_size,
            total_duration_ms=total_duration,
            codec_breakdown=codec_breakdown,
            resolution_breakdown=resolution_breakdown,
            hdr_count=hdr_count,
            avg_bitrate=float(avg_bitrate),
            libraries=libraries,
        )

    async def export_library(self, format: str = "csv", library_id: Optional[int] = None) -> dict:
        query = select(MediaItem)
        if library_id:
            query = query.where(MediaItem.plex_library_id == library_id)
        result = await self.session.execute(query)
        items = result.scalars().all()

        if format == "json":
            data = [MediaItemResponse.model_validate(i).model_dump() for i in items]
            return {"format": "json", "count": len(data), "data": data}
        else:
            lines = ["title,year,resolution,codec,bitrate,file_size,audio,file_path"]
            for item in items:
                lines.append(
                    f'"{item.title}",{item.year or ""},'
                    f'{item.resolution_tier or ""},{item.video_codec or ""},'
                    f'{item.video_bitrate or ""},{item.file_size or ""},'
                    f'{item.audio_codec or ""},"{item.file_path or ""}"'
                )
            return {"format": "csv", "count": len(items), "data": "\n".join(lines)}
