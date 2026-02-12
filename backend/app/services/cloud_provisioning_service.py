import asyncio
import logging
import time
from datetime import datetime
from pathlib import Path

import httpx
from sqlalchemy import select

from app.database import async_session_factory
from app.models.worker_server import WorkerServer
from app.models.transcode_job import TranscodeJob
from app.models.media_item import MediaItem
from app.models.plex_library import PlexLibrary
from app.models.plex_server import PlexServer
from app.models.cloud_cost import CloudCostRecord
from app.models.app_settings import AppSetting
from app.api.websocket import manager
from app.services.vultr_client import VultrClient

logger = logging.getLogger(__name__)


async def _get_setting(session, key: str, default=None):
    result = await session.execute(
        select(AppSetting).where(AppSetting.key == key)
    )
    setting = result.scalar_one_or_none()
    if setting and setting.value is not None:
        return setting.value
    return default


async def _set_setting(session, key: str, value):
    result = await session.execute(
        select(AppSetting).where(AppSetting.key == key)
    )
    setting = result.scalar_one_or_none()
    if setting:
        setting.value = value
    else:
        session.add(AppSetting(key=key, value=value))
    await session.commit()


async def _get_vultr_client(session) -> VultrClient:
    api_key = await _get_setting(session, "vultr_api_key")
    if not api_key:
        raise ValueError("Vultr API key not configured. Set it in Settings > Cloud GPU.")
    return VultrClient(api_key)


def _get_ssh_key_path() -> str:
    """Get the local private key path to use for cloud SSH connections."""
    cloud_key = Path.home() / ".mediaflow" / "cloud_key"
    if cloud_key.exists():
        return str(cloud_key)
    for key_name in ["id_ed25519", "id_rsa"]:
        key_path = Path.home() / ".ssh" / key_name
        if key_path.exists():
            return str(key_path)
    return str(Path.home() / ".ssh" / "id_ed25519")


def _get_local_public_key() -> str:
    """Get the public key content matching _get_ssh_key_path()."""
    private_path = Path(_get_ssh_key_path())
    pub_path = private_path.with_suffix(".pub")
    if not pub_path.exists():
        # Try appending .pub to the full name (e.g., cloud_key → cloud_key.pub)
        pub_path = Path(str(private_path) + ".pub")
    if pub_path.exists():
        return pub_path.read_text().strip()
    return ""


async def _ensure_ssh_key(vultr: VultrClient, session) -> str:
    """Ensure a 'mediaflow' SSH key on Vultr matches our local key. Returns Vultr key ID."""
    private_path = _get_ssh_key_path()
    local_pub = _get_local_public_key()

    if not local_pub:
        # No local key — generate one
        cloud_key_dir = Path.home() / ".mediaflow"
        cloud_key_dir.mkdir(exist_ok=True)
        cloud_key_path = cloud_key_dir / "cloud_key"
        if not cloud_key_path.exists():
            proc = await asyncio.create_subprocess_exec(
                "ssh-keygen", "-t", "ed25519", "-f", str(cloud_key_path),
                "-N", "", "-C", "mediaflow-cloud",
                stdout=asyncio.subprocess.PIPE,
                stderr=asyncio.subprocess.PIPE,
            )
            await proc.wait()
        local_pub = cloud_key_path.with_suffix(".pub").read_text().strip()
        private_path = str(cloud_key_path)

    logger.info(f"Cloud SSH: using private key {private_path}")

    # Check existing keys on Vultr
    keys = await vultr.get_ssh_keys()
    for k in keys:
        if k.get("name") == "mediaflow":
            # Verify the key on Vultr matches our local key
            remote_pub = k.get("ssh_key", "").strip()
            if remote_pub == local_pub:
                logger.info(f"Cloud SSH: reusing existing Vultr key {k['id']}")
                await _set_setting(session, "vultr_ssh_key_id", k["id"])
                return k["id"]
            else:
                # Key mismatch — delete the stale one and re-upload
                logger.warning("Cloud SSH: Vultr 'mediaflow' key doesn't match local key, re-uploading")
                try:
                    async with httpx.AsyncClient(timeout=15) as client:
                        resp = await client.delete(
                            f"{vultr.BASE_URL}/ssh-keys/{k['id']}",
                            headers=vultr._headers(),
                        )
                        logger.info(f"Deleted stale Vultr SSH key {k['id']}: {resp.status_code}")
                except Exception as e:
                    logger.error(f"Failed to delete stale SSH key: {e}")
                break

    # Upload our local public key
    key_data = await vultr.create_ssh_key("mediaflow", local_pub)
    key_id = key_data["id"]
    await _set_setting(session, "vultr_ssh_key_id", key_id)
    logger.info(f"Cloud SSH: uploaded new key to Vultr: {key_id}")
    return key_id


