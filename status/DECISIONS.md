# DECISIONS

| # | Dato | Beslutning | Begrunnelse |
|---|---|---|---|
| D1 | 2026-08-02 | «Jarvis» beholdes som arbeidsnavn; `assistant_name` og `wake_word` er konfig (`config/assistant.yaml`) med miljøoverstyring | Prebens instruks: endelig navn velges senere uten stemmeendring eller ny bygging |
| D2 | 2026-08-02 | Språkpolicy per endret §7: STT nb-NO, tale ut alltid en-GB, norsk svar kun ved uttrykkelig forespørsel | Prebens endring av masteroppdraget, erstatter «Primærspråk er norsk bokmål»-avsnittet |
| D3 | 2026-08-02 | Identitet, stemme og språk holdes på tre uavhengige konfigakser | Rename skal aldri kunne rive med seg stemme/språk; testfestet |
| D4 | 2026-08-02 | Fase 0–1 bruker enkel `src/jarvis`-pakke i stedet for full monorepo-splitt | Repoet var tomt; full splitt (apps/services/packages) gjøres når dashboard og voice-agent landes, jf. oppdragets åpning for tilpasning |
| D5 | 2026-08-02 | Mock-modus er førsteklasses i alle adaptere | Hele pipelinen skal kunne kjøres, testes og måles uten nøkler/nettverk |
| D6 | 2026-08-02 | Uttale løses med leksikon ved TTS-tid; skrivemåte i data/logger endres aldri | Krav i oppdraget §6.4 og endret §7 |
| D7 | 2026-08-02 | CLI registrerer kun kommandoer som faktisk virker | `--help` skal aldri love funksjonalitet som ikke finnes |
| D8 | 2026-08-02 | Python-krav satt til >=3.11 midlertidig | Utviklingsmiljøet har 3.11; målmiljøet skal ha 3.12+ (se ASSUMPTIONS A2) |
