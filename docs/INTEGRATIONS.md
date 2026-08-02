# INTEGRATIONS — Project Jarvis

Alle integrasjoner er definert i `config/integrations.yaml`, starter
**deaktivert og read-only**, og tilbys gjennom strengt typede MCP-verktøy
eller tilsvarende schema-validert grensesnitt. Første reelle aktivering skjer
i Fase 5 etter en read-only integrasjonsinventering — anta aldri at en
tjeneste er aktiv.

## Katalog

| Integrasjon | Startmodus | Merknader |
|---|---|---|
| Home Assistant | read-only | WebSocket-hendelser; kun eksplisitt godkjente enheter; egen tjenestekonto; kritiske låser/porter/alarmer styres aldri kun ved stemme |
| MQTT | read-only | publish krever nivå 2 |
| ExtremeCloud IQ | read-only | aktiv policy/overrides/radioer/klienter leses fra systemet; alle skriveoperasjoner nivå 3 med full konsekvensvisning |
| Switcher/AP-er | read-only | som XIQ |
| WordPress | read-only | publisering nivå 2 |
| Marivold booking | read-only | historikk med WPBooking Calendar/Invite/BookVisit — faktisk løsning kartlegges i inventeringen. MVP: søk tilgjengelighet, les booking, oppsummer ankomst/avreise, utkast (booking/pris/betalingsinfo), avvik, dagsrapport. Aldri fullføre/kansellere/belaste/refundere/sende betalingslenke uten tydelig godkjenning |
| Gjesteportal | read-only | gjestedata er `restricted` |
| Infoskjermer | read-only | innholdspush nivå 2 |
| E-post | read-only | sending følger 7-stegs prosedyren i SECURITY.md |
| Kalender | read-only | opprettelse nivå 2 |
| Google Drive/Docs | read-only | |
| GitHub | read-only | |
| Lokale filer | read-only | avgrensede stier |
| n8n | read-only | workflow-motor for gjentatte automasjoner, webhooks, planlagte jobber, varslinger, godkjenningsflyter og MCP-eksponerte workflows — aldri en «gjør hva som helst»-funksjon |
| Stripe | read-only | kun utkast og status |
| Hikvision/CCTV | read-only (absolutt) | `restricted`; aldri til skymodeller; ingen endring av innstillinger/opptak/kontoer/retention, ingen eksport, ingen restart uten separat eksplisitt oppdrag |
| Vær/web | read-only | egress allowlist |
| Oppgaver/varsling | read-only | opprettelse nivå 1 |

## Adapterkrav

- Leverandørspesifikk kode kun i adapteren; kjernen er nøytral.
- Mock-/simulert modus er obligatorisk før første reelle kall.
- Hver adapter har egen tjenestekonto og minste nødvendige rettigheter.
- Tekniske funn merkes OBSERVED / CALCULATED / UNKNOWN / NOT USED; gammelt
  minne er aldri bevis på nåværende konfigurasjon.
