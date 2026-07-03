#!/usr/bin/env python3
"""List ExtremeCloud IQ devices whose model contains 'Atom' or 'AP30'.

Reads an API token from the XIQ_TOKEN environment variable and prints only
each matching device's hostname and management IP address, one per line
(tab-separated).

Usage:
    export XIQ_TOKEN=<your-xiq-api-token>
    python xiq_atom_ap30_devices.py
"""

from __future__ import annotations

import json
import os
import sys
import urllib.error
import urllib.parse
import urllib.request
from typing import Any, Iterator

API_BASE = "https://api.extremecloudiq.com"
PAGE_SIZE = 100
MATCH_TERMS = ("atom", "ap30")


def fail(msg: str, code: int = 1) -> None:
    print(f"error: {msg}", file=sys.stderr)
    sys.exit(code)


def get_token() -> str:
    token = os.environ.get("XIQ_TOKEN", "").strip()
    if not token:
        fail("XIQ_TOKEN environment variable is not set")
    return token


def fetch_page(token: str, page: int) -> dict[str, Any]:
    query = urllib.parse.urlencode({"views": "BASIC", "page": page, "limit": PAGE_SIZE})
    req = urllib.request.Request(
        f"{API_BASE}/devices?{query}",
        headers={
            "Authorization": f"Bearer {token}",
            "Accept": "application/json",
        },
    )
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            return json.load(resp)
    except urllib.error.HTTPError as e:
        body = e.read().decode("utf-8", "replace")[:200]
        fail(f"HTTP {e.code} from XIQ: {body}")
    except urllib.error.URLError as e:
        fail(f"network error reaching XIQ: {e.reason}")
    return {}


def iter_devices(token: str) -> Iterator[dict[str, Any]]:
    page = 1
    while True:
        payload = fetch_page(token, page)
        data = payload.get("data") or []
        for dev in data:
            yield dev
        total_pages = payload.get("total_pages") or 1
        if page >= total_pages or not data:
            return
        page += 1


def model_matches(device: dict[str, Any]) -> bool:
    fields = (
        device.get("product_type"),
        device.get("device_function"),
        device.get("hardware_type"),
    )
    haystack = " ".join(str(v) for v in fields if v).lower()
    return any(term in haystack for term in MATCH_TERMS)


def main() -> int:
    token = get_token()
    for dev in iter_devices(token):
        if not model_matches(dev):
            continue
        name = dev.get("hostname") or dev.get("device_name") or ""
        ip = dev.get("ip_address") or dev.get("device_admin_ip_address") or ""
        print(f"{name}\t{ip}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