async def deploy_cloud_gpu(
    plan: str = "vcg-a16-6c-64g-16vram",
    region: str = "ewr",
    idle_minutes: int = 30,
    auto_teardown: bool = True,
) -> int:
    """Deploy a Vultr GPU instance and register it as a WorkerServer.

    Returns the new WorkerServer ID.
    """
    async with async_session_factory() as session:
        vultr = await _get_vultr_client(session)

        # Fetch real plan info from Vultr API
        all_plans = await vultr.list_gpu_plans()
        plan_info = next((p for p in all_plans if p["plan_id"] == plan), {})
        hourly_rate = plan_info.get("hourly_cost", 0)
        gpu_model = plan_info.get("gpu_model", "GPU")

        # Step 1: Ensure SSH key
        await manager.broadcast("cloud.deploy_progress", {
            "server_id": 0, "step": "ssh_key", "progress": 5,
            "message": "Preparing SSH key...",
        })
        ssh_key_id = await _ensure_ssh_key(vultr, session)

        # Step 2: Create instance
        label = f"mediaflow-gpu-{int(time.time())}"
        await manager.broadcast("cloud.deploy_progress", {
            "server_id": 0, "step": "create_instance", "progress": 10,
            "message": f"Creating {gpu_model} instance in {region}...",
        })

        instance = await vultr.create_instance(
            plan=plan, region=region, label=label,
            ssh_key_ids=[ssh_key_id],
        )
        instance_id = instance["id"]

        # Step 3: Create WorkerServer record
        server = WorkerServer(
            name=f"Cloud GPU ({gpu_model or plan})",
            hostname="pending",
            port=22,
            ssh_username="root",
            ssh_key_path=_get_ssh_key_path(),
            role="transcode",
            max_concurrent_jobs=2,
            is_local=False,
            is_enabled=True,
            working_directory="/tmp/mediaflow",
            hourly_cost=hourly_rate,
            cloud_provider="vultr",
            cloud_instance_id=instance_id,
            cloud_plan=plan,
            cloud_region=region,
            cloud_created_at=datetime.utcnow(),
            cloud_auto_teardown=auto_teardown,
            cloud_idle_minutes=idle_minutes,
            cloud_status="creating",
            status="provisioning",
        )
        session.add(server)
        await session.commit()
        server_id = server.id

        await manager.broadcast("cloud.deploy_progress", {
            "server_id": server_id, "step": "create_instance", "progress": 15,
            "message": "Instance created, waiting for it to become active...",
        })

    # Step 4: Poll until active (separate session for long-running operation)
    try:
        ip_address = await _poll_instance_active(vultr, instance_id, server_id)
    except Exception as e:
        await _handle_deploy_failure(server_id, instance_id, vultr, str(e))
        raise

    # Step 5: Update server with IP
    async with async_session_factory() as session:
        result = await session.execute(
            select(WorkerServer).where(WorkerServer.id == server_id)
        )
        server = result.scalar_one()
        server.hostname = ip_address
        server.cloud_status = "bootstrapping"
        await session.commit()

    await manager.broadcast("cloud.deploy_progress", {
        "server_id": server_id, "step": "bootstrapping", "progress": 50,
        "message": f"Instance active at {ip_address}. Waiting for SSH...",
    })

    # Step 6: Wait for SSH
    try:
        await _wait_for_ssh(ip_address, server_id)
    except Exception as e:
        await _handle_deploy_failure(server_id, instance_id, vultr, str(e))
        raise

    await manager.broadcast("cloud.deploy_progress", {
        "server_id": server_id, "step": "provisioning", "progress": 60,
        "message": "SSH connected. Installing ffmpeg and GPU drivers...",
    })

    # Step 7: Run provisioning
    try:
        from app.services.provisioning_service import run_provisioning
        await run_provisioning(server_id, install_gpu_drivers=True)
    except Exception as e:
        await _handle_deploy_failure(server_id, instance_id, vultr, f"Provisioning failed: {e}")
        raise

    # Step 8: Finalize
    async with async_session_factory() as session:
        result = await session.execute(
            select(WorkerServer).where(WorkerServer.id == server_id)
        )
        server = result.scalar_one()
        server.cloud_status = "active"
        server.status = "online"
        await session.commit()

        # Create instance cost record
        cost_record = CloudCostRecord(
            worker_server_id=server_id,
            cloud_provider="vultr",
            cloud_instance_id=instance_id,
            cloud_plan=plan,
            hourly_rate=hourly_rate,
            start_time=server.cloud_created_at,
            record_type="instance",
        )
        session.add(cost_record)
        await session.commit()

    await manager.broadcast("cloud.deploy_completed", {
        "server_id": server_id,
        "instance_ip": ip_address,
        "gpu_model": gpu_model or "Unknown",
    })

    logger.info(f"Cloud GPU deployed: server_id={server_id}, ip={ip_address}, plan={plan}")

    # Reassign queued jobs that have no worker
    await _reassign_unassigned_jobs(server_id)

    return server_id


