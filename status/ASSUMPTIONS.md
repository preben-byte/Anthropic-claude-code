# ASSUMPTIONS

| # | Antakelse | Konsekvens hvis feil | Verifiseres |
|---|---|---|---|
| A1 | ElevenLabs-endepunktene i adapteren (create-previews, text-to-speech med pcm_24000) stemmer med gjeldende API | Adapteren justeres mot offisiell dokumentasjon før første live-kall | Fase 1, første kjøring med nøkkel |
| A2 | Målmaskinen ved Marivold kjører Python 3.12+ | `requires-python` heves; koden bruker ingen 3.11-spesifikke begrensninger | Fase 2-oppsett |
| A3 | Samme `voice_id` kan brukes i både flash- og kvalitetsmodell hos ElevenLabs | Manifestet får per-modell voice_id-felt | Fase 1 |
| A4 | Preben godtar engelsk `hint`-notasjon i uttaleordboken inntil leverandørens ordbokformat (IPA/CMU) er verifisert | Konverteres til leverandørformat i adapteren | Fase 1 |
| A5 | Blandet testtekst (norske stedsnavn i engelsk setning) dekker kjernen i endret §7 godt nok for kandidatvurdering | Utvides med flere faguttrykk fra §6.4-listen | Fase 1, lyttetest |
| A6 | Wake word «Jarvis» er akustisk brukbart som standard inntil endelig navn velges | Kun konfigendring; wake-word-motor velges i Fase 2 | Fase 2 |
