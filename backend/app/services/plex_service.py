import logging
import time
from typing import Optional, Dict, Any, List

import httpx
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select

from app.models.plex_server import PlexServer
from app.models.plex_library import PlexLibrary
from app.models.media_item import MediaItem
from app.config import settings

logger = logging.getLogger(__name__)

PLEX_HEADERS = {"Accept": "application/json"}
PLEX_TV_BASE = "https://plex.tv/api/v2"


class PlexService:
    def __init__(self, session: AsyncSession):
        self.session = session

    async def validate_connection(self, url: str, token: str) -> Optional[Dict[str, Any]]:
        try:
            async with httpx.AsyncClient(timeout=10.0, verify=False) as client:
                resp = await client.get(
                    f"{url.rstrip('/')}/",
                    headers={**PLEX_HEADERS, "X-Plex-Token": token},
                )
                resp.raise_for_status()
                data = resp.json()
                container = data.get("MediaContainer", {})
                return {
                    "friendlyName": container.get("friendlyName", "Plex Server"),
                    "machineIdentifier": container.get("machineIdentifier"),
                    "version": container.get("version"),
                }
        except Exception as e:
            logger.error(f"Plex connection failed: {e}")
            return None

    async def get_libraries(self, url: str, token: str) -> List[Dict[str, Any]]:
        try:
            async with httpx.AsyncClient(timeout=10.0, verify=False) as client:
                resp = await client.get(
                    f"{url.rstrip('/')}/library/sections",
                    headers={**PLEX_HEADERS, "X-Plex-Token": token},
                )
                resp.raise_for_status()
                data = resp.json()
                directories = data.get("MediaContainer", {}).get("Directory", [])
                return [
                    {
                        "key": d["key"],
                        "title": d["title"],
                        "type": d["type"],
                    }
                    for d in directories
                ]
        except Exception as e:
            logger.error(f"Failed to fetch libraries: {e}")
            return []

    async def get_library_items(
        self, url: str, token: str, section_key: str, lib_type: str = "movie"
    ) -> List[Dict[str, Any]]:
        items = []
        try:
            async with httpx.AsyncClient(timeout=120.0, verify=False) as client:
                if lib_type == "show":
                    items = await self._get_show_episodes(client, url, token, section_key)
                else:
                    resp = await client.get(
                        f"{url.rstrip('/')}/library/sections/{section_key}/all",
                        headers={**PLEX_HEADERS, "X-Plex-Token": token},
                        params={"includeGuids": "1", "includeMedia": "1"},
                    )
                    resp.raise_for_status()
                    data = resp.json()
                    metadata_list = data.get("MediaContainer", {}).get("Metadata", [])

                    for meta in metadata_list:
                        item = self._parse_plex_metadata(meta, url)
                        items.append(item)

                # Enrich items that are missing stream details
                missing = [i for i in items if not i.get("file_size") or not i.get("video_codec")]
                if missing:
                    logger.info(f"Enriching {len(missing)} items missing media details...")
                    for item in missing:
                        try:
                            detail = await self._fetch_item_metadata(
                                client, url, token, item["plex_rating_key"]
                            )
                            if detail:
                                for key, value in detail.items():
                                    if value is not None:
                                        item[key] = value
                        except Exception as e:
                            logger.debug(f"Failed to enrich {item.get('title')}: {e}")
        except Exception as e:
            logger.error(f"Failed to fetch library items: {e}")
        return items

    async def _get_show_episodes(
        self, client: httpx.AsyncClient, url: str, token: str, section_key: str
    ) -> List[Dict[str, Any]]:
        """Fetch all episodes for a TV show library by drilling into shows -> episodes."""
        items = []
        # Get all episodes directly via the allLeaves endpoint
        resp = await client.get(
            f"{url.rstrip('/')}/library/sections/{section_key}/all",
            headers={**PLEX_HEADERS, "X-Plex-Token": token},
            params={"type": "4", "includeGuids": "1", "includeMedia": "1"},
        )
        resp.raise_for_status()
        data = resp.json()
        metadata_list = data.get("MediaContainer", {}).get("Metadata", [])

        for meta in metadata_list:
            item = self._parse_plex_metadata(meta, url)
            # Prefix episode title with show name for clarity
            show_title = meta.get("grandparentTitle", "")
            season_num = meta.get("parentIndex")
            ep_num = meta.get("index")
            if show_title:
                ep_label = ""
                if season_num is not None and ep_num is not None:
                    ep_label = f" S{season_num:02d}E{ep_num:02d}"
                item["title"] = f"{show_title}{ep_label} - {item['title']}"
            items.append(item)

        logger.info(f"Fetched {len(items)} episodes from show library section {section_key}")
        return items

    async def _fetch_item_metadata(
        self, client: httpx.AsyncClient, url: str, token: str, rating_key: str
    ) -> Optional[Dict[str, Any]]:
        resp = await client.get(
            f"{url.rstrip('/')}/library/metadata/{rating_key}",
            headers={**PLEX_HEADERS, "X-Plex-Token": token},
        )
        resp.raise_for_status()
        data = resp.json()
        metadata_list = data.get("MediaContainer", {}).get("Metadata", [])
        if not metadata_list:
            return None
        return self._parse_plex_metadata(metadata_list[0], url)

    def _parse_plex_metadata(self, meta: dict, base_url: str) -> Dict[str, Any]:
        item = {
            "plex_rating_key": str(meta.get("ratingKey", "")),
            "title": meta.get("title", "Unknown"),
            "year": meta.get("year"),
            "duration_ms": meta.get("duration"),
            "thumb_url": f"{base_url.rstrip('/')}{meta['thumb']}" if meta.get("thumb") else None,
            "play_count": meta.get("viewCount", 0),
            "genres": [g.get("tag") for g in meta.get("Genre", [])],
            "directors": [d.get("tag") for d in meta.get("Director", [])],
        }

        media_list = meta.get("Media", [])
        if media_list:
            media = media_list[0]
            item.update({
                "container": media.get("container"),
                "video_codec": media.get("videoCodec"),
                "video_profile": media.get("videoProfile"),
                "video_bitrate": media.get("bitrate"),
                "width": media.get("width"),
                "height": media.get("height"),
                "frame_rate": self._parse_frame_rate(media.get("videoFrameRate")),
                "audio_codec": media.get("audioCodec"),
                "audio_channels": media.get("audioChannels"),
                "audio_channel_layout": media.get("audioChannelLayout"),
            })

            height = media.get("height", 0)
            item["resolution_tier"] = self._classify_resolution(height)
            item["is_hdr"] = "HDR" in str(media.get("videoProfile", ""))
            item["bit_depth"] = media.get("bitDepth")

            parts = media.get("Part", [])
            if parts:
                part = parts[0]
                item["file_path"] = part.get("file")
                item["file_size"] = part.get("size")

                audio_tracks = []
                subtitle_tracks = []
                for stream in part.get("Stream", []):
                    stream_type = stream.get("streamType")
                    if stream_type == 2:
                        audio_tracks.append({
                            "codec": stream.get("codec"),
                            "channels": stream.get("channels"),
                            "language": stream.get("language"),
                            "title": stream.get("title"),
                            "bitrate": stream.get("bitrate"),
                        })
                        if not item.get("audio_bitrate") and stream.get("bitrate"):
                            item["audio_bitrate"] = stream["bitrate"]
                    elif stream_type == 3:
                        subtitle_tracks.append({
                            "codec": stream.get("codec"),
                            "language": stream.get("language"),
                            "title": stream.get("title"),
                            "forced": stream.get("forced", False),
                        })
                item["audio_tracks_json"] = audio_tracks if audio_tracks else None
                item["subtitle_tracks_json"] = subtitle_tracks if subtitle_tracks else None

            if media.get("videoProfile") and "HDR" in media["videoProfile"]:
                item["hdr_format"] = media["videoProfile"]

        return item

    def _classify_resolution(self, height: int) -> str:
        if height >= 2160:
            return "4K"
        elif height >= 1080:
            return "1080p"
        elif height >= 720:
            return "720p"
        elif height >= 480:
            return "480p"
        else:
            return "SD"

    def _parse_frame_rate(self, fr_str: Optional[str]) -> Optional[float]:
        if not fr_str:
            return None
        fr_map = {"24p": 23.976, "NTSC": 29.97, "PAL": 25.0}
        return fr_map.get(fr_str)

    async def save_server(self, name: str, url: str, token: str,
                          machine_id: Optional[str] = None, version: Optional[str] = None) -> PlexServer:
        existing = None
        if machine_id:
            result = await self.session.execute(
                select(PlexServer).where(PlexServer.machine_id == machine_id)
            )
            existing = result.scalar_one_or_none()

        if existing:
            existing.name = name
            existing.url = url
            existing.token = token
            existing.version = version
            existing.is_active = True
            server = existing
        else:
            server = PlexServer(
                name=name, url=url, token=token,
                machine_id=machine_id, version=version,
            )
            self.session.add(server)

        await self.session.commit()
        await self.session.refresh(server)

        libraries = await self.get_libraries(url, token)
        for lib_data in libraries:
            result = await self.session.execute(
                select(PlexLibrary).where(
                    PlexLibrary.plex_server_id == server.id,
                    PlexLibrary.plex_key == lib_data["key"],
                )
            )
            existing_lib = result.scalar_one_or_none()
            if not existing_lib:
                lib = PlexLibrary(
                    plex_server_id=server.id,
                    plex_key=lib_data["key"],
                    title=lib_data["title"],
                    type=lib_data["type"],
                )
                self.session.add(lib)
        await self.session.commit()
        await self.session.refresh(server)
        return server

    async def sync_library(self, server: PlexServer) -> dict:
        start_time = time.time()
        total_items = 0
        total_libs = 0

        libraries = await self.get_libraries(server.url, server.token)

        for lib_data in libraries:
            # Skip non-video library types
            if lib_data.get("type") in ("artist", "photo"):
                continue

            result = await self.session.execute(
                select(PlexLibrary).where(
                    PlexLibrary.plex_server_id == server.id,
                    PlexLibrary.plex_key == lib_data["key"],
                )
            )
            library = result.scalar_one_or_none()
            if not library:
                library = PlexLibrary(
                    plex_server_id=server.id,
                    plex_key=lib_data["key"],
                    title=lib_data["title"],
                    type=lib_data["type"],
                )
                self.session.add(library)
                await self.session.commit()
                await self.session.refresh(library)

            items = await self.get_library_items(
                server.url, server.token, lib_data["key"], lib_type=lib_data.get("type", "movie")
            )

            batch = []
            for item_data in items:
                result = await self.session.execute(
                    select(MediaItem).where(
                        MediaItem.plex_library_id == library.id,
                        MediaItem.plex_rating_key == item_data["plex_rating_key"],
                    )
                )
                existing = result.scalar_one_or_none()

                if existing:
                    for key, value in item_data.items():
                        if value is not None:
                            setattr(existing, key, value)
                else:
                    item_data["plex_library_id"] = library.id
                    batch.append(MediaItem(**item_data))

                if len(batch) >= 500:
                    self.session.add_all(batch)
                    await self.session.commit()
                    total_items += len(batch)
                    batch = []

            if batch:
                self.session.add_all(batch)
                await self.session.commit()
                total_items += len(batch)

            library.total_items = len(items)
            total_size_result = sum(i.get("file_size", 0) or 0 for i in items)
            library.total_size = total_size_result
            total_libs += 1

        from datetime import datetime
        server.last_synced_at = datetime.utcnow()
        await self.session.commit()

        duration = time.time() - start_time
        return {
            "status": "completed",
            "items_synced": total_items,
            "libraries_synced": total_libs,
            "duration_seconds": round(duration, 2),
        }

    @staticmethod
    async def create_pin(client_id: str, product: str) -> Dict[str, Any]:
        async with httpx.AsyncClient(timeout=10.0) as client:
            resp = await client.post(
                f"{PLEX_TV_BASE}/pins",
                headers={**PLEX_HEADERS, "X-Plex-Product": product, "X-Plex-Client-Identifier": client_id},
                data={"strong": "true", "X-Plex-Product": product, "X-Plex-Client-Identifier": client_id},
            )
            resp.raise_for_status()
            data = resp.json()
            return {"id": data["id"], "code": data["code"]}

    @staticmethod
    async def check_pin(pin_id: int, client_id: str, product: str) -> Dict[str, Any]:
        async with httpx.AsyncClient(timeout=10.0) as client:
            resp = await client.get(
                f"{PLEX_TV_BASE}/pins/{pin_id}",
                headers={**PLEX_HEADERS, "X-Plex-Client-Identifier": client_id, "X-Plex-Product": product},
            )
            resp.raise_for_status()
            data = resp.json()
            auth_token = data.get("authToken")
            expired = data.get("expiresAt") and data["expiresAt"] < data.get("createdAt", "")
            return {"auth_token": auth_token, "expired": bool(expired)}

    @staticmethod
    async def discover_servers(auth_token: str, client_id: str, product: str) -> List[Dict[str, Any]]:
        async with httpx.AsyncClient(timeout=15.0) as client:
            resp = await client.get(
                f"{PLEX_TV_BASE}/resources",
                headers={
                    **PLEX_HEADERS,
                    "X-Plex-Token": auth_token,
                    "X-Plex-Client-Identifier": client_id,
                    "X-Plex-Product": product,
                },
                params={"includeHttps": "1", "includeRelay": "1"},
            )
            resp.raise_for_status()
            resources = resp.json()
            servers = []
            for r in resources:
                if r.get("provides") and "server" in r["provides"]:
                    connections = r.get("connections", [])
                    best = PlexService._pick_best_connection(connections)
                    if best:
                        servers.append({
                            "name": r.get("name", "Plex Server"),
                            "machine_id": r.get("clientIdentifier"),
                            "version": r.get("productVersion"),
                            "uri": best,
                            "token": r.get("accessToken", auth_token),
                        })
            return servers

    @staticmethod
    def _pick_best_connection(connections: List[Dict[str, Any]]) -> Optional[str]:
        local_https = []
        local_http = []
        remote = []
        relay = []
        for c in connections:
            uri = c.get("uri", "")
            is_local = c.get("local", False)
            is_relay = c.get("relay", False)
            if is_relay:
                relay.append(uri)
            elif is_local and uri.startswith("https"):
                local_https.append(uri)
            elif is_local:
                local_http.append(uri)
            else:
                remote.append(uri)
        for group in [local_https, local_http, remote, relay]:
            if group:
                return group[0]
        return None

    async def save_discovered_servers(self, discovered: List[Dict[str, Any]]) -> List[PlexServer]:
        saved = []
        for srv in discovered:
            server = await self.save_server(
                name=srv["name"],
                url=srv["uri"],
                token=srv["token"],
                machine_id=srv.get("machine_id"),
                version=srv.get("version"),
            )
            saved.append(server)
        return saved
