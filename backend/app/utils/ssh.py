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
                result = await asyncio.wait_for(
                    conn.run("echo ok", check=True),
                    timeout=15,
                )
                return result.stdout.strip() == "ok"
        except ImportError:
            logger.warning("asyncssh not installed, SSH features unavailable")
            return False
        except Exception as e:
            logger.debug(f"SSH test to {self.hostname}: {e}")
            return False

    async def run_command(self, command: str, timeout: int = 300) -> Dict[str, Any]:
        try:
            import asyncssh
            kwargs = self._connect_kwargs()

            async with asyncssh.connect(**kwargs) as conn:
                result = await asyncio.wait_for(
                    conn.run(command),
                    timeout=timeout,
                )
                return {
                    "stdout": result.stdout,
                    "stderr": result.stderr,
                    "exit_status": result.exit_status,
                }
        except ImportError:
            return {"stdout": "", "stderr": "asyncssh not installed", "exit_status": 1}
        except asyncio.TimeoutError:
            return {"stdout": "", "stderr": f"Command timed out after {timeout}s", "exit_status": 1}
        except Exception as e:
            return {"stdout": "", "stderr": str(e), "exit_status": 1}

    async def run_command_streaming(self, command: str, line_callback=None,
                                      timeout: int = 7200) -> Dict[str, Any]:
        """Run a command via SSH and stream output lines to a callback.

        Used for long-running commands like ffmpeg where we want real-time progress.
        The callback receives each line of stderr as it arrives.
        """
        try:
            import asyncssh
            kwargs = self._connect_kwargs()
            kwargs["login_timeout"] = 30  # Longer timeout for cloud connections

            all_stderr = []
            all_stdout = []

            async with asyncssh.connect(**kwargs) as conn:
                async with conn.create_process(command) as process:
                    stderr_buffer = b""
                    try:
                        while True:
                            chunk = await asyncio.wait_for(
                                process.stderr.read(4096),
                                timeout=timeout,
                            )
                            if not chunk:
                                break
                            stderr_buffer += chunk.encode() if isinstance(chunk, str) else chunk

                            # Split on \r or \n for ffmpeg progress lines
                            while b"\r" in stderr_buffer or b"\n" in stderr_buffer:
                                r_pos = stderr_buffer.find(b"\r")
                                n_pos = stderr_buffer.find(b"\n")
                                if r_pos == -1:
                                    pos = n_pos
                                elif n_pos == -1:
                                    pos = r_pos
                                else:
                                    pos = min(r_pos, n_pos)

                                line_bytes = stderr_buffer[:pos]
                                if pos + 1 < len(stderr_buffer) and stderr_buffer[pos:pos+2] == b"\r\n":
                                    stderr_buffer = stderr_buffer[pos+2:]
                                else:
                                    stderr_buffer = stderr_buffer[pos+1:]

                                line_text = line_bytes.decode("utf-8", errors="replace").strip()
                                if line_text:
                                    all_stderr.append(line_text)
                                    if line_callback:
                                        await line_callback(line_text)
                    except asyncio.TimeoutError:
                        process.terminate()
                        return {
                            "stdout": "\n".join(all_stdout),
                            "stderr": "\n".join(all_stderr),
                            "exit_status": -1,
                        }

                    # Process remaining buffer
                    if stderr_buffer:
                        line_text = stderr_buffer.decode("utf-8", errors="replace").strip()
                        if line_text:
                            all_stderr.append(line_text)
                            if line_callback:
                                await line_callback(line_text)

                    await process.wait()
                    exit_status = process.exit_status

                    return {
                        "stdout": "\n".join(all_stdout),
                        "stderr": "\n".join(all_stderr),
                        "exit_status": exit_status,
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
        gpu_name = gpu_result.get("stdout", "").strip()
        if gpu_result["exit_status"] == 0 and gpu_name and "failed" not in gpu_name.lower():
            capabilities["gpu_model"] = gpu_name
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
                    try:
                        await sftp.put(local_path, remote_path,
                                       progress_handler=progress_callback)
                    except OSError as e:
                        if e.errno == 45:  # "Operation not supported" — SMB/NFS mounts
                            logger.info(f"sftp.put failed on network mount, using chunked upload")
                            await self._chunked_upload(sftp, local_path, remote_path, progress_callback)
                        else:
                            raise
            return True
        except Exception as e:
            logger.error(f"Upload failed: {e}")
            return False

    async def _chunked_upload(self, sftp, local_path: str, remote_path: str,
                              progress_callback=None) -> None:
        """Upload a file by reading chunks manually — works on SMB/NFS mounts."""
        import os
        file_size = os.path.getsize(local_path)
        chunk_size = 1024 * 1024  # 1 MB
        transferred = 0

        async with sftp.open(remote_path, "wb") as remote_file:
            with open(local_path, "rb") as local_file:
                while True:
                    chunk = local_file.read(chunk_size)
                    if not chunk:
                        break
                    await remote_file.write(chunk)
                    transferred += len(chunk)
                    if progress_callback:
                        try:
                            progress_callback(local_path, remote_path, transferred, file_size)
                        except Exception:
                            pass

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
