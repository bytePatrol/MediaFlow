import logging

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, func
from typing import List

logger = logging.getLogger(__name__)

from app.database import get_session
from app.models.plex_server import PlexServer
from app.models.plex_library import PlexLibrary
from app.schemas.plex import (
    PlexConnectRequest, PlexServerResponse, PlexLibraryResponse, PlexSyncResponse,
    PlexPinCreateResponse, PlexAuthStatusResponse, PlexOAuthServersResponse,
    PlexServerSSHUpdate,
)
from app.services.plex_service import PlexService
from app.config import settings

router = APIRouter()


@router.post("/connect", response_model=PlexServerResponse)
async def connect_plex_server(
    request: PlexConnectRequest,
    session: AsyncSession = Depends(get_session),
):
    service = PlexService(session)
    server_info = await service.validate_connection(request.url, request.token)
    if not server_info:
        raise HTTPException(status_code=400, detail="Failed to connect to Plex server")

    server = await service.save_server(
        name=request.name or server_info.get("friendlyName", "Plex Server"),
        url=request.url,
        token=request.token,
        machine_id=server_info.get("machineIdentifier"),
        version=server_info.get("version"),
    )
    result = await session.execute(
        select(func.count()).select_from(PlexLibrary).where(PlexLibrary.plex_server_id == server.id)
    )
    lib_count = result.scalar() or 0
    resp = PlexServerResponse.model_validate(server)
    resp.library_count = lib_count
    return resp


@router.get("/servers", response_model=List[PlexServerResponse])
async def list_plex_servers(session: AsyncSession = Depends(get_session)):
    result = await session.execute(select(PlexServer).order_by(PlexServer.created_at.desc()))
    servers = result.scalars().all()
    responses = []
    for s in servers:
        lib_result = await session.execute(
            select(func.count()).select_from(PlexLibrary).where(PlexLibrary.plex_server_id == s.id)
        )
        resp = PlexServerResponse.model_validate(s)
        resp.library_count = lib_result.scalar() or 0
        responses.append(resp)
    return responses


@router.delete("/servers/{server_id}")
async def delete_plex_server(server_id: int, session: AsyncSession = Depends(get_session)):
    result = await session.execute(select(PlexServer).where(PlexServer.id == server_id))
    server = result.scalar_one_or_none()
    if not server:
        raise HTTPException(status_code=404, detail="Server not found")
    await session.delete(server)
    await session.commit()
    return {"status": "deleted", "message": f"Server '{server.name}' removed"}


@router.get("/servers/{server_id}/libraries", response_model=List[PlexLibraryResponse])
async def get_server_libraries(server_id: int, session: AsyncSession = Depends(get_session)):
    result = await session.execute(
        select(PlexLibrary).where(PlexLibrary.plex_server_id == server_id)
    )
    return result.scalars().all()


@router.post("/servers/{server_id}/sync", response_model=PlexSyncResponse)
async def sync_plex_library(server_id: int, session: AsyncSession = Depends(get_session)):
    result = await session.execute(select(PlexServer).where(PlexServer.id == server_id))
    server = result.scalar_one_or_none()
    if not server:
        raise HTTPException(status_code=404, detail="Server not found")

    service = PlexService(session)
    sync_result = await service.sync_library(server)

    # Auto-run intelligence analysis after manual sync
    import asyncio
    asyncio.create_task(_auto_analyze_after_sync_bg())

    return sync_result


@router.put("/servers/{server_id}/ssh", response_model=PlexServerResponse)
async def update_server_ssh(
    server_id: int,
    request: PlexServerSSHUpdate,
    session: AsyncSession = Depends(get_session),
):
    result = await session.execute(select(PlexServer).where(PlexServer.id == server_id))
    server = result.scalar_one_or_none()
    if not server:
        raise HTTPException(status_code=404, detail="Server not found")

    server.ssh_hostname = request.ssh_hostname
    server.ssh_port = request.ssh_port
    server.ssh_username = request.ssh_username
    server.ssh_key_path = request.ssh_key_path
    server.ssh_password = request.ssh_password
    server.benchmark_path = request.benchmark_path
    await session.commit()
    await session.refresh(server)

    lib_result = await session.execute(
        select(func.count()).select_from(PlexLibrary).where(PlexLibrary.plex_server_id == server.id)
    )
    resp = PlexServerResponse.model_validate(server)
    resp.library_count = lib_result.scalar() or 0
    return resp


@router.post("/servers/{server_id}/test-ssh")
async def test_server_ssh(server_id: int, session: AsyncSession = Depends(get_session)):
    result = await session.execute(select(PlexServer).where(PlexServer.id == server_id))
    server = result.scalar_one_or_none()
    if not server:
        raise HTTPException(status_code=404, detail="Server not found")
    if not server.ssh_hostname:
        raise HTTPException(status_code=400, detail="SSH hostname not configured")

    from app.utils.ssh import SSHClient
    ssh = SSHClient(server.ssh_hostname, server.ssh_port or 22,
                    server.ssh_username, server.ssh_key_path, server.ssh_password)
    success = await ssh.test_connection()
    return {"status": "ok" if success else "failed", "message": "SSH connection successful" if success else "SSH connection failed"}


# --- OAuth / PIN-based auth ---


