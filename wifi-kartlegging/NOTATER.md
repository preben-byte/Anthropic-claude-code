# WiFi-kartlegging campingplass – status og notater

Sist oppdatert: 2026-07-28. Dette dokumentet sikrer informasjonen fra samtalen om
dekningskart for campingplassen, slik at arbeidet kan gjenopptas i en senere økt.

## Filer i denne mappen

| Fil | Innhold |
|---|---|
| `kart-med-tekst.png` | Kart med områdenavn, plassnummer og etiketter |
| `kart-rent.png` | Samme kart uten tekst – kun pins og områdelinje |
| `tegnforklaring.png` | Forklaring på pin-fargene |
| `naalkart-v4.html` | Interaktivt nålkart (zoom/panorér/trykk) bygget på hele satellittbildet, med fasit-posisjoner fra eierens kart + svake klienter per AP. Vivendel er markert ANTATT (stiplet) og trenger fasit. |

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

## Fasit-avklaringer fra eier (28.07.2026, kveld)

- **Vivendel-ext = den hvite nålen blant hyttene** – nærmest Atomene, mellom
  dem og Resepsjon (delvis skjult bak den gule linjen på kartet, ca. pixel
  483,2815 i fullskala-bildet). Ikke lenger antatt – FASIT.
- **Sonene 201–260/264 = alle umerkede felt** med campingvogner, dvs. hele
  resten av området innenfor den gule linjen som ikke har egen merking.
- **Dekningskrav: 100 % i hele det gult inngjerdede området** – fra
  Resepsjon mot 101–119, ved 240–244, ned mot Nedre toalett, og alt imellom.
- Åpent spørsmål: kartet ser ut til å ha 10 gule nåler, mens forrige økt
  talte ni Atomer – stemmer 10, eller er én av dem noe annet?

## Viktige avklaringer fra eier (28.07.2026)

1. **Den gule streken skal i utgangspunktet bort.** Spesielt den lange rette
   diagonale streken mot sørøst.
2. **Partiet midt inne i skogen kan sløyfes** – det skal IKKE være wifi-dekning
   inne i skogsområdet (øst/sørøst for plassene 101–119).
3. Dekningsbehovet gjelder selve campingarealet: feltene 240–244, teltområdet
   301–342, plassene 101–119 og 120–122, samt bygningene (toaletter,
   selvinnsjekk, resepsjon/kafé/restaurant).

## Gjenopprettet kontekst fra forrige samtale (XIQ-/RF-analyse)

Status fra forrige økt («Nålkart v3»), limt inn av eier 28.07.2026:

### Bekreftede AP-posisjoner (fasit)

- Fire posisjoner er fasit-bekreftet (merket FASIT i nålkart v3), pluss
  **Nedre-Toalett** (merket BEKREFTET).
- Alle gjettede posisjoner er fjernet fra nålkartet. Atomene (hyttene), Kafé,
  Restaurant, Gazastripe og Vivendel vises ikke igjen før eier gir fasit for dem.
- **Merk:** Kartene i denne mappen (opplastet 28.07.2026) inneholder trolig
  mye av denne fasiten: gule pins = Atom30 ved hyttene, blå pins = 305-serie
  i resepsjon/kafé/restaurant, grønn pin ved «Toalett og gazastripe», samt
  soner 101–119, 120–122 og telt 301–342. Vivendel er ikke merket på kartet.

### Tre hovedfunn fra analysen

1. **Sør-enden er hovedhullet (dobbelt bekreftet).** Resepsjon står alene
   nederst ved brygga med 6 svake klienter og 84 % kanalbruk, og RF-matrisen
   viste AP-en som «ensom». Alt sør for Toalett-bygget (nedre vognrekker,
   brygga, badeområdet) henger på ett eneste AP.
2. **Nordfeltet er godt dekket i teorien.** Stolpe midt i feltet, Selvinnsjekk
   i vest, Nedre-Toalett i nordøst – tre AP-er rundt teltområdet. Stolpes
   16 % CRC-feil på 2,4 GHz skyldes trolig kanalkaos (alle på 1/6/11 uten
   plan). Løses av 2026-kanalplanen, ikke av nye AP-er.
3. **XIQ-kartet var villedende.** Stolpe lå i feil ende av anlegget i XIQ.
   Planen er å laste opp eierens kartbilde som nytt kartunderlag i XIQ og
   plassere AP-ene etter fasit – først da blir XIQ sitt heatmap til å stole på.

