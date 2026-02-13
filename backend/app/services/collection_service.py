import logging
from typing import List, Dict, Any, Optional

import httpx
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select

from app.models.plex_server import PlexServer
from app.models.plex_library import PlexLibrary
from app.models.media_item import MediaItem

logger = logging.getLogger(__name__)

PLEX_HEADERS = {"Accept": "application/json"}


class CollectionService:
    def __init__(self, session: AsyncSession):
        self.session = session

    async def _get_server(self, server_id: int) -> PlexServer:
        result = await self.session.execute(
            select(PlexServer).where(PlexServer.id == server_id)
        )
        server = result.scalar_one_or_none()
        if not server:
            raise ValueError(f"Plex server {server_id} not found")
        return server

    async def list_collections(self, server_id: int) -> List[Dict[str, Any]]:
        server = await self._get_server(server_id)
        collections = []

        result = await self.session.execute(
            select(PlexLibrary).where(PlexLibrary.plex_server_id == server_id)
        )
        libraries = result.scalars().all()

        async with httpx.AsyncClient(timeout=15.0, verify=False) as client:
            for lib in libraries:
                try:
                    resp = await client.get(
                        f"{server.url.rstrip('/')}/library/sections/{lib.plex_key}/collections",
                        headers={**PLEX_HEADERS, "X-Plex-Token": server.token},
                    )
                    resp.raise_for_status()
                    data = resp.json()
                    metadata = data.get("MediaContainer", {}).get("Metadata", [])
                    for item in metadata:
                        thumb = item.get("thumb")
                        thumb_url = f"{server.url.rstrip('/')}{thumb}" if thumb else None
                        collections.append({
                            "id": str(item.get("ratingKey", "")),
                            "title": item.get("title", ""),
                            "section_key": lib.plex_key,
                            "section_title": lib.title,
                            "item_count": item.get("childCount", 0),
                            "thumb_url": thumb_url,
                        })
                except Exception as e:
                    logger.warning(f"Failed to fetch collections for library {lib.title}: {e}")

        return collections

    async def create_collection(
        self, server_id: int, library_id: int, title: str, media_item_ids: List[int]
    ) -> Dict[str, Any]:
        server = await self._get_server(server_id)

        # Resolve library plex_key
        lib_result = await self.session.execute(
            select(PlexLibrary).where(PlexLibrary.id == library_id)
        )
        library = lib_result.scalar_one_or_none()
        if not library:
            raise ValueError(f"Library {library_id} not found")

        # Map local media item IDs to Plex rating keys
        rating_keys = await self._resolve_rating_keys(media_item_ids)
        if not rating_keys:
            raise ValueError("No valid media items found for the given IDs")

        # Create collection via Plex API
        machine_id = server.machine_id or ""
        items_uri = ",".join(
            f"server://{machine_id}/com.plexapp.plugins.library/library/metadata/{rk}"
            for rk in rating_keys
        )

        async with httpx.AsyncClient(timeout=15.0, verify=False) as client:
            resp = await client.post(
                f"{server.url.rstrip('/')}/library/collections",
                headers={**PLEX_HEADERS, "X-Plex-Token": server.token},
                params={
                    "type": "1",
                    "title": title,
                    "smart": "0",
                    "sectionId": library.plex_key,
                    "uri": items_uri,
                },
            )
            resp.raise_for_status()
            data = resp.json()
            metadata = data.get("MediaContainer", {}).get("Metadata", [])
            collection_id = str(metadata[0]["ratingKey"]) if metadata else None

        return {
            "status": "created",
            "collection_id": collection_id,
            "title": title,
            "items_added": len(rating_keys),
        }

    async def add_to_collection(
        self, server_id: int, collection_id: str, media_item_ids: List[int]
    ) -> Dict[str, Any]:
        server = await self._get_server(server_id)
        rating_keys = await self._resolve_rating_keys(media_item_ids)
        if not rating_keys:
            raise ValueError("No valid media items found for the given IDs")

        machine_id = server.machine_id or ""
        items_uri = ",".join(
            f"server://{machine_id}/com.plexapp.plugins.library/library/metadata/{rk}"
            for rk in rating_keys
        )

        async with httpx.AsyncClient(timeout=15.0, verify=False) as client:
            resp = await client.put(
                f"{server.url.rstrip('/')}/library/collections/{collection_id}/items",
                headers={**PLEX_HEADERS, "X-Plex-Token": server.token},
                params={"uri": items_uri},
            )
            resp.raise_for_status()

        return {
            "status": "added",
            "collection_id": collection_id,
            "title": "",
            "items_added": len(rating_keys),
        }

    async def _resolve_rating_keys(self, media_item_ids: List[int]) -> List[str]:
        result = await self.session.execute(
            select(MediaItem.plex_rating_key).where(MediaItem.id.in_(media_item_ids))
        )
        return [row[0] for row in result.all() if row[0]]
