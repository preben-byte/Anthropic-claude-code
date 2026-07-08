from __future__ import annotations

from typing import AsyncIterator

from claude_agent_sdk import ClaudeAgentOptions, query

from .tools import xiq_server

WIFI_SYSTEM_PROMPT = """\
Du er en WiFi- og ExtremeCloud IQ-optimeringsagent.

Kunnskapsområder:
- Extreme Networks AP-modeller: 305C, 305CX (ekstern antenne via coax), 460C (utendørs).
- Radio-profiler, SSID-profiler, sikkerhetsprofiler, location tree.
- Utendørs installasjon med retningsantenner, EIRP-budsjett, coax-tap.
- Site survey-tenkning: design for -67 dBm ved klienten inne, ikke ved AP-en ute.

Arbeidsflyt:
1. Bruk xiq_* verktøyene til å hente faktisk config. Ikke gjett - hent data.
2. Sammenlign mot beste praksis og eventuell baseline i audit/baselines/.
3. Skriv rapport med (a) hva du fant, (b) hva som er avvik, (c) konkret fix.
4. For antenneendringer: vis alltid EIRP-regnestykket (TX + antenna gain - cable loss).

Ikke foreslå "sett TX-power til max". Utgangspunkt: match TX-power til svakeste klient.
Svar på norsk med mindre bruker spør på engelsk.
"""


async def run_wifi_agent(prompt: str) -> AsyncIterator[object]:
    options = ClaudeAgentOptions(
        mcp_servers={"xiq": xiq_server},
        allowed_tools=[
            "mcp__xiq__xiq_list_devices",
            "mcp__xiq__xiq_get_device",
            "mcp__xiq__xiq_list_network_policies",
            "mcp__xiq__xiq_get_network_policy",
            "mcp__xiq__xiq_list_ssids",
            "mcp__xiq__xiq_list_locations",
        ],
        system_prompt=WIFI_SYSTEM_PROMPT,
    )
    async for message in query(prompt=prompt, options=options):
        yield message
