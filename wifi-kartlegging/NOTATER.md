# WiFi-kartlegging campingplass – status og notater

Sist oppdatert: 2026-07-28. Dette dokumentet sikrer informasjonen fra samtalen om
dekningskart for campingplassen, slik at arbeidet kan gjenopptas i en senere økt.

## Filer i denne mappen

| Fil | Innhold |
|---|---|
| `kart-med-tekst.png` | Kart med områdenavn, plassnummer og etiketter |
| `kart-rent.png` | Samme kart uten tekst – kun pins og områdelinje |
| `tegnforklaring.png` | Forklaring på pin-fargene |

## Tegnforklaring (utstyr)

- **Grønn pin** = AP460c
- **Gul pin** = Atom30
- **Blå pin** = 305-serie, montert inne i restaurant og kafé
- **Hvit pin** = 305-serie med utendørs 2 GHz-extender
- **Gul heltrukken linje** = området det ønskes wifi-signaler i (se viktig avklaring under)

## Områder og punkter markert på kartet

- `240–244` – øvre felt (nord på plassen)
- `TELT-området 301 til 342` – vestre del
- `101 til 119` – markert med turkis rektangel (sørøst, ved den rette gule streken)
- `120, 121, 122` – rekken like vest for 101–119
- Nedre toalett (2 GHz) – nordøst, ved hvit pin
- STOLPE – grønn pin midt på øvre felt
- Selvinnsjekk – grønn pin ved innkjøring/parkering vest
- Toalett og gazastripe – grønn pin sentralt
- Resepsjon, kafé og restaurant – sør, med blå pins (305-serie innendørs)

## Viktige avklaringer fra eier (28.07.2026)

1. **Den gule streken skal i utgangspunktet bort.** Spesielt den lange rette
   diagonale streken mot sørøst.
2. **Partiet midt inne i skogen kan sløyfes** – det skal IKKE være wifi-dekning
   inne i skogsområdet (øst/sørøst for plassene 101–119).
3. Dekningsbehovet gjelder selve campingarealet: feltene 240–244, teltområdet
   301–342, plassene 101–119 og 120–122, samt bygningene (toaletter,
   selvinnsjekk, resepsjon/kafé/restaurant).

## Designforbedringer til neste versjon av kartet

- Symbolet for «området» i tegnforklaringen (hvit stiplet omriss) matcher ikke
  kartet – bruk en bit av selve den gule linjen som symbol, eller fjern
  linjen helt iht. avklaring 1.
- Gul brukes både til områdelinje og Atom30-pin – vurder annen farge på
  områdelinjen hvis den beholdes.
- Små hvite etiketter drukner mot satellittbildet – legg mørk halvtransparent
  bakgrunnsplate bak teksten (samme stil som «101 til 119»-boksen).
- Hvit pin har lav kontrast mot hvite campingvogner – legg tynn mørk kant
  rundt pinnen.
- Beskjær utsnittet tettere rundt campingplassen, så tekst og pins kan
  gjøres 30–40 % større.
- Vurder å legge tegnforklaringen inn i et hjørne av kartet (plass nede til
  venstre), så alt er i én fil.
- Skriv «2,4 GHz» i stedet for «2Ghz» hvis det er 2,4 GHz-bandet som menes.
