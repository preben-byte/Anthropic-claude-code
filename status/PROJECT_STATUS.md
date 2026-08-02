# PROJECT_STATUS

Sist oppdatert: 2026-08-02

## Fase: 0 (Discovery) fullført → 1 (Voice Lab) påbegynt

| Milepæl | Status |
|---|---|
| Arbeidsområde inspisert (repo var tomt bortsett fra `kode`-notat) | ✅ |
| Dokument- og statusstruktur opprettet | ✅ |
| Arkitektur og faseplan dokumentert | ✅ |
| Konfigsystem: `assistant_name`/`wake_word` konfigurerbart (endring 2) | ✅ testfestet |
| Språkpolicy: nb-NO inn / en-GB ut, endret §7 (endring 1) | ✅ testfestet |
| Uttaleordbok for norske navn i engelske setninger | ✅ startsett |
| Voice Lab: mock-adapter, 12 blindkodede kandidater, blindliste, manifest-skjema | ✅ kjørbar |
| ElevenLabs-adapter (ekte API, aktiveres av nøkkel) | ✅ skrevet, ⏳ uverifisert mot live API |
| CLI: `doctor`, `config`, `voice test`, `voice candidates`, `models list` | ✅ |
| Testsuite | ✅ 18/18 |
| `.env.example` + hemmelighetshåndtering | ✅ |

## Aktiv sperre

Fase 1 trenger `ELEVENLABS_API_KEY` i `.env.local` for å generere ekte
stemmekandidater (Voice Design). Alt annet kjører i mock-modus.
Se `status/BLOCKERS.md`.

## Neste

1. Preben legger inn nøkkel (én handling, se docs/OPERATIONS.md).
2. Kjør `jarvis voice candidates` mot ekte API; verifiser adapteren mot
   gjeldende ElevenLabs-dokumentasjon.
3. Blind lyttetest runde 1 (12 kandidater) — enkel avspillings-/scoringsside.
4. Deretter Fase 2-skjelett (LiveKit Agents, wake word fra konfig).
