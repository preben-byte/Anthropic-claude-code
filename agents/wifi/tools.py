from __future__ import annotations

import json
from typing import Any

from claude_agent_sdk import create_sdk_mcp_server, tool

from .xiq_client import XIQClient, XIQError


def _text(payload: Any) -> dict[str, Any]:
    body = json.dumps(payload, indent=2, ensure_ascii=False, default=str)
    return {"content": [{"type": "text", "text": body}]}


def _error(msg: str) -> dict[str, Any]:
    return {"content": [{"type": "text", "text": f"ERROR: {msg}"}], "isError": True}


@tool(
    "xiq_list_devices",
    "List devices (APs, switches) registered in ExtremeCloud IQ.",
    {"limit": int, "page": int},
)
async def xiq_list_devices(args: dict[str, Any]) -> dict[str, Any]:
    try:
        with XIQClient() as c:
            return _text(c.list_devices(page=args.get("page", 1), limit=args.get("limit", 50)))
    except XIQError as e:
        return _error(str(e))


@tool(
    "xiq_get_device",
    "Fetch a single device by numeric device_id (from xiq_list_devices).",
    {"device_id": int},
)
async def xiq_get_device(args: dict[str, Any]) -> dict[str, Any]:
    try:
        with XIQClient() as c:
            return _text(c.get_device(args["device_id"]))
    except XIQError as e:
        return _error(str(e))


@tool(
    "xiq_list_network_policies",
    "List Network Policies (SSID + radio + security profile bundles).",
    {"limit": int, "page": int},
)
async def xiq_list_network_policies(args: dict[str, Any]) -> dict[str, Any]:
    try:
        with XIQClient() as c:
            return _text(
                c.list_network_policies(page=args.get("page", 1), limit=args.get("limit", 50))
            )
    except XIQError as e:
        return _error(str(e))


@tool(
    "xiq_get_network_policy",
    "Fetch full Network Policy detail by policy_id.",
    {"policy_id": int},
)
async def xiq_get_network_policy(args: dict[str, Any]) -> dict[str, Any]:
    try:
        with XIQClient() as c:
            return _text(c.get_network_policy(args["policy_id"]))
    except XIQError as e:
        return _error(str(e))


@tool(
    "xiq_list_ssids",
    "List SSIDs configured across policies.",
    {"limit": int, "page": int},
)
async def xiq_list_ssids(args: dict[str, Any]) -> dict[str, Any]:
    try:
        with XIQClient() as c:
            return _text(c.list_ssids(page=args.get("page", 1), limit=args.get("limit", 50)))
    except XIQError as e:
        return _error(str(e))


@tool("xiq_list_locations", "List location tree (sites/floors/zones).", {})
async def xiq_list_locations(_args: dict[str, Any]) -> dict[str, Any]:
    try:
        with XIQClient() as c:
            return _text(c.list_locations())
    except XIQError as e:
        return _error(str(e))


xiq_server = create_sdk_mcp_server(
    name="xiq",
    version="0.1.0",
    tools=[
        xiq_list_devices,
        xiq_get_device,
        xiq_list_network_policies,
        xiq_get_network_policy,
        xiq_list_ssids,
        xiq_list_locations,
    ],
)
