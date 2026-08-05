from __future__ import annotations

import os
from typing import Any

import httpx


class XIQError(RuntimeError):
    pass


class XIQClient:
    def __init__(
        self,
        token: str | None = None,
        base_url: str | None = None,
        timeout: float = 30.0,
    ) -> None:
        self.token = token or os.environ.get("XIQ_TOKEN")
        if not self.token:
            raise XIQError("XIQ_TOKEN not set (env or constructor arg)")
        self.base_url = (
            base_url
            or os.environ.get("XIQ_BASE_URL")
            or "https://api.extremecloudiq.com"
        )
        self._client = httpx.Client(
            base_url=self.base_url,
            headers={
                "Authorization": f"Bearer {self.token}",
                "Accept": "application/json",
            },
            timeout=timeout,
        )

    def _get(self, path: str, params: dict[str, Any] | None = None) -> Any:
        r = self._client.get(path, params=params or {})
        if r.status_code >= 400:
            raise XIQError(f"{r.status_code} {r.request.method} {path}: {r.text[:400]}")
        return r.json()

    def list_devices(self, page: int = 1, limit: int = 100) -> Any:
        return self._get("/devices", {"page": page, "limit": limit})

    def get_device(self, device_id: int) -> Any:
        return self._get(f"/devices/{device_id}")

    def list_network_policies(self, page: int = 1, limit: int = 100) -> Any:
        return self._get("/network-policies", {"page": page, "limit": limit})

    def get_network_policy(self, policy_id: int) -> Any:
        return self._get(f"/network-policies/{policy_id}")

    def list_ssids(self, page: int = 1, limit: int = 100) -> Any:
        return self._get("/ssids", {"page": page, "limit": limit})

    def list_locations(self) -> Any:
        return self._get("/locations/tree")

    def close(self) -> None:
        self._client.close()

    def __enter__(self) -> "XIQClient":
        return self

    def __exit__(self, *_exc: Any) -> None:
        self.close()