async def _reassign_unassigned_jobs(worker_server_id: int):
    """Reassign queued jobs with no worker to the newly deployed cloud worker."""
    from app.utils.ffmpeg import FFmpegCommandBuilder
    from app.utils.path_resolver import determine_transfer_mode
    from app.services.transcode_service import TranscodeService

    async with async_session_factory() as session:
        # Load the new worker
        result = await session.execute(
            select(WorkerServer).where(WorkerServer.id == worker_server_id)
        )
        worker = result.scalar_one_or_none()
        if not worker or worker.status != "online":
            return

        # Find all queued jobs with no worker assigned
        result = await session.execute(
            select(TranscodeJob).where(
                TranscodeJob.status == "queued",
                TranscodeJob.worker_server_id.is_(None),
            )
        )
        jobs = result.scalars().all()
        if not jobs:
            return

        svc = TranscodeService(session)
        reassigned_count = 0

        for job in jobs:
            # Determine transfer mode for this worker
            plex_server_has_ssh = False
            if job.media_item_id:
                media_result = await session.execute(
                    select(MediaItem).where(MediaItem.id == job.media_item_id)
                )
                media = media_result.scalar_one_or_none()
                if media and media.plex_library_id:
                    lib_result = await session.execute(
                        select(PlexLibrary).where(PlexLibrary.id == media.plex_library_id)
                    )
                    lib = lib_result.scalar_one_or_none()
                    if lib and lib.plex_server_id:
                        srv_result = await session.execute(
                            select(PlexServer).where(PlexServer.id == lib.plex_server_id)
                        )
                        srv = srv_result.scalar_one_or_none()
                        if srv and srv.ssh_hostname:
                            plex_server_has_ssh = True

            mode, resolved_path = determine_transfer_mode(
                job.source_path, worker.is_local, worker.path_mappings or [],
                plex_server_has_ssh=plex_server_has_ssh,
            )

            # Upgrade to NVENC if worker has GPU
            config = job.config_json or {}
            config = await svc._maybe_upgrade_to_nvenc(worker_server_id, config)

            # Rebuild ffmpeg command with worker path
            effective_input = resolved_path or job.source_path
            builder = FFmpegCommandBuilder(config, effective_input)
            ffmpeg_command = builder.build()
            output_path = builder._get_output_path()

            job.worker_server_id = worker_server_id
            job.transfer_mode = mode
            job.worker_input_path = resolved_path
            job.config_json = config
            job.ffmpeg_command = ffmpeg_command
            job.output_path = output_path
            reassigned_count += 1

        await session.commit()

        if reassigned_count > 0:
            logger.info(f"Reassigned {reassigned_count} queued jobs to cloud worker {worker_server_id}")
            await manager.broadcast("cloud.jobs_reassigned", {
                "server_id": worker_server_id,
                "job_count": reassigned_count,
            })


async def _poll_instance_active(vultr: VultrClient, instance_id: str, server_id: int) -> str:
    """Poll Vultr API until instance is active. Returns the main IP address."""
    max_wait = 600  # 10 minutes
    interval = 10
    elapsed = 0

    while elapsed < max_wait:
        instance = await vultr.get_instance(instance_id)
        status = instance.get("status", "")
        power = instance.get("power_status", "")
        main_ip = instance.get("main_ip", "")

        progress = min(45, 15 + int(elapsed / max_wait * 30))
        await manager.broadcast("cloud.deploy_progress", {
            "server_id": server_id, "step": "waiting_active",
            "progress": progress,
            "message": f"Instance status: {status} / power: {power}...",
        })

        if status == "active" and power == "running" and main_ip and main_ip != "0.0.0.0":
            return main_ip

        await asyncio.sleep(interval)
        elapsed += interval

    raise TimeoutError(f"Instance {instance_id} did not become active within {max_wait}s")