### Tidligste steg: nålkart v1 («naalkart-svake-klienter.html»)

Første interaktive leveranse, bygget på XIQ-kartet (kun nordre halvdel, med
Stolpe-avviket dokumentert). Én nål per AP som bar svake klienter
(RSSI ≤ −75), farge = alvorlighetsgrad:

| AP | Svake klienter | Nivå |
|---|---|---|
| Resepsjon | 6 | 🔴 |
| Selvinnsjekk | 5 | 🔴 |
| Toalett (m/Gazastripe) | 4 | 🔴 (inkl. VIP-TV på −80) |
| Stolpe | 2 | 🟠 |
| Nedre-Toalett | 2 | 🟠 |
| Restaurant | 1 | 🟡 |
| Vivendel | 1 | 🟡 (45-timersbrukeren på −75) |
| Alle ni Atomene | 0 | 🟢 – hyttene er friske |

Presisjonsforbehold (viktig): en svak klient befinner seg i ytterkanten av
sitt AP sin dekning – nålen står på AP-et, ringen rundt er sannhetsområdet.
Uten posisjoneringsmotor finnes ikke gjestens eksakte punkt. Hullene som
avtegnet seg: feltet rundt Resepsjon og aksen Selvinnsjekk/Toalett/Stolpe –
uteområdene mellom bygningene.

Lovet sluttleveranse når tegning + lagerliste foreligger: sone-for-sone-plan –
hvilken bygning, hvilken vegg, hvilken høyde, hvilken retning, hvilken
kabeltrasé, med utstyret fra lagerlisten først.

### Tidligere steg: Nålkart v2 (ANTATTE posisjoner – delvis overstyrt av v3-fasit)

Anlegget heter **Marivold** (XIQ-kartforslag: «Marivold_hele», kartbilde
1883×4096 px). Alle nåler i v2 var merket ANTATT, resonnert fra
bygningslogikk + RF-nabomatrisen fordi XIQ-kartet ikke ga fasit.
Klienttall i parentes = svake klienter på måletidspunktet.

- **Innkjørsel/parkering (vest):** Resepsjon (6 svake), Selvinnsjekk +
  2 GHz-masten (5 svake – RF beviser at de to står på samme stolpe),
  Restaurant og Kafé i bygningsklyngen ved siden av.
- **Veikrysset nordøst for teltfeltet:** Nedre-Toalett (2 svake) – RF sier den
  hører Selvinnsjekk best, derfor plassert der og ikke ved store sanitærbygget.
  *(Senere BEKREFTET i v3.)*
- **Store sanitærbygget (midt):** Toalett + Gazastripe (4 svake, inkl.
  VIP-TV-en) – RF −46 og kablet i kjede; de står på samme punkt.
- **Mot brygga i sør:** Stolpe (2 svake) – lå utenfor XIQ-rammen.
  *(OBS: Overstyrt av fasit – Stolpe står i virkeligheten midt i nordfeltet,
  jf. v3-funn 2 og eierens kart.)*
- **Hytterekkene (vest-midt):** alle ni Atomene, 0 svake klienter – hyttene
  er friske.
- **Øst ved sjøen:** Vivendel-ext (med 45-timersbrukeren) – fortsatt ANTATT,
  mangler fasit fra eier.

### XIQ: bytte av kartunderlag (plan fra forrige økt)

- **Anbefalt (trygg) måte:** last opp eierens kartbilde som NYTT kart
  («Marivold_hele») i Manage → Real Time Maps/Planning, ved siden av det
  gamle – ingenting ødelegges, det gamle halv-kartet beholdes som backup.
  Deretter dras AP-ene på plass med nålkartet/fasiten som referanse.
- Alternativ: bytte bakgrunnsbildet på dagens kart direkte, men da mistes det
  gamle underlaget umiddelbart.
- Avgrensning avtalt: kun opplasting og AP-plassering – ingen
  policy-/deploy-endringer i portalen.

### Neste steg (avtalt i forrige økt)

1. Fasit-prikker for resten: Atomene (hyttene), Kafé, Restaurant, Gazastripe,
   Vivendel – pluss omtrentlig soneinndeling (101–119, 120–122, 201–260/264,
   telt, 301–342). *Kartene i denne mappen dekker trolig det meste av dette.*
2. Laste opp kartbildet som nytt kartunderlag i XIQ (trygt, ved siden av det
   gamle).
3. Lagerliste fra eier, for å beregne om sør-hullet ved Resepsjon kan tettes
   med utstyr som allerede eies.

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
