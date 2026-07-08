from __future__ import annotations

import argparse
import asyncio
import sys

from dotenv import load_dotenv

from .wifi.agent import run_wifi_agent

AGENTS = {
    "wifi": run_wifi_agent,
}


async def _run(agent_name: str, prompt: str) -> int:
    runner = AGENTS.get(agent_name)
    if runner is None:
        print(f"Unknown agent '{agent_name}'. Available: {', '.join(AGENTS)}", file=sys.stderr)
        return 2
    async for message in runner(prompt):
        print(message)
    return 0


def main() -> None:
    load_dotenv()
    parser = argparse.ArgumentParser(prog="jarvis", description="Multi-agent orchestrator")
    parser.add_argument("agent", choices=list(AGENTS), help="Which specialist agent to invoke")
    parser.add_argument("prompt", nargs="+", help="Prompt to send to the agent")
    args = parser.parse_args()
    rc = asyncio.run(_run(args.agent, " ".join(args.prompt)))
    sys.exit(rc)


if __name__ == "__main__":
    main()