async def _wait_for_ssh(ip_address: str, server_id: int):
    """Wait for SSH to become available on the instance."""
    from app.utils.ssh import SSHClient

    max_wait = 600  # 10 minutes — Vultr cloud-init runs package updates before SSH
    interval = 10
    elapsed = 0
    ssh_key_path = _get_ssh_key_path()
    last_error = ""

    logger.info(f"Waiting for SSH on {ip_address} with key {ssh_key_path}")

    while elapsed < max_wait:
        try:
            ssh = SSHClient(ip_address, 22, "root", ssh_key_path)
            connected = await asyncio.wait_for(
                ssh.test_connection(),
                timeout=20,
            )
            if connected:
                logger.info(f"SSH connected to {ip_address} after {elapsed}s")
                return
            last_error = "test_connection returned False"
        except asyncio.TimeoutError:
            last_error = "connection attempt timed out"
        except Exception as e:
            last_error = str(e)

        logger.debug(f"SSH attempt to {ip_address} failed ({elapsed}s): {last_error}")
        await manager.broadcast("cloud.deploy_progress", {
            "server_id": server_id, "step": "waiting_ssh",
            "progress": min(58, 50 + int(elapsed / max_wait * 8)),
            "message": f"Waiting for SSH ({elapsed}s)... {last_error}",
        })

        await asyncio.sleep(interval)
        elapsed += interval

    raise TimeoutError(f"SSH not available on {ip_address} within {max_wait}s. Last error: {last_error}")


async def _handle_deploy_failure(server_id: int, instance_id: str, vultr: VultrClient, error: str):
    """Clean up on deploy failure: destroy instance, update server record."""
    logger.error(f"Cloud deploy failed for server {server_id}: {error}")

    # Try to destroy the instance
    try:
        await vultr.delete_instance(instance_id)
    except Exception as e:
        logger.error(f"Failed to destroy instance {instance_id} after deploy failure: {e}")

    # Update server record
    async with async_session_factory() as session:
        result = await session.execute(
            select(WorkerServer).where(WorkerServer.id == server_id)
        )
        server = result.scalar_one_or_none()
        if server:
            server.cloud_status = "failed"
            server.status = "setup_failed"
            server.is_enabled = False
            await session.commit()

    await manager.broadcast("cloud.deploy_failed", {
        "server_id": server_id,
        "error": error[:500],
    })


async def teardown_cloud_gpu(server_id: int) -> bool:
    """Destroy a Vultr instance and clean up the WorkerServer record."""
    async with async_session_factory() as session:
        result = await session.execute(
            select(WorkerServer).where(WorkerServer.id == server_id)
        )
        server = result.scalar_one_or_none()
        if not server or not server.cloud_instance_id:
            return False

        instance_id = server.cloud_instance_id
        cloud_plan = server.cloud_plan
        hourly_rate = server.hourly_cost or 0
        created_at = server.cloud_created_at

        vultr = await _get_vultr_client(session)

        # Update status
        server.cloud_status = "destroying"
        server.status = "offline"
        server.is_enabled = False
        await session.commit()

        await manager.broadcast("server.status", {
            "server_id": server_id, "status": "offline",
        })

    # Destroy instance
    try:
        deleted = await vultr.delete_instance(instance_id)
        if not deleted:
            logger.warning(f"Vultr delete returned non-204 for {instance_id}")
    except Exception as e:
        logger.error(f"Failed to delete Vultr instance {instance_id}: {e}")

    # Close cost record
    total_cost = 0.0
    async with async_session_factory() as session:
        # Find the open instance cost record
        result = await session.execute(
            select(CloudCostRecord).where(
                CloudCostRecord.cloud_instance_id == instance_id,
                CloudCostRecord.record_type == "instance",
                CloudCostRecord.end_time.is_(None),
            )
        )
        cost_record = result.scalar_one_or_none()
        now = datetime.utcnow()
        if cost_record:
            cost_record.end_time = now
            duration = (now - cost_record.start_time).total_seconds()
            cost_record.duration_seconds = duration
            cost_record.cost_usd = round((duration / 3600) * cost_record.hourly_rate, 4)
            total_cost = cost_record.cost_usd
            await session.commit()

        # Update server cloud_status
        result = await session.execute(
            select(WorkerServer).where(WorkerServer.id == server_id)
        )
        server = result.scalar_one_or_none()
        if server:
            server.cloud_status = "destroyed"
            await session.commit()

    await manager.broadcast("cloud.teardown_completed", {
        "server_id": server_id,
        "total_cost": round(total_cost, 2),
    })

    logger.info(f"Cloud GPU torn down: server_id={server_id}, cost=${total_cost:.2f}")
    return True
