# ACCEPTANCE_TESTS — Project Jarvis

Automatiserte tester ligger i `tests/` og kjøres med `pytest`.
Status: **20/20 passerer** (Fase 0).

## A. Identitet og konfigurasjon (implementert)

| ID | Krav | Test |
|---|---|---|
| A1 | Arbeidsnavnet er «Jarvis» i konfig, ikke i kode | `test_config.py::test_default_identity_is_working_name` |
| A2 | Navn/wake word endres via én YAML-fil uten at stemme eller språkpolicy berøres | `test_config.py::test_rename_via_config_file_only` |
| A3 | Navn/wake word kan overstyres per enhet via miljøvariabler | `test_config.py::test_env_override` |
| A4 | Blankt navn/wake word avvises | `test_config.py::test_blank_name_rejected` |

## B. Språkpolicy — endret §7 (implementert)

| ID | Krav | Test |
|---|---|---|
| B1 | STT optimalisert for nb-NO, konservativt språkbytte | `test_language_policy.py::test_stt_optimised_for_norwegian` |
| B2 | Svar alltid britisk engelsk, uansett inngangsspråk | `test_language_policy.py::test_reply_is_british_english_even_for_norwegian_input` |
| B3 | Norsk svar kun ved uttrykkelig forespørsel | `test_language_policy.py::test_norwegian_reply_only_on_explicit_request` |
| B4 | Norske navn/steder har uttaleoppføringer (Marivold, Paradisbukta, Beverdalen, Golanhøyden) | `test_language_policy.py::test_norwegian_pronunciation_uses_lexicon` |

## C. Voice Lab (implementert i mock; regenereres mot ekte API i Fase 1)

| ID | Krav | Test |
|---|---|---|
| C1 | Uten nøkkel: mock-modus, aldri krasj | `test_voice_lab.py::test_adapter_falls_back_to_mock_without_key` |
| C1b | Avvist nøkkel: fall tilbake til mock med advarsel, aldri krasj | `test_voice_lab.py::test_adapter_falls_back_to_mock_on_rejected_key` |
| C1c | Gyldig nøkkel: ekte leverandøradapter velges | `test_voice_lab.py::test_adapter_uses_provider_when_key_is_valid` |
| C2 | Gyldig WAV, mono, 24 kHz | `test_voice_lab.py::test_mock_synthesis_writes_valid_wav` |
| C3 | 12 blindkodede kandidater A01–D03 med to kjerneprøver hver | `test_voice_lab.py::test_generates_twelve_blind_coded_candidates` |
| C4 | Blindliste eksponerer kun blindkode + lyd (bias-kontroll) | `test_voice_lab.py::test_blind_listing_hides_variant_information` |
| C5 | Voice manifest uten hemmeligheter, tur/retur-serialisering | `test_voice_lab.py::test_voice_manifest_roundtrip_contains_no_secrets` |

## D. CLI (implementert)

| ID | Krav | Test |
|---|---|---|
| D1 | `jarvis doctor` read-only, exit 0, viser aldri nøkkelverdier | `test_cli.py::test_doctor_runs_clean`, `test_doctor_json_mode` |
| D2 | Maskinlesbar JSON-modus | `test_cli.py::test_doctor_json_mode` |
| D3 | `jarvis voice test` produserer prøver i mock-modus | `test_cli.py::test_voice_test_in_mock_mode` |
| D4 | `jarvis models list` leser register fra YAML | `test_cli.py::test_models_list` |

## E. Senere faser (definert, ikke implementert)

Latens (wake < 200 ms, p50 < 800 ms, p95 < 1,5 s, barge-in < 250 ms,
TTS TTFA p50 < 450 ms), blindscore ≥ 4,3/5, falsk-oppvåkningsmåling,
rutingsevalueringer (§16), minne-, sikkerhets- og injectiontester, backup/
restore, `jarvis doctor` full dekning, emergency stop. Ferdigkriteriene i
masteroppdraget §19 gjelder uavkortet.
