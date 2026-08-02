# PRD — Project Jarvis

## 1. Identitet (konfigurerbar)

| Egenskap | Verdi | Kilde |
|---|---|---|
| Arbeidsnavn | Jarvis | `config/assistant.yaml` → `assistant_name` |
| Wake word | Jarvis | `config/assistant.yaml` → `wake_word` |
| Tiltale | ingen (konfigurerbart: `preben` / `sir` / `none`) | `config/assistant.yaml` |

Navnet er et arbeidsnavn. Endelig navn velges senere: endres i én YAML-fil
(eller via miljøvariablene `JARVIS_ASSISTANT_NAME` / `JARVIS_WAKE_WORD`),
uten kodeendring, uten ny bygging, og uten at stemmeidentiteten berøres.
Dette er testfestet i `tests/test_config.py`.

## 2. Språkpolicy (masteroppdrag §7, endret 2026-08-02)

Preben skal alltid kunne snakke norsk bokmål til systemet. STT og
språkforståelse er derfor optimalisert for norsk. Jarvis svarer alltid
muntlig på naturlig britisk engelsk, uansett hvilket språk Preben bruker.
Norske navn, steder og faguttrykk uttales korrekt inne i engelske setninger
(uttaleordbok, `config/pronunciation.yaml`). Jarvis svarer ikke på norsk med
mindre Preben uttrykkelig ber om det.

Implementert i `config/language.yaml` + `jarvis.config.schema.LanguagePolicy`
og testfestet i `tests/test_language_policy.py`:

- `listen.primary_language: nb-NO`, konservativt automatisk språkbytte —
  engelske faguttrykk i en norsk setning bytter ikke samtalespråk.
- `speak.language: en-GB` — alltid.
- `speak.reply_in_norwegian: on_explicit_request_only`.
- Skrivemåte i data og logger endres aldri for å oppnå riktig uttale.

## 3. Kjernekrav (sammendrag)

- Sanntidssamtale: lokal wake word, push-to-talk-reserve, VAD, semantisk
  turn detection, streaming STT/TTS, barge-in ≤ 250 ms.
- Latensmål: enkel kommando p50 < 800 ms / p95 < 1,5 s; wake word < 200 ms;
  muntlig kvittering for bakgrunnsjobb < 800 ms. Falsk oppvåkning måles.
- Multimodellhjerne: LiteLLM-gateway + native adaptere; modellregister i
  `config/models.yaml`; TaskEnvelope-basert ruting med harde sperrer før
  poengsetting; fallback bare til samme eller strengere personvernnivå.
- Minne: fire atskilte minnetyper; Markdown-hvelv som sannhetslag;
  pgvector som indeks; minneforslag godkjennes av Preben; sletting fjerner
  post, indeks og embeddings.
- Verktøy: strengt typede MCP-verktøy; alt starter read-only; fire
  risikonivåer (`config/permissions.yaml`); stemme alene er aldri nok for
  nivå 3.
- Kostnad: daglige/månedlige grenser, varsling ved 50/75/90/100 %,
  automatisk stopp fremfor overforbruk. Fable 5 brukes strategisk, aldri på
  wake word, STT eller trivielle svar.

## 4. Akseptanse

Se `docs/ACCEPTANCE_TESTS.md` og ferdigkriteriene i masteroppdraget §19.
Stemmen er ikke godkjent før Prebens eksplisitte beslutning (§6.10).
