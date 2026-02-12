import asyncio
import json
import logging
from datetime import datetime

from sqlalchemy import select

from app.database import async_session_factory
from app.models.worker_server import WorkerServer
from app.api.websocket import manager
from app.utils.ssh import SSHClient

logger = logging.getLogger(__name__)

FFMPEG_URLS = {
    "x86_64": "https://github.com/BtbN/FFmpeg-Builds/releases/download/latest/ffmpeg-master-latest-linux64-gpl.tar.xz",
    "aarch64": "https://github.com/BtbN/FFmpeg-Builds/releases/download/latest/ffmpeg-master-latest-linuxarm64-gpl.tar.xz",
}


async def _broadcast_progress(server_id: int, progress: int, step: str, message: str):
    await manager.broadcast("provision.progress", {
        "server_id": server_id,
        "progress": progress,
        "step": step,
        "message": message,
    })


async def run_provisioning(server_id: int, install_gpu_drivers: bool = False):
    """Install ffmpeg and configure a fresh VPS via SSH.

    Follows the benchmark_service pattern: own session via async_session_factory,
    WebSocket progress via manager.broadcast().
    """
    async with async_session_factory() as session:
        result = await session.execute(
            select(WorkerServer).where(WorkerServer.id == server_id)
        )
        server = result.scalar_one_or_none()
        if not server:
            logger.error(f"Provision: server {server_id} not found")
            return

        server.status = "provisioning"
        await session.commit()

        await manager.broadcast("server.status", {
            "server_id": server_id,
            "status": "provisioning",
        })

        log_entries = []
        ssh = SSHClient(
            server.hostname,
            server.port or 22,
            server.ssh_username,
            server.ssh_key_path,
        )

        try:
            # Step 1: Detect distro
            await _broadcast_progress(server_id, 5, "detect_distro", "Detecting Linux distribution...")
            distro_result = await ssh.run_command("cat /etc/os-release 2>/dev/null || echo 'unknown'")
            os_release = distro_result.get("stdout", "")
            distro_family = "unknown"
            if any(d in os_release.lower() for d in ["debian", "ubuntu", "mint", "pop"]):
                distro_family = "debian"
            elif any(d in os_release.lower() for d in ["rhel", "centos", "fedora", "rocky", "alma", "amazon"]):
                distro_family = "rhel"
            elif "arch" in os_release.lower():
                distro_family = "arch"

            if distro_family == "unknown":
                # Fallback: check for package managers
                apt_check = await ssh.run_command("which apt-get 2>/dev/null")
                if apt_check.get("exit_status") == 0:
                    distro_family = "debian"
                else:
                    dnf_check = await ssh.run_command("which dnf 2>/dev/null || which yum 2>/dev/null")
                    if dnf_check.get("exit_status") == 0:
                        distro_family = "rhel"

            log_entries.append({"step": "detect_distro", "family": distro_family})
            logger.info(f"Provision [{server_id}]: detected distro family={distro_family}")

            # Step 2: Check sudo
            await _broadcast_progress(server_id, 10, "check_sudo", "Checking root/sudo access...")
            whoami = await ssh.run_command("whoami")
            is_root = whoami.get("stdout", "").strip() == "root"
            sudo_prefix = "" if is_root else "sudo "

            if not is_root:
                sudo_check = await ssh.run_command("sudo -n true 2>/dev/null && echo OK")
                if "OK" not in (sudo_check.get("stdout") or ""):
                    raise PermissionError(
                        "User does not have passwordless sudo. "
                        "Run 'echo \"<user> ALL=(ALL) NOPASSWD:ALL\" | sudo tee /etc/sudoers.d/<user>' on the server, "
                        "or connect as root."
                    )

            log_entries.append({"step": "check_sudo", "is_root": is_root})

            # Step 3: Install prerequisites
            await _broadcast_progress(server_id, 20, "install_prereqs", "Installing prerequisites...")
            if distro_family == "debian":
                prereq_cmd = f"{sudo_prefix}apt-get update -qq && {sudo_prefix}apt-get install -y -qq wget tar xz-utils"
            elif distro_family == "rhel":
                pkg_mgr = "dnf" if "dnf" in (await ssh.run_command("which dnf 2>/dev/null")).get("stdout", "") else "yum"
                prereq_cmd = f"{sudo_prefix}{pkg_mgr} install -y -q wget tar xz"
            elif distro_family == "arch":
                prereq_cmd = f"{sudo_prefix}pacman -Sy --noconfirm wget tar xz"
            else:
                prereq_cmd = "echo 'Skipping prereqs for unknown distro'"

            prereq_result = await ssh.run_command(prereq_cmd)
            log_entries.append({
                "step": "install_prereqs",
                "exit_status": prereq_result.get("exit_status"),
            })

            # Step 4: Detect architecture
            await _broadcast_progress(server_id, 25, "detect_arch", "Detecting CPU architecture...")
            arch_result = await ssh.run_command("uname -m")
            arch = arch_result.get("stdout", "").strip()

            if arch not in FFMPEG_URLS:
                if arch == "x86_64" or "64" in arch:
                    arch = "x86_64"
                elif "aarch64" in arch or "arm64" in arch:
                    arch = "aarch64"
                else:
                    raise RuntimeError(f"Unsupported architecture: {arch}. Only x86_64 and aarch64 are supported.")

            ffmpeg_url = FFMPEG_URLS[arch]
            log_entries.append({"step": "detect_arch", "arch": arch})

            # Step 5: Download + install ffmpeg
            await _broadcast_progress(server_id, 35, "download_ffmpeg", "Downloading ffmpeg static build...")
            download_cmd = (
                f"cd /tmp && "
                f"wget -q --show-progress -O ffmpeg-static.tar.xz '{ffmpeg_url}' && "
                f"echo DOWNLOAD_OK"
            )
            dl_result = await ssh.run_command(download_cmd)
            if "DOWNLOAD_OK" not in (dl_result.get("stdout") or ""):
                raise IOError(f"Failed to download ffmpeg: {dl_result.get('stderr', '')[:300]}")

            await _broadcast_progress(server_id, 45, "install_ffmpeg", "Extracting and installing ffmpeg...")
            install_cmd = (
                f"cd /tmp && "
                f"tar xf ffmpeg-static.tar.xz && "
                f"FFDIR=$(ls -d ffmpeg-master-* 2>/dev/null | head -1) && "
                f"{sudo_prefix}cp -f $FFDIR/bin/ffmpeg /usr/local/bin/ffmpeg && "
                f"{sudo_prefix}cp -f $FFDIR/bin/ffprobe /usr/local/bin/ffprobe && "
                f"{sudo_prefix}chmod +x /usr/local/bin/ffmpeg /usr/local/bin/ffprobe && "
                f"rm -rf /tmp/ffmpeg-static.tar.xz /tmp/ffmpeg-master-* && "
                f"echo INSTALL_OK"
            )
            install_result = await ssh.run_command(install_cmd)
            if "INSTALL_OK" not in (install_result.get("stdout") or ""):
                raise IOError(f"Failed to install ffmpeg: {install_result.get('stderr', '')[:300]}")

            log_entries.append({"step": "install_ffmpeg", "status": "ok"})

            # Step 6: Verify ffmpeg
            await _broadcast_progress(server_id, 60, "verify_ffmpeg", "Verifying ffmpeg installation...")
            version_result = await ssh.run_command("ffmpeg -version 2>/dev/null | head -1")
            ffmpeg_version = version_result.get("stdout", "").strip()
            if not ffmpeg_version or version_result.get("exit_status") != 0:
                raise RuntimeError("ffmpeg installed but not responding to -version")

            encoders_result = await ssh.run_command("ffmpeg -encoders 2>/dev/null | grep -E '(libx265|libx264|libsvtav1)' | head -5")
            supported_encoders = encoders_result.get("stdout", "").strip()
            log_entries.append({
                "step": "verify_ffmpeg",
                "version": ffmpeg_version,
                "encoders": supported_encoders,
            })

            # Step 7: GPU detection + NVENC compatibility check
            await _broadcast_progress(server_id, 70, "gpu_detection", "Checking for GPU hardware...")
            gpu_result = await ssh.run_command("lspci 2>/dev/null | grep -i nvidia || echo 'NO_NVIDIA'")
            has_nvidia = "NO_NVIDIA" not in (gpu_result.get("stdout") or "")

            if has_nvidia:
                # Don't install GPU drivers — cloud vGPU instances ship with the
                # correct driver pre-installed and changing it breaks the vGPU.
                # Instead, test if the installed ffmpeg's NVENC works with the driver.
                await _broadcast_progress(server_id, 75, "nvenc_test", "Testing NVENC GPU encoding...")
                nvenc_test = await ssh.run_command(
                    "ffmpeg -y -f lavfi -i nullsrc=s=320x240:d=0.1 "
                    "-c:v hevc_nvenc -frames:v 1 -f null /dev/null 2>&1"
                )
                nvenc_works = nvenc_test.get("exit_status") == 0

                if nvenc_works:
                    log_entries.append({"step": "nvenc_test", "status": "ok"})
                    logger.info(f"Provision [{server_id}]: NVENC works with static ffmpeg")
                else:
                    # Static ffmpeg's NVENC SDK is too new for this driver.
                    # Install Jellyfin ffmpeg which is compiled against SDK 12.x
                    # (compatible with driver 535+).
                    nvenc_err = (nvenc_test.get("stdout") or "")[-200:]
                    logger.warning(
                        f"Provision [{server_id}]: NVENC failed with static ffmpeg, "
                        f"installing Jellyfin ffmpeg for SDK compatibility: {nvenc_err}"
                    )
                    await _broadcast_progress(
                        server_id, 78, "jellyfin_ffmpeg",
                        "NVENC incompatible — installing GPU-compatible ffmpeg...",
                    )
                    try:
                        # Use distro codename to select the correct package
                        codename_result = await ssh.run_command(
                            "lsb_release -cs 2>/dev/null || "
                            "grep VERSION_CODENAME /etc/os-release 2>/dev/null | cut -d= -f2"
                        )
                        codename = (codename_result.get("stdout") or "").strip() or "noble"
                        # Download and install Jellyfin ffmpeg + dependencies
                        jf_download = (
                            f"cd /tmp && "
                            f"wget -q -O jellyfin-ffmpeg.deb "
                            f"'https://repo.jellyfin.org/files/ffmpeg/ubuntu/latest-7.x/amd64/"
                            f"jellyfin-ffmpeg7_7.1.3-1-{codename}_amd64.deb'"
                        )
                        await ssh.run_command(jf_download, timeout=60)
                        await ssh.run_command(
                            f"{sudo_prefix}dpkg -i --force-depends /tmp/jellyfin-ffmpeg.deb", timeout=30
                        )
                        await ssh.run_command(
                            f"{sudo_prefix}apt-get install -f -y", timeout=120
                        )
                        await ssh.run_command("rm -f /tmp/jellyfin-ffmpeg.deb")

                        # Check if Jellyfin ffmpeg binary exists
                        jf_check = await ssh.run_command(
                            "test -x /usr/lib/jellyfin-ffmpeg/ffmpeg && echo JF_OK"
                        )
                        if "JF_OK" in (jf_check.get("stdout") or ""):
                            # Replace static ffmpeg with Jellyfin's NVENC-compatible build
                            await ssh.run_command(
                                f"{sudo_prefix}ln -sf /usr/lib/jellyfin-ffmpeg/ffmpeg /usr/local/bin/ffmpeg && "
                                f"{sudo_prefix}ln -sf /usr/lib/jellyfin-ffmpeg/ffprobe /usr/local/bin/ffprobe"
                            )
                            # Verify NVENC works now
                            retest = await ssh.run_command(
                                "ffmpeg -y -f lavfi -i nullsrc=s=320x240:d=0.1 "
                                "-c:v hevc_nvenc -frames:v 1 -f null /dev/null 2>&1"
                            )
                            if retest.get("exit_status") == 0:
                                log_entries.append({"step": "nvenc_test", "status": "ok_jellyfin"})
                                logger.info(f"Provision [{server_id}]: NVENC works with Jellyfin ffmpeg")
                            else:
                                log_entries.append({"step": "nvenc_test", "status": "failed_jellyfin", "error": nvenc_err})
                                logger.warning(f"Provision [{server_id}]: NVENC still failed after Jellyfin ffmpeg")
                        else:
                            log_entries.append({"step": "nvenc_test", "status": "jellyfin_install_failed"})
                    except Exception as jf_err:
                        log_entries.append({"step": "nvenc_test", "status": "jellyfin_error", "error": str(jf_err)[:200]})
            else:
                log_entries.append({"step": "gpu_detection", "nvidia_found": False})

            # Step 8: Create working directory
            await _broadcast_progress(server_id, 85, "create_workdir", "Creating working directory...")
            workdir = server.working_directory or "/tmp/mediaflow"
            workdir_cmd = f"{sudo_prefix}mkdir -p {workdir}"
            if not is_root:
                username = server.ssh_username or whoami.get("stdout", "").strip()
                workdir_cmd += f" && {sudo_prefix}chown {username}:{username} {workdir}"
            workdir_result = await ssh.run_command(workdir_cmd)
            log_entries.append({
                "step": "create_workdir",
                "path": workdir,
                "exit_status": workdir_result.get("exit_status"),
            })

            # Step 9: Re-probe capabilities
            await _broadcast_progress(server_id, 95, "probe_capabilities", "Detecting server capabilities...")
            capabilities = await ssh.probe_capabilities()
            if capabilities.get("cpu_model"):
                server.cpu_model = capabilities["cpu_model"]
            if capabilities.get("cpu_cores"):
                server.cpu_cores = capabilities["cpu_cores"]
            if capabilities.get("ram_gb"):
                server.ram_gb = capabilities["ram_gb"]
            if capabilities.get("gpu_model"):
                server.gpu_model = capabilities["gpu_model"]
            if capabilities.get("hw_accel_types"):
                server.hw_accel_types = capabilities["hw_accel_types"]

            log_entries.append({"step": "probe_capabilities", "capabilities": capabilities})

            # Step 10: Complete
            server.status = "online"
            server.provision_log = json.dumps({
                "completed_at": datetime.utcnow().isoformat(),
                "ffmpeg_version": ffmpeg_version,
                "distro_family": distro_family,
                "arch": arch,
                "steps": log_entries,
            })
            await session.commit()

            await _broadcast_progress(server_id, 100, "completed", "Setup complete!")
            await manager.broadcast("provision.completed", {
                "server_id": server_id,
                "ffmpeg_version": ffmpeg_version,
                "capabilities": capabilities,
            })
            await manager.broadcast("server.status", {
                "server_id": server_id,
                "status": "online",
            })

            logger.info(f"Provision [{server_id}]: completed successfully")

        except Exception as e:
            logger.error(f"Provision failed for server {server_id}: {e}")
            server.status = "setup_failed"
            server.provision_log = json.dumps({
                "failed_at": datetime.utcnow().isoformat(),
                "error": str(e)[:1000],
                "steps": log_entries,
            })
            await session.commit()

            await manager.broadcast("provision.failed", {
                "server_id": server_id,
                "error": str(e)[:500],
            })
            await manager.broadcast("server.status", {
                "server_id": server_id,
                "status": "setup_failed",
            })
