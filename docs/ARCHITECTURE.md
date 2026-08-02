# ARCHITECTURE — Project Jarvis

## Logisk flyt

```
Mikrofon / telefon / nettleser
  → Wake word (konfigurerbart, config/assistant.yaml) + VAD + støydemping
  → Streaming STT (optimalisert nb-NO)
  → Samtale- og turstyring
  → Data- og risikoklassifisering
  → Modellruter (harde sperrer → poengsetting)
  → Valgt AI-modell eller bakgrunnsagent
  → Minneinnhenting + verktøysøk
  → Tillatelseskontrollert MCP-verktøy
  → Svarplan og taleoptimalisering (skrift ≠ tale; alltid en-GB ut)
  → Streaming TTS med fast stemmeidentitet + uttaleordbok
  → Høyttaler + dashboard + revisjonslogg
```

## Harde skiller

Ti lag holdes fullstendig atskilt: lyd/stemme, samtalestyring, modellruting,
minne, verktøy, tillatelser, bakgrunnsjobber, observability/revisjon,
brukergrensesnitt og leverandørspesifikk kode. Ingen språkmodell har direkte
tilgang til OS, nettverk, e-post, betalinger eller produksjonssystemer.

## Identitet vs. stemme vs. språk

Tre uavhengige akser, hver med egen konfigfil, slik at én kan endres uten å
røre de andre:

| Akse | Fil | Kan endres uten |
|---|---|---|
| Navn + wake word | `config/assistant.yaml` | ny bygging, stemmeendring |
| Stemmeidentitet | `config/voices.yaml` + `config/voice_manifest.json` | navnendring |
| Språkpolicy | `config/language.yaml` | begge over |

## Teknologivalg (fra oppdraget)

Python 3.12+, FastAPI, Pydantic v2, AsyncIO, LiveKit Agents, ElevenLabs
Voice Design/TTS, selvhostet LiteLLM, PostgreSQL + pgvector, Redis,
Markdown-kunnskapshvelv, n8n som workflow-motor, MCP som verktøygrensesnitt,
Next.js-dashboard, Docker Compose, OpenTelemetry, pytest/Vitest/Playwright,
uv og pnpm, Alembic.

## Repostruktur

Fase 0–1 bruker en enkel pakkestruktur; full monorepo-splitt gjøres når
dashboard og voice-agent landes (begrunnelse i `status/DECISIONS.md`).

```
config/          # all styring: identitet, språk, stemmer, modeller,
                 # ruting, tillatelser, integrasjoner, uttaleordbok
src/jarvis/      # Python-kjerne
  config/        # typet konfiglasting (Pydantic v2)
  voice_lab/     # Fase 1: adaptere, kandidater, manifest, testtekster
  cli.py         # `jarvis`-kommandoen
  secrets.py     # .env.local / miljø; aldri i konfig eller logger
tests/           # pytest
docs/  status/   # dokumentasjon og prosjektstatus
var/             # generert lyd (gitignorert)
```

Planlagt utvidelse følger oppdragets monorepo-skisse: `apps/` (api,
voice-agent, dashboard, edge-client), `services/` (conversation,
model-router, memory, tool-gateway, job-runner, policy-engine, voice-lab),
`packages/`, `knowledge/`, `evals/`, `infra/`.

## Adaptermønster

All leverandørkode ligger bak smale grensesnitt (`TTSAdapter` er første
eksempel). Mock-implementasjoner er førsteklasses: hele systemet skal kunne
kjøre uten API-nøkler. En ny TTS- eller modellleverandør skal kunne legges
til uten å endre samtalekjernen.
