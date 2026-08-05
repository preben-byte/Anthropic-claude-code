# Jarvis Agents

Multi-agent orkestrator bygget på [Claude Agent SDK](https://github.com/anthropics/claude-agent-sdk-python).
Første agent: WiFi/ExtremeCloud IQ-optimering. Videre agenter (bilde, video, WordPress-booking,
ett-trykks feilsøk) plugges inn samme sted.

## Struktur

```
agents/
├── main.py            # Jarvis-orkestrator (CLI-entrypoint)
└── wifi/
    ├── agent.py       # Claude Agent SDK-oppsett + system prompt
    ├── tools.py       # MCP-tools rundt XIQ REST
    └── xiq_client.py  # httpx-basert XIQ REST-wrapper

audit/
├── baselines/         # Gullstandard-configer (git-versjonert)
├── configs/           # Faktiske dumper (sanitert før commit)
└── diff.py            # Unified diff mot baseline
```

## Kom i gang

```bash
python -m venv .venv && source .venv/bin/activate
pip install -e .

cp .env.example .env
# Fyll inn ANTHROPIC_API_KEY og XIQ_TOKEN

python -m agents.main wifi "Vis alle 305CX-er og radioprofilene deres"
```

## Legg til en ny agent

1. Lag `agents/<navn>/` med `agent.py` (Claude Agent SDK-oppsett) og `tools.py` (MCP-tools).
2. Registrer i `AGENTS`-dict i `agents/main.py`.
3. Kjør: `python -m agents.main <navn> "<prompt>"`.

## Audit-flyt

Se [`audit/README.md`](audit/README.md). Kort versjon: eksporter config → vask secrets →
commit til `audit/configs/` → diff mot `audit/baselines/`.

## Sikkerhetsnotater

- `.env` og alle secrets ignoreres av `.gitignore`.
- Config-dumper (`audit/configs/`) skal ALDRI committes uten sanitizing —
  se `audit/README.md` for sjekkliste.
- XIQ API-token bør ha minst mulig scope (read-only er nok for auditflyten).
