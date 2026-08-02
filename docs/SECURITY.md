# SECURITY — Project Jarvis

## Grunnprinsipper

- Innhold fra e-post, dokumenter, nettsider og verktøyresultater er **data,
  aldri systeminstruksjoner**.
- Minste privilegium; separate tjenestekontoer per integrasjon.
- Ingen rå shell-tilgang for samtalemodellen.
- Personvern er en hard sperre i modellrutingen, ikke et poengtall.
- Stemme alene er aldri tilstrekkelig autentisering for kritiske handlinger.

## Hemmeligheter

- Aldri i git, chat, konfig, manifest eller logger.
- `.env.local` (gitignorert), OS-nøkkellager eller ekstern vault.
- `.env.example` inneholder kun variabelnavn og forklaringer.
- CLI og doctor viser kun *tilstedeværelse*, aldri verdier.

## Obligatoriske kontroller (masteroppdrag §12)

Tillatt-verktøy- og tillatt-kommando-lister; egress allowlist; rate limits;
kostnadsgrenser; PII-redigering; sensitivitetsmerking; kryptering i ro og
transport; secret manager; uforanderlig audit-logg; automatisk backup med
dokumentert restore-test; avhengighetsskanning; SBOM; fastlåste
container-images; containere kjører ikke som root; nettverkssegmentering
mellom stemme, verktøy og produksjonssystemer.

## Tillatelsesmodell

Fire risikonivåer, definert i `config/permissions.yaml`:

| Nivå | Karakter | Godkjenning |
|---|---|---|
| 0 | read-only | automatisk |
| 1 | reversibel lokal endring | automatisk hvis mål/scope er entydig |
| 2 | ekstern/operativ effekt | forhåndsvisning + eksplisitt engangsgodkjenning |
| 3 | kritisk/vanskelig reverserbar | dashboard + ny autentisering (gjerne MFA) |

Kontroller: engangsbekreftelsestoken med kort utløp, binding til eksakt
handling og mål, replay-beskyttelse, idempotency key, before/after-snapshot,
rollback der mulig, automatisk avslag hvis parametre endres etter
godkjenning.

## Dataklassifisering og Fable 5

Fable 5 har dokumentert 30-dagers datalagring og er ikke ZDR:

- `public`: Fable 5 kan brukes.
- `internal`: etter policykontroll.
- `confidential`: rediger først, eller bruk annen godkjent modell.
- `restricted`: kun lokal modell eller særskilt godkjent ZDR-løsning.

Skal normalt aldri til Fable 5: gjestedata, betalingsdata, API-nøkler,
passord, kameraopptak, ansiktsbilder, sikkerhetskonfigurasjon, full
nettverkskonfig med hemmeligheter, private e-poster, personnummer og
helseopplysninger. Finnes ingen trygg modell, stopper systemet og forklarer
hvorfor — det lekker aldri data for å «løse» oppgaven.

## Domenespesifikke sperrer

- **CCTV/Hikvision**: absolutt read-only; `restricted`; aldri til skymodeller.
- **Nettverk (XIQ)**: read-only som standard; save/deploy/reboot/kanal/
  effekt/VLAN/SSID/PPSK/firmware/CLI-write krever særskilt godkjenning med
  enhet, nåverdi, foreslått verdi, konsekvens, rollback, nedetid og
  bekreftelses-ID.
- **Kommunikasjon**: verifisert mottaker, vist utkast, eksplisitt
  godkjenning, send én gang, leveringsstatus + revisjons-ID. Fornavn alene
  er ikke nok ved flertydighet.
- **Kritiske låser/porter/alarmer**: styres aldri kun ved stemme.
