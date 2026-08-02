# THREAT_MODEL — Project Jarvis

Trusler fra masteroppdraget §12, med primær motvirkning. Detaljerte
kontroller står i `docs/SECURITY.md`.

| # | Trussel | Primær motvirkning |
|---|---|---|
| 1 | Prompt injection fra e-post/web/dokumenter/verktøysvar | Eksternt innhold er data, aldri instruksjoner; verktøykall krever policy-motor og nivågodkjenning |
| 2 | Ondsinnede MCP-servere | Tillatt-verktøy-liste; kun godkjente servere; schemavalidering |
| 3 | For brede OAuth-rettigheter | Minste privilegium; separate tjenestekontoer; scope-revisjon |
| 4 | Lekkasje av API-nøkler | .env.local/vault; aldri i logger/manifest; presence-only i CLI |
| 5 | Voice replay / syntetisk stemmespoofing | Stemme aldri nok for nivå 2–3; dashboardgodkjenning + reautentisering |
| 6 | Uønsket aktivering fra TV/høyttaler | Målt falsk-oppvåkningsrate; konfigurerbart wake word; mute-knapp |
| 7 | Handling på feil mottaker/enhet | Mottakerverifisering; forhåndsvisning; binding til eksakt mål |
| 8 | SSRF | Egress allowlist; adaptere uten fri URL-tilgang |
| 9 | Kommandoinjeksjon | Ingen rå shell for modeller; strengt typede verktøy |
| 10 | Path traversal | Verktøy med validerte, avgrensede stier |
| 11 | Hemmeligheter i logger | Redigering før logging; forbudsliste (§15) |
| 12 | Leverandørutfall | Fallback til samme/strengere personvernnivå; systemet kjører uten Fable 5 |
| 13 | Manipulerte minneposter | Minneforslag med godkjenning; endringslogg; kilder |
| 14 | Forgiftet RAG-innhold | Kildehenvisning; motstridende info vises; sensitivitetsmerking |
| 15 | Uautorisert modellbytte | Modellbytte logges og vises; brukerbekreftelse for vedvarende endring |
| 16 | Kostnadsangrep | Daglige/månedlige grenser; varsling 50/75/90/100 %; autostopp |
| 17 | Dobbel betaling/booking | Idempotency key; replay-beskyttelse |
| 18 | Tilgang til gjestedata | `restricted`-klasse; aldri til cloud-modeller; minste privilegium |
| 19 | CCTV-personvern | Absolutt read-only; restricted; aldri eksport uten eksplisitt oppdrag |
| 20 | Nettverksendring på utdatert info | Aktiv konfig leses alltid fra systemet; OBSERVED/CALCULATED/UNKNOWN/NOT USED-merking |

Sikkerhetsevalueringer (masteroppdrag §16) skal bevise: injection ignoreres,
manipulert dokument kan ikke aktivere verktøy, replay avvises, endret
parameter krever ny godkjenning, dobbel booking hindres.
