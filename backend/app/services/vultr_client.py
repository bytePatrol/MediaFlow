import base64
import logging
import re
from typing import Optional

import httpx

logger = logging.getLogger(__name__)

# Curated GPU plans for transcoding — display name + plan ID
ALLOWED_GPU_PLANS = {
    "vcg-a16-6c-64g-16vram": "A16 1× (16GB)",
    "vcg-a40-8c-40g-16vram": "A40 1/3 (16GB)",
    "vcg-a40-12c-60g-24vram": "A40 1/2 (24GB)",
}

# Pattern: vcg-{gpu}-{vcpus}c-{ram}g-{vram}vram
_PLAN_ID_RE = re.compile(r"^vcg-([a-z0-9]+)-(\d+)c-(\d+)g-(\d+)vram$")

class VultrClient:
    BASE_URL = "https://api.vultr.com/v2"

    def __init__(self, api_key: str):
        self.api_key = api_key
        self._os_id_cache: Optional[int] = None
        self._startup_script_id: Optional[str] = None

    def _headers(self) -> dict:
        return {
            "Authorization": f"Bearer {self.api_key}",
            "Content-Type": "application/json",
        }

    def _check_response(self, resp: httpx.Response) -> None:
        """Raise with Vultr's actual error message on failure."""
        if resp.status_code >= 400:
            try:
                detail = resp.json()
            except Exception:
                detail = resp.text
            raise RuntimeError(
                f"Vultr API {resp.status_code}: {detail}"
            )

    async def _get_ubuntu_os_id(self) -> int:
        """Dynamically find the Ubuntu 24.04 (or latest LTS) OS ID."""
        if self._os_id_cache:
            return self._os_id_cache
        async with httpx.AsyncClient(timeout=15) as client:
            resp = await client.get(
                f"{self.BASE_URL}/os",
                headers=self._headers(),
                params={"per_page": 500},
            )
            self._check_response(resp)
            os_list = resp.json().get("os", [])
            # Prefer Ubuntu 24.04, fall back to 22.04
            for target in ["Ubuntu 24.04", "Ubuntu 22.04"]:
                for os_entry in os_list:
                    if target in os_entry.get("name", "") and os_entry.get("arch") == "x64":
                        self._os_id_cache = os_entry["id"]
                        logger.info(f"Vultr OS selected: {os_entry['name']} (id={os_entry['id']})")
                        return os_entry["id"]
            # Last resort: any Ubuntu x64
            for os_entry in os_list:
                if "Ubuntu" in os_entry.get("name", "") and os_entry.get("arch") == "x64":
                    self._os_id_cache = os_entry["id"]
                    logger.info(f"Vultr OS fallback: {os_entry['name']} (id={os_entry['id']})")
                    return os_entry["id"]
            raise RuntimeError("Could not find Ubuntu OS on Vultr")

    async def _ensure_startup_script(self) -> str:
        """Ensure a 'mediaflow-init' startup script exists on Vultr. Returns the script ID."""
        if self._startup_script_id:
            return self._startup_script_id

        script_content = (
            "#!/bin/bash\n"
            "# MediaFlow: ensure SSH is accessible after cloud-init completes\n"
            "ufw allow 22/tcp 2>/dev/null || true\n"
            "iptables -I INPUT -p tcp --dport 22 -j ACCEPT 2>/dev/null || true\n"
            "systemctl enable ssh 2>/dev/null; systemctl restart ssh 2>/dev/null\n"
            "systemctl enable sshd 2>/dev/null; systemctl restart sshd 2>/dev/null\n"
        )

        async with httpx.AsyncClient(timeout=15) as client:
            # Check for existing script
            resp = await client.get(
                f"{self.BASE_URL}/startup-scripts",
                headers=self._headers(),
                params={"per_page": 100},
            )
            self._check_response(resp)
            for s in resp.json().get("startup_scripts", []):
                if s.get("name") == "mediaflow-init":
                    self._startup_script_id = s["id"]
                    return s["id"]

            # Create new
            resp = await client.post(
                f"{self.BASE_URL}/startup-scripts",
                headers=self._headers(),
                json={"name": "mediaflow-init", "type": "boot",
                      "script": base64.b64encode(script_content.encode()).decode()},
            )
            self._check_response(resp)
            script_id = resp.json()["startup_script"]["id"]
            self._startup_script_id = script_id
            logger.info(f"Created Vultr startup script: {script_id}")
            return script_id

    async def create_instance(
        self,
        plan: str,
        region: str,
        label: str,
        ssh_key_ids: list[str],
    ) -> dict:
        """Create a new Vultr instance. Returns the instance dict."""
        os_id = await self._get_ubuntu_os_id()
        script_id = await self._ensure_startup_script()

        body = {
            "plan": plan,
            "region": region,
            "os_id": os_id,
            "label": label,
            "sshkey_id": ssh_key_ids,
            "script_id": script_id,
            "backups": "disabled",
            "enable_ipv6": False,
        }
        logger.info(f"Vultr create_instance: plan={plan} region={region} os_id={os_id}")
        async with httpx.AsyncClient(timeout=30) as client:
            resp = await client.post(
                f"{self.BASE_URL}/instances",
                headers=self._headers(),
                json=body,
            )
            self._check_response(resp)
            return resp.json()["instance"]

    async def get_instance(self, instance_id: str) -> dict:
        """Get a single instance by ID."""
        async with httpx.AsyncClient(timeout=15) as client:
            resp = await client.get(
                f"{self.BASE_URL}/instances/{instance_id}",
                headers=self._headers(),
            )
            self._check_response(resp)
            return resp.json()["instance"]

    async def delete_instance(self, instance_id: str) -> bool:
        """Delete/destroy an instance. Returns True on success."""
        async with httpx.AsyncClient(timeout=15) as client:
            resp = await client.delete(
                f"{self.BASE_URL}/instances/{instance_id}",
                headers=self._headers(),
            )
            return resp.status_code == 204

    async def list_instances(self, label_filter: Optional[str] = None) -> list:
        """List all instances, optionally filtering by label prefix."""
        async with httpx.AsyncClient(timeout=15) as client:
            resp = await client.get(
                f"{self.BASE_URL}/instances",
                headers=self._headers(),
                params={"per_page": 100},
            )
            self._check_response(resp)
            instances = resp.json().get("instances", [])
            if label_filter:
                instances = [i for i in instances if i.get("label", "").startswith(label_filter)]
            return instances

    async def get_ssh_keys(self) -> list:
        """List all SSH keys on the account."""
        async with httpx.AsyncClient(timeout=15) as client:
            resp = await client.get(
                f"{self.BASE_URL}/ssh-keys",
                headers=self._headers(),
            )
            self._check_response(resp)
            return resp.json().get("ssh_keys", [])

    async def create_ssh_key(self, name: str, public_key: str) -> dict:
        """Upload an SSH public key. Returns the key dict."""
        async with httpx.AsyncClient(timeout=15) as client:
            resp = await client.post(
                f"{self.BASE_URL}/ssh-keys",
                headers=self._headers(),
                json={"name": name, "ssh_key": public_key},
            )
            self._check_response(resp)
            return resp.json()["ssh_key"]

    async def list_gpu_plans(self) -> list:
        """List available GPU plans by querying the Vultr API directly."""
        async with httpx.AsyncClient(timeout=20) as client:
            resp = await client.get(
                f"{self.BASE_URL}/plans",
                headers=self._headers(),
                params={"type": "vcg", "per_page": 500},
            )
            self._check_response(resp)
            raw_plans = resp.json().get("plans", [])

        plans = []
        for p in raw_plans:
            plan_id = p.get("id", "")
            if plan_id not in ALLOWED_GPU_PLANS:
                continue
            m = _PLAN_ID_RE.match(plan_id)
            if not m:
                continue
            vram_gb = int(m.group(4))
            plans.append({
                "plan_id": plan_id,
                "gpu_model": ALLOWED_GPU_PLANS[plan_id],
                "vcpus": p.get("vcpu_count", 0),
                "ram_mb": p.get("ram", 0),
                "gpu_vram_gb": vram_gb,
                "monthly_cost": p.get("monthly_cost", 0),
                "hourly_cost": round(p.get("monthly_cost", 0) / 730, 3),
                "regions": p.get("locations", []),
            })
        plans.sort(key=lambda x: x["monthly_cost"])
        logger.info(f"Vultr GPU plans fetched: {len(plans)} plans available")
        return plans

    async def get_plan_regions(self, plan_id: str) -> list:
        """Get regions where a specific plan is available."""
        async with httpx.AsyncClient(timeout=15) as client:
            resp = await client.get(
                f"{self.BASE_URL}/regions",
                headers=self._headers(),
                params={"type": "all", "per_page": 100},
            )
            self._check_response(resp)
            regions = resp.json().get("regions", [])
            available = []
            for r in regions:
                if plan_id in r.get("available_plans", []):
                    available.append(r["id"])
            return available

    async def verify_api_key(self) -> bool:
        """Verify that the API key is valid by listing account info."""
        try:
            async with httpx.AsyncClient(timeout=10) as client:
                resp = await client.get(
                    f"{self.BASE_URL}/account",
                    headers=self._headers(),
                )
                return resp.status_code == 200
        except Exception:
            return False
