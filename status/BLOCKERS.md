# BLOCKERS

## B1 — ElevenLabs API-nøkkel (aktiv)

- **Hva er ferdig:** Voice Lab-pipeline (kandidatgenerering A01–D03,
  blindliste, manifest-skjema, CLI) kjørbar og testet i mock-modus.
- **Test kjørt:** `pytest` 18/18 grønn; `jarvis doctor` ok; `jarvis voice
  candidates` genererer 12 blindkodede kandidater med gyldige WAV-filer.
- **Eksakt sperre:** Ekte Voice Design-kandidater krever
  `ELEVENLABS_API_KEY`. Nøkkelen skal aldri limes inn i chat.
- **Én handling for Preben:**
  ```bash
  cp .env.example .env.local
  # rediger .env.local: ELEVENLABS_API_KEY=<din nøkkel>
  ```
  Verifiser med `jarvis doctor` → `elevenlabs_api_key: present`.
- **Fortsetter med etterpå:** Verifisere adapteren mot gjeldende ElevenLabs-
  dokumentasjon, generere ekte kandidater, bygge blind lyttetest runde 1.

Ingen andre aktive sperrer.
