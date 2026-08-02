# Project Jarvis

Prebens personlige AI-operativsystem. «Jarvis» er internt arbeidsnavn —
assistentens navn og wake word er konfigurasjon (`config/assistant.yaml`),
ikke kode, og kan endres uten ny bygging og uten å endre stemmen.

Systemet er ikke tilknyttet Marvel, Disney, Iron Man eller Paul Bettany, og
stemmen er en helt original syntetisk identitet (se `docs/VOICE_SPEC.md`).

## Språkpolicy

Preben snakker norsk bokmål til systemet (STT er optimalisert for norsk).
Systemet svarer alltid muntlig på naturlig britisk engelsk, med korrekt
uttale av norske navn og steder, og svarer bare på norsk når Preben
uttrykkelig ber om det. Se `config/language.yaml` og `docs/PRD.md`.

## Kom i gang

```bash
pip install -e ".[dev]"   # eller: uv pip install -e ".[dev]"
jarvis doctor             # helsesjekk (kjører i mock-modus uten API-nøkkel)
pytest                    # testsuite
jarvis voice candidates   # generer blindkodede stemmekandidater A01–D03
```

ElevenLabs-nøkkel legges i `.env.local` (se `docs/OPERATIONS.md`); uten
nøkkel kjører Voice Lab i mock-modus med gyldige WAV-filer.

## Struktur

- `config/` — identitet, språk, stemmer, modeller, ruting, tillatelser,
  integrasjoner, uttaleordbok
- `src/jarvis/` — Python-kjerne (konfig, Voice Lab, CLI, secrets)
- `docs/` — VISION, PRD, ARCHITECTURE, VOICE_SPEC, SECURITY, THREAT_MODEL,
  OPERATIONS, INTEGRATIONS, ACCEPTANCE_TESTS
- `status/` — PROJECT_STATUS, DECISIONS, ASSUMPTIONS, RISK_REGISTER, BLOCKERS
- `tests/` — pytest-suite

## Fase

Fase 0 (Discovery) er fullført; Fase 1 (Voice Lab) er påbegynt og venter på
API-nøkkel for ekte stemmekandidater. Se `status/PROJECT_STATUS.md`.
