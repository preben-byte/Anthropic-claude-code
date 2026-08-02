# BLOCKERS

## B1 — Gyldig ElevenLabs API-nøkkel (aktiv, oppdatert 2026-08-02)

- **Hva er ferdig:** Voice Lab-pipeline (kandidatgenerering A01–D03,
  blindliste, manifest-skjema, CLI) kjørbar og testet i mock-modus.
  Robusthet forbedret: `jarvis doctor` *validerer* nå nøkkelen mot API-et
  (read-only), og en avvist nøkkel gir automatisk mock-fallback med
  advarsel i stedet for krasj.
- **Test kjørt:** `pytest` 20/20 grønn; `jarvis doctor`, `jarvis voice
  test` og `jarvis voice candidates` kjørt mot faktisk miljø.
- **Eksakt sperre:** Verdien som er lagt inn i miljøvariabelen
  `ELEVENLABS_API_KEY` er **ikke en gyldig ElevenLabs-nøkkel** — API-et
  avviser den med 401, og formatet stemmer ikke (ekte nøkler starter med
  `sk_`). `jarvis doctor` viser `elevenlabs_api_key: invalid (using mock)`.
- **Én handling for Preben:** elevenlabs.io → profilikon → API Keys →
  Create API Key → kopier `sk_`-verdien → erstatt verdien i
  `ELEVENLABS_API_KEY` i Claude Code-miljøinnstillingene (eller i
  `.env.local` lokalt). Aldri i chat.
- **Fortsetter med etterpå:** Verifisere adapteren mot gjeldende ElevenLabs-
  dokumentasjon, generere ekte kandidater, bygge blind lyttetest runde 1.

Ingen andre aktive sperrer.
