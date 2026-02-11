import asyncio
import logging
from typing import Optional, Dict, Any, List

logger = logging.getLogger(__name__)


class SSHClient:
    def __init__(self, hostname: str, port: int = 22,
                 username: Optional[str] = None, key_path: Optional[str] = None,
                 password: Optional[str] = None):
        self.hostname = hostname
        self.port = port
        self.username = username
        self.key_path = key_path
        self.password = password

    def _connect_kwargs(self) -> dict:
        kwargs = {
            "host": self.hostname,
            "port": self.port,
            "known_hosts": None,
            "login_timeout": 15,
        }
        if self.username:
            kwargs["username"] = self.username
        if self.key_path:
            kwargs["client_keys"] = [self.key_path]
        if self.password:
            kwargs["password"] = self.password
        return kwargs

    async def test_connection(self) -> bool:
        try:
            import asyncssh
            kwargs = self._connect_kwargs()

            async with asyncssh.connect(**kwargs) as conn:
                result = await conn.run("echo ok", check=True)
                return result.stdout.strip() == "ok"
        except ImportError:
            logger.warning("asyncssh not installed, SSH features unavailable")
            return False
        except Exception as e:
            logger.error(f"SSH connection failed: {e}")
            return False

    async def run_command(self, command: str) -> Dict[str, Any]:
        try:
            import asyncssh
            kwargs = self._connect_kwargs()

            async with asyncssh.connect(**kwargs) as conn:
                result = await conn.run(command)
                return {
                    "stdout": result.stdout,
                    "stderr": result.stderr,
                    "exit_status": result.exit_status,
                }
        except ImportError:
            return {"stdout": "", "stderr": "asyncssh not installed", "exit_status": 1}
        except Exception as e:
            return {"stdout": "", "stderr": str(e), "exit_status": 1}

    async def probe_capabilities(self) -> Dict[str, Any]:
        capabilities = {}
        cpu_result = await self.run_command("cat /proc/cpuinfo | grep 'model name' | head -1 | cut -d: -f2")
        if cpu_result["exit_status"] == 0:
            capabilities["cpu_model"] = cpu_result["stdout"].strip()

        cores_result = await self.run_command("nproc")
        if cores_result["exit_status"] == 0:
            try:
                capabilities["cpu_cores"] = int(cores_result["stdout"].strip())
            except ValueError:
                pass

        ram_result = await self.run_command("free -g | awk '/^Mem:/{print $2}'")
        if ram_result["exit_status"] == 0:
            try:
                capabilities["ram_gb"] = float(ram_result["stdout"].strip())
            except ValueError:
                pass

        gpu_result = await self.run_command("nvidia-smi --query-gpu=name --format=csv,noheader 2>/dev/null | head -1")
        if gpu_result["exit_status"] == 0 and gpu_result["stdout"].strip():
            capabilities["gpu_model"] = gpu_result["stdout"].strip()
            capabilities["hw_accel_types"] = ["nvenc"]
        else:
            capabilities["hw_accel_types"] = []

        ffmpeg_result = await self.run_command("ffmpeg -version 2>/dev/null | head -1")
        if ffmpeg_result["exit_status"] == 0:
            capabilities["ffmpeg_version"] = ffmpeg_result["stdout"].strip()

        return capabilities

    async def upload_file(self, local_path: str, remote_path: str,
                          progress_callback=None) -> bool:
        try:
            import asyncssh
            kwargs = self._connect_kwargs()

            async with asyncssh.connect(**kwargs) as conn:
                async with conn.start_sftp_client() as sftp:
                    await sftp.put(local_path, remote_path,
                                   progress_handler=progress_callback)
            return True
        except Exception as e:
            logger.error(f"Upload failed: {e}")
            return False

    async def download_file(self, remote_path: str, local_path: str,
                            progress_callback=None) -> bool:
        try:
            import asyncssh
            kwargs = self._connect_kwargs()

            async with asyncssh.connect(**kwargs) as conn:
                async with conn.start_sftp_client() as sftp:
                    await sftp.get(remote_path, local_path,
                                   progress_handler=progress_callback)
            return True
        except Exception as e:
            logger.error(f"Download failed: {e}")
            return False
