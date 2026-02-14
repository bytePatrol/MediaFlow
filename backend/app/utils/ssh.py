import asyncio
import logging
import os
import re
import shlex
from typing import Optional, Dict, Any, List

logger = logging.getLogger(__name__)

# SFTP tuning — default asyncssh block_size is 16KB which causes excessive round trips.
# 256KB blocks reduce SFTP request count 16x and dramatically improve throughput.
SFTP_BLOCK_SIZE = 128 * 1024          # 128 KB per SFTP request (256 KB exceeds some servers' max packet size)
TRANSFER_CHUNK_SIZE = 4 * 1024 * 1024 # 4 MB read/write chunks

# Prefer hardware-accelerated ciphers (AES-GCM uses AES-NI on modern CPUs)
_PREFERRED_CIPHERS = [
    "aes128-gcm@openssh.com",
    "aes256-gcm@openssh.com",
    "aes128-ctr",
    "aes256-ctr",
]


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
            "encryption_algs": _PREFERRED_CIPHERS,
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

    def _ssh_cmd_args(self) -> str:
        """Build SSH command string for rsync -e flag."""
        parts = ["ssh", "-o", "StrictHostKeyChecking=no",
                 "-o", "UserKnownHostsFile=/dev/null",
                 "-o", "LogLevel=ERROR",
                 "-o", "Compression=no",
                 "-c", "aes128-gcm@openssh.com"]
        if self.port != 22:
            parts += ["-p", str(self.port)]
        if self.key_path:
            parts += ["-i", self.key_path]
        return " ".join(parts)

    def _remote_spec(self, path: str) -> str:
        """Build user@host:path spec for rsync/scp."""
        user_prefix = f"{self.username}@" if self.username else ""
        return f"{user_prefix}{self.hostname}:{shlex.quote(path)}"

    async def _rsync_transfer(self, src: str, dst: str, total_size: int,
                               progress_callback=None) -> bool:
        """Transfer a file using rsync over SSH with progress tracking.

        rsync uses native OpenSSH (C) which is much faster than asyncssh SFTP
        due to better TCP buffer utilization and hardware-accelerated ciphers.
        Uses --whole-file (skip delta algorithm) since we're always sending new files.
        Uses --progress (not --info=progress2) for macOS openrsync compatibility.
        """
        cmd = [
            "rsync", "-e", self._ssh_cmd_args(),
            "--inplace", "--whole-file", "--progress",
            src, dst,
        ]
        logger.info(f"rsync transfer: {src} -> {dst}")

        proc = await asyncio.create_subprocess_exec(
            *cmd,
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.PIPE,
        )

        # Parse rsync --progress output (macOS openrsync format):
        #   "  1234567 100%   15.43MB/s    0:00:05 (xfr#1, to-chk=0/1)"
        # or per-chunk lines:  "  1234567  12%   15.43MB/s    0:00:05"
        progress_re = re.compile(r'([\d,]+)\s+(\d+)%')
        buffer = b""

        while True:
            chunk = await proc.stdout.read(256)
            if not chunk:
                break
            buffer += chunk

            # Split on \r or \n (openrsync may use either)
            while b"\r" in buffer or b"\n" in buffer:
                r_pos = buffer.find(b"\r")
                n_pos = buffer.find(b"\n")
                if r_pos == -1:
                    pos = n_pos
                elif n_pos == -1:
                    pos = r_pos
                else:
                    pos = min(r_pos, n_pos)

                line_bytes = buffer[:pos]
                if pos + 1 < len(buffer) and buffer[pos:pos+2] == b"\r\n":
                    buffer = buffer[pos+2:]
                else:
                    buffer = buffer[pos+1:]

                line = line_bytes.decode("utf-8", errors="replace").strip()
                if progress_callback and line:
                    m = progress_re.search(line)
                    if m:
                        transferred = int(m.group(1).replace(",", ""))
                        try:
                            progress_callback(src, dst, transferred, total_size)
                        except Exception:
                            pass

        stderr = await proc.stderr.read()
        await proc.wait()

        if proc.returncode == 0:
            # Final progress callback at 100%
            if progress_callback:
                try:
                    progress_callback(src, dst, total_size, total_size)
                except Exception:
                    pass
            return True
        else:
            err = stderr.decode("utf-8", errors="replace").strip()
            logger.warning(f"rsync failed (rc={proc.returncode}): {err}")
            return False

    async def _parallel_ssh_upload(self, local_path: str, remote_path: str,
                                    total_size: int, progress_callback=None,
                                    num_streams: int = 4) -> bool:
        """Upload using N parallel SSH dd pipes for maximum throughput.

        Splits the file into segments on 1MB boundaries, pre-allocates the
        remote file, then writes each segment concurrently through independent
        SSH connections.  Each stream uses hardware-accelerated AES-GCM cipher.
        """
        MB = 1048576
        total_mb = total_size // MB
        segment_mb = total_mb // num_streams
        if segment_mb < 1:
            return False  # File too small for parallel upload

        ssh_cmd = self._ssh_cmd_args()
        user = f"{self.username}@" if self.username else ""
        host = f"{user}{self.hostname}"

        # Pre-allocate file at full size on remote
        pre = await asyncio.create_subprocess_shell(
            f'{ssh_cmd} -T {host} "truncate -s {total_size} {shlex.quote(remote_path)}"',
            stdout=asyncio.subprocess.PIPE, stderr=asyncio.subprocess.PIPE,
        )
        await pre.wait()
        if pre.returncode != 0:
            stderr = (await pre.stderr.read()).decode("utf-8", errors="replace")
            logger.warning(f"Parallel upload pre-allocate failed: {stderr}")
            return False

        done = [False]

        async def _stream(idx: int) -> bool:
            offset_mb = idx * segment_mb
            if idx == num_streams - 1:
                remaining = total_size - offset_mb * MB
                count_mb = (remaining + MB - 1) // MB
            else:
                count_mb = segment_mb

            cmd = (
                f'dd if={shlex.quote(local_path)} bs={MB} '
                f'skip={offset_mb} count={count_mb} 2>/dev/null | '
                f'{ssh_cmd} -T {host} '
                f'"dd of={shlex.quote(remote_path)} bs={MB} '
                f'seek={offset_mb} conv=notrunc 2>/dev/null"'
            )
            proc = await asyncio.create_subprocess_shell(
                cmd, stdout=asyncio.subprocess.PIPE, stderr=asyncio.subprocess.PIPE,
            )
            await proc.wait()

            if proc.returncode != 0:
                stderr = (await proc.stderr.read()).decode("utf-8", errors="replace")
                logger.warning(f"Parallel stream {idx} failed (rc={proc.returncode}): {stderr}")
                return False
            return True

        async def _poll_progress():
            """Poll remote file's allocated disk blocks to track actual bytes written."""
            import asyncssh
            try:
                kwargs = self._connect_kwargs()
                async with asyncssh.connect(**kwargs) as conn:
                    while not done[0]:
                        await asyncio.sleep(1.0)
                        # stat -c %b gives 512-byte blocks actually allocated (not apparent size)
                        result = await asyncio.wait_for(
                            conn.run(f"stat -c %b {shlex.quote(remote_path)} 2>/dev/null"),
                            timeout=5,
                        )
                        if result.exit_status == 0:
                            try:
                                blocks = int(result.stdout.strip())
                                written = blocks * 512
                                written = min(written, total_size)
                                if progress_callback and written > 0:
                                    progress_callback(local_path, remote_path,
                                                      written, total_size)
                            except (ValueError, TypeError):
                                pass
            except asyncio.CancelledError:
                pass
            except Exception as e:
                logger.debug(f"Parallel upload progress poller error: {e}")

        logger.info(
            f"Parallel upload: {local_path} -> {host}:{remote_path} "
            f"({total_size / MB:.0f} MB, {num_streams} streams)"
        )

        # Run streams + progress poller concurrently
        poll_task = asyncio.create_task(_poll_progress())
        try:
            results = await asyncio.gather(*[_stream(i) for i in range(num_streams)])
        finally:
            done[0] = True
            poll_task.cancel()
            try:
                await poll_task
            except asyncio.CancelledError:
                pass

        if all(results):
            # Verify remote file size matches
            check = await self.run_command(
                f'stat -c %s {shlex.quote(remote_path)} 2>/dev/null || '
                f'stat -f %z {shlex.quote(remote_path)}'
            )
            if check["exit_status"] == 0:
                try:
                    remote_size = int(check["stdout"].strip())
                    if remote_size != total_size:
                        logger.error(
                            f"Parallel upload size mismatch: remote={remote_size} local={total_size}"
                        )
                        return False
                except ValueError:
                    pass

            if progress_callback:
                try:
                    progress_callback(local_path, remote_path, total_size, total_size)
                except Exception:
                    pass
            return True

        return False

    async def upload_file(self, local_path: str, remote_path: str,
                          progress_callback=None) -> bool:
        try:
            file_size = os.path.getsize(local_path)

            if self.key_path and not self.password:
                # For large files, try parallel multi-stream upload (4 SSH connections)
                if file_size >= 100 * 1024 * 1024:
                    ok = await self._parallel_ssh_upload(
                        local_path, remote_path, file_size,
                        num_streams=4, progress_callback=progress_callback,
                    )
                    if ok:
                        return True
                    logger.info("Parallel upload failed, falling back to rsync")

                # Single-stream rsync fallback
                ok = await self._rsync_transfer(
                    local_path, self._remote_spec(remote_path),
                    file_size, progress_callback,
                )
                if ok:
                    return True
                logger.info("rsync upload failed, falling back to SFTP")

            # Fallback: asyncssh SFTP
            import asyncssh
            kwargs = self._connect_kwargs()

            async with asyncssh.connect(**kwargs) as conn:
                async with conn.start_sftp_client() as sftp:
                    try:
                        await sftp.put(local_path, remote_path,
                                       block_size=SFTP_BLOCK_SIZE,
                                       sparse=False,
                                       progress_handler=progress_callback)
                    except OSError as e:
                        if e.errno == 45:
                            logger.info("sftp.put failed on network mount, using chunked upload")
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
        transferred = 0

        async with sftp.open(remote_path, "wb", block_size=SFTP_BLOCK_SIZE) as remote_file:
            with open(local_path, "rb") as local_file:
                while True:
                    chunk = local_file.read(TRANSFER_CHUNK_SIZE)
                    if not chunk:
                        break
                    await remote_file.write(chunk)
                    transferred += len(chunk)
                    if progress_callback:
                        try:
                            progress_callback(local_path, remote_path, transferred, file_size)
                        except Exception:
                            pass

    async def relay_to(self, src_path: str, dst_client: "SSHClient", dst_path: str,
                       total_size: int = 0, progress_callback=None) -> bool:
        """Stream a file from this SSH host to another SSH host without local staging.

        Uses pipelined reads/writes — the reader fills a queue while the writer
        drains it concurrently, keeping both connections saturated.
        """
        try:
            import asyncssh
            src_kwargs = self._connect_kwargs()
            dst_kwargs = dst_client._connect_kwargs()

            async with asyncssh.connect(**src_kwargs) as src_conn:
                async with src_conn.start_sftp_client() as src_sftp:
                    if total_size <= 0:
                        try:
                            stat = await src_sftp.stat(src_path)
                            total_size = stat.size or 0
                        except Exception:
                            pass

                    async with asyncssh.connect(**dst_kwargs) as dst_conn:
                        async with dst_conn.start_sftp_client() as dst_sftp:
                            transferred = 0
                            queue: asyncio.Queue = asyncio.Queue(maxsize=8)
                            read_error = None

                            async def _reader():
                                nonlocal read_error
                                try:
                                    async with src_sftp.open(src_path, "rb",
                                                             block_size=SFTP_BLOCK_SIZE) as src_file:
                                        while True:
                                            chunk = await src_file.read(TRANSFER_CHUNK_SIZE)
                                            if not chunk:
                                                await queue.put(None)  # sentinel
                                                break
                                            await queue.put(chunk)
                                except Exception as e:
                                    read_error = e
                                    await queue.put(None)

                            async def _writer():
                                nonlocal transferred
                                async with dst_sftp.open(dst_path, "wb",
                                                         block_size=SFTP_BLOCK_SIZE) as dst_file:
                                    while True:
                                        chunk = await queue.get()
                                        if chunk is None:
                                            break
                                        await dst_file.write(chunk)
                                        transferred += len(chunk)
                                        if progress_callback:
                                            try:
                                                progress_callback(src_path, dst_path,
                                                                  transferred, total_size)
                                            except Exception:
                                                pass

                            await asyncio.gather(_reader(), _writer())

                            if read_error:
                                raise read_error

            return True
        except Exception as e:
            logger.error(f"Relay failed ({self.hostname} -> {dst_client.hostname}): {e}")
            return False

    async def _parallel_ssh_download(self, remote_path: str, local_path: str,
                                      total_size: int, progress_callback=None,
                                      num_streams: int = 4) -> bool:
        """Download using N parallel SSH dd pipes for maximum throughput."""
        MB = 1048576
        total_mb = total_size // MB
        segment_mb = total_mb // num_streams
        if segment_mb < 1:
            return False

        ssh_cmd = self._ssh_cmd_args()
        user = f"{self.username}@" if self.username else ""
        host = f"{user}{self.hostname}"

        # Pre-allocate local file
        with open(local_path, "wb") as f:
            f.truncate(total_size)

        done = [False]

        async def _stream(idx: int) -> bool:
            offset_mb = idx * segment_mb
            if idx == num_streams - 1:
                remaining = total_size - offset_mb * MB
                count_mb = (remaining + MB - 1) // MB
            else:
                count_mb = segment_mb

            cmd = (
                f'{ssh_cmd} -T {host} '
                f'"dd if={shlex.quote(remote_path)} bs={MB} '
                f'skip={offset_mb} count={count_mb} 2>/dev/null" | '
                f'dd of={shlex.quote(local_path)} bs={MB} '
                f'seek={offset_mb} conv=notrunc 2>/dev/null'
            )
            proc = await asyncio.create_subprocess_shell(
                cmd, stdout=asyncio.subprocess.PIPE, stderr=asyncio.subprocess.PIPE,
            )
            await proc.wait()

            if proc.returncode != 0:
                stderr = (await proc.stderr.read()).decode("utf-8", errors="replace")
                logger.warning(f"Parallel download stream {idx} failed: {stderr}")
                return False
            return True

        async def _poll_progress():
            """Poll local file's allocated disk blocks to track actual bytes written."""
            try:
                while not done[0]:
                    await asyncio.sleep(1.0)
                    try:
                        # On macOS, stat -f %b gives 512-byte blocks allocated
                        st = os.stat(local_path)
                        written = st.st_blocks * 512
                        written = min(written, total_size)
                        if progress_callback and written > 0:
                            progress_callback(remote_path, local_path, written, total_size)
                    except (OSError, ValueError):
                        pass
            except asyncio.CancelledError:
                pass

        logger.info(
            f"Parallel download: {host}:{remote_path} -> {local_path} "
            f"({total_size / MB:.0f} MB, {num_streams} streams)"
        )

        poll_task = asyncio.create_task(_poll_progress())
        try:
            results = await asyncio.gather(*[_stream(i) for i in range(num_streams)])
        finally:
            done[0] = True
            poll_task.cancel()
            try:
                await poll_task
            except asyncio.CancelledError:
                pass

        if all(results):
            local_size = os.path.getsize(local_path)
            if local_size != total_size:
                logger.error(f"Parallel download size mismatch: {local_size} vs {total_size}")
                return False
            if progress_callback:
                try:
                    progress_callback(remote_path, local_path, total_size, total_size)
                except Exception:
                    pass
            return True

        # Clean up partial file on failure
        if os.path.exists(local_path):
            os.remove(local_path)
        return False

    async def download_file(self, remote_path: str, local_path: str,
                            progress_callback=None, total_size: int = 0) -> bool:
        try:
            if self.key_path and not self.password:
                # Parallel multi-stream download for large files
                if total_size >= 100 * 1024 * 1024:
                    ok = await self._parallel_ssh_download(
                        remote_path, local_path, total_size,
                        num_streams=4, progress_callback=progress_callback,
                    )
                    if ok:
                        return True
                    logger.info("Parallel download failed, falling back to rsync")

                # Single-stream rsync
                ok = await self._rsync_transfer(
                    self._remote_spec(remote_path), local_path,
                    total_size, progress_callback,
                )
                if ok:
                    return True
                logger.info("rsync download failed, falling back to SFTP")

            # Fallback: asyncssh SFTP
            import asyncssh
            kwargs = self._connect_kwargs()

            async with asyncssh.connect(**kwargs) as conn:
                async with conn.start_sftp_client() as sftp:
                    await sftp.get(remote_path, local_path,
                                   block_size=SFTP_BLOCK_SIZE,
                                   progress_handler=progress_callback)
            return True
        except Exception as e:
            logger.error(f"Download failed: {e}")
            return False
