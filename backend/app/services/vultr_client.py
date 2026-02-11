import logging
from typing import Optional

import httpx

logger = logging.getLogger(__name__)

# Known GPU plan metadata (Vultr doesn't expose GPU details in the plans API)
GPU_PLAN_INFO = {
    "vcg-a16-2c-4g-1vram": {
        "gpu_model": "NVIDIA A16", "vcpus": 2, "ram_mb": 4096,
        "gpu_vram_gb": 1, "monthly_cost": 65.0, "hourly_cost": 0.097,
    },
    "vcg-a16-4c-16g-4vram": {
        "gpu_model": "NVIDIA A16", "vcpus": 4, "ram_mb": 16384,
        "gpu_vram_gb": 4, "monthly_cost": 150.0, "hourly_cost": 0.224,
    },
    "vcg-a16-6c-32g-8vram": {
        "gpu_model": "NVIDIA A16", "vcpus": 6, "ram_mb": 32768,
        "gpu_vram_gb": 8, "monthly_cost": 250.0, "hourly_cost": 0.373,
    },
    "vcg-a16-8c-64g-16vram": {
        "gpu_model": "NVIDIA A16", "vcpus": 8, "ram_mb": 65536,
        "gpu_vram_gb": 16, "monthly_cost": 500.0, "hourly_cost": 0.746,
    },
    "vcg-a40-12c-120g-16vram": {
        "gpu_model": "NVIDIA A40", "vcpus": 12, "ram_mb": 122880,
        "gpu_vram_gb": 16, "monthly_cost": 750.0, "hourly_cost": 1.119,
    },
    "vcg-a40-12c-120g-24vram": {
        "gpu_model": "NVIDIA A40", "vcpus": 12, "ram_mb": 122880,
        "gpu_vram_gb": 24, "monthly_cost": 850.0, "hourly_cost": 1.268,
    },
    "vcg-a40-16c-240g-48vram": {
        "gpu_model": "NVIDIA A40", "vcpus": 16, "ram_mb": 245760,
        "gpu_vram_gb": 48, "monthly_cost": 1700.0, "hourly_cost": 2.536,
    },
}

# Ubuntu 24.04 LTS OS ID on Vultr
UBUNTU_2404_OS_ID = 2284


class VultrClient:
    BASE_URL = "https://api.vultr.com/v2"

    def __init__(self, api_key: str):
        self.api_key = api_key

    def _headers(self) -> dict:
        return {
            "Authorization": f"Bearer {self.api_key}",
            "Content-Type": "application/json",
        }

    async def create_instance(
        self,
        plan: str,
        region: str,
        label: str,
        ssh_key_ids: list[str],
        os_id: int = UBUNTU_2404_OS_ID,
    ) -> dict:
        """Create a new Vultr instance. Returns the instance dict."""
        body = {
            "plan": plan,
            "region": region,
            "os_id": os_id,
            "label": label,
            "sshkey_id": ssh_key_ids,
            "backups": "disabled",
            "enable_ipv6": False,
        }
        async with httpx.AsyncClient(timeout=30) as client:
            resp = await client.post(
                f"{self.BASE_URL}/instances",
                headers=self._headers(),
                json=body,
            )
            resp.raise_for_status()
            return resp.json()["instance"]

    async def get_instance(self, instance_id: str) -> dict:
        """Get a single instance by ID."""
        async with httpx.AsyncClient(timeout=15) as client:
            resp = await client.get(
                f"{self.BASE_URL}/instances/{instance_id}",
                headers=self._headers(),
            )
            resp.raise_for_status()
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
            resp.raise_for_status()
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
            resp.raise_for_status()
            return resp.json().get("ssh_keys", [])

    async def create_ssh_key(self, name: str, public_key: str) -> dict:
        """Upload an SSH public key. Returns the key dict."""
        async with httpx.AsyncClient(timeout=15) as client:
            resp = await client.post(
                f"{self.BASE_URL}/ssh-keys",
                headers=self._headers(),
                json={"name": name, "ssh_key": public_key},
            )
            resp.raise_for_status()
            return resp.json()["ssh_key"]

    async def list_gpu_plans(self) -> list:
        """List available GPU plans with enriched metadata."""
        plans = []
        for plan_id, info in GPU_PLAN_INFO.items():
            try:
                regions = await self.get_plan_regions(plan_id)
            except Exception:
                regions = []
            plans.append({
                "plan_id": plan_id,
                "gpu_model": info["gpu_model"],
                "vcpus": info["vcpus"],
                "ram_mb": info["ram_mb"],
                "gpu_vram_gb": info["gpu_vram_gb"],
                "monthly_cost": info["monthly_cost"],
                "hourly_cost": info["hourly_cost"],
                "regions": regions,
            })
        return plans

    async def get_plan_regions(self, plan_id: str) -> list:
        """Get regions where a specific plan is available."""
        async with httpx.AsyncClient(timeout=15) as client:
            resp = await client.get(
                f"{self.BASE_URL}/regions",
                headers=self._headers(),
                params={"type": "all", "per_page": 100},
            )
            resp.raise_for_status()
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