@router.post("/auth/pin", response_model=PlexPinCreateResponse)
async def create_auth_pin():
    try:
        pin_data = await PlexService.create_pin(
            settings.PLEX_CLIENT_IDENTIFIER, settings.PLEX_PRODUCT_NAME
        )
        auth_url = (
            f"https://app.plex.tv/auth#?clientID={settings.PLEX_CLIENT_IDENTIFIER}"
            f"&code={pin_data['code']}&context%5Bdevice%5D%5Bproduct%5D={settings.PLEX_PRODUCT_NAME}"
        )
        return PlexPinCreateResponse(pin_id=pin_data["id"], auth_url=auth_url)
    except Exception as e:
        raise HTTPException(status_code=502, detail=f"Failed to create Plex PIN: {e}")


@router.get("/auth/pin/{pin_id}/status", response_model=PlexAuthStatusResponse)
async def check_auth_pin_status(pin_id: int, session: AsyncSession = Depends(get_session)):
    try:
        result = await PlexService.check_pin(
            pin_id, settings.PLEX_CLIENT_IDENTIFIER, settings.PLEX_PRODUCT_NAME
        )
    except Exception as e:
        return PlexAuthStatusResponse(status="error", error_message=str(e))

    if result["expired"]:
        return PlexAuthStatusResponse(status="expired")

    if not result["auth_token"]:
        return PlexAuthStatusResponse(status="pending")

    # Authenticated — discover and save servers (sync happens separately)
    auth_token = result["auth_token"]
    try:
        discovered = await PlexService.discover_servers(
            auth_token, settings.PLEX_CLIENT_IDENTIFIER, settings.PLEX_PRODUCT_NAME
        )
        service = PlexService(session)
        saved = await service.save_discovered_servers(discovered)

        # Kick off library sync in the background so the auth response returns immediately
        import asyncio
        for server in saved:
            asyncio.create_task(_background_sync(server.id))

        return PlexAuthStatusResponse(
            status="authenticated",
            auth_token=auth_token,
            servers_discovered=len(saved),
        )
    except Exception as e:
        return PlexAuthStatusResponse(
            status="error",
            auth_token=auth_token,
            error_message=f"Authenticated but failed to discover servers: {e}",
        )


async def _background_sync(server_id: int):
    """Run library sync in the background outside the request lifecycle."""
    from app.database import async_session_factory
    try:
        async with async_session_factory() as session:
            result = await session.execute(select(PlexServer).where(PlexServer.id == server_id))
            server = result.scalar_one_or_none()
            if server:
                service = PlexService(session)
                await service.sync_library(server)
                logger.info(f"Background sync completed for {server.name}")

                # Count synced items
                from sqlalchemy import func as sql_func
                from app.models.media_item import MediaItem
                count_result = await session.execute(
                    select(sql_func.count()).select_from(MediaItem)
                )
                item_count = count_result.scalar() or 0

                from app.utils.notify import fire_notification
                await fire_notification("sync.completed", {
                    "server_name": server.name,
                    "items_synced": item_count,
                })

                # Auto-run intelligence analysis if enabled
                await _auto_analyze_after_sync(session)
    except Exception as e:
        logger.warning(f"Background sync failed for server {server_id}: {e}")


async def _auto_analyze_after_sync(session):
    """Run intelligence analysis automatically after sync if setting is enabled."""
    try:
        from app.models.app_settings import AppSetting
        result = await session.execute(
            select(AppSetting).where(AppSetting.key == "intel.auto_analyze_on_sync")
        )
        setting = result.scalar_one_or_none()
        # Default to true if setting doesn't exist
        if setting and setting.value == "false":
            return

        from app.services.recommendation_service import RecommendationService
        rec_service = RecommendationService(session)
        run_result = await rec_service.run_full_analysis(trigger="auto")
        logger.info(
            f"Auto-analysis completed: {run_result['recommendations_generated']} recommendations generated"
        )
    except Exception as e:
        logger.warning(f"Auto-analysis after sync failed: {e}")


async def _auto_analyze_after_sync_bg():
    """Run auto-analysis in a background task with its own session."""
    from app.database import async_session_factory
    try:
        async with async_session_factory() as session:
            await _auto_analyze_after_sync(session)
    except Exception as e:
        logger.warning(f"Background auto-analysis failed: {e}")


@router.post("/auth/discover", response_model=PlexOAuthServersResponse)
async def discover_servers_with_token(
    token: str,
    session: AsyncSession = Depends(get_session),
):
    try:
        discovered = await PlexService.discover_servers(
            token, settings.PLEX_CLIENT_IDENTIFIER, settings.PLEX_PRODUCT_NAME
        )
        service = PlexService(session)
        saved = await service.save_discovered_servers(discovered)

        responses = []
        for s in saved:
            lib_result = await session.execute(
                select(func.count()).select_from(PlexLibrary).where(PlexLibrary.plex_server_id == s.id)
            )
            resp = PlexServerResponse.model_validate(s)
            resp.library_count = lib_result.scalar() or 0
            responses.append(resp)

        return PlexOAuthServersResponse(status="success", servers=responses)
    except Exception as e:
        raise HTTPException(status_code=502, detail=f"Server discovery failed: {e}")
