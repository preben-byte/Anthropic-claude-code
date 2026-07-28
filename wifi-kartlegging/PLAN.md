# Marivold – forslag til dekningsplan (v3, til bekreftelse mot lagerliste)

Mål: 100 % dekning overalt der det ikke er skog.
Utstyrstyper: grønn = utendørs AP460c · hvit = 305-serie med 2,4 GHz
retningsantenne · blå = 305-serie innendørs · Atom30 i hyttene.

Forslagene F1–F9 ligger som turkise ruter i `naalkart-v4.html`, og eierens
prioriterte områder som lilla felt P1–P4. Ingenting er besluttet – planen
skal bekreftes/avkreftes mot lagerlisten.

## Retningsalternativer til AP460c (eiers spørsmål: «noe som sender fremover, ikke omni?»)

Ja – i samme familie, samme XIQ-administrasjon:

- **AP460S6C** – AP460c-plattformen med innebygd **60° sektorantenne**: smal
  stråle, lang rekkevidde. Ideell for smale striper som P1 (vest-langsiden)
  og F8.
- **AP460S12C** – samme med **120° sektor**: bred vifte fremover, ingenting
  bakover. Ideell på gavlvegg/stolpe i kanten av et felt (F1, F6) – og
  passer kravet om at ingenting skal kastes inn i skogen.
- Ett hakk opp: **AP5050D** – utendørs Wi-Fi 6E med innebygd retningsantenne.
  Dyrere og krever nyere lisens; sjekk pris/tilgjengelighet hos leverandør.
  (Modellutvalget endrer seg – be leverandøren bekrefte hva som er gjeldende
  utendørs sektor-modeller i XIQ-porteføljen nå.)

Tommelfinger: omni (AP460c) midt i et felt – sektor (S6C/S12C) i kanten av
et felt eller langs en stripe.

## Eierens feltobservasjoner (28.07.2026, sen kveld)

- Resepsjonen dekker bra lokalt, men når IKKE opp til 120/121/122 → F1.
- Gaza dekker bobilfeltet bra → Gaza blir stående; det er Toalett-enheten
  som er feilplassert på tvillingpunktet → F3 revidert.
- Toalett-enhetens bidrag er usikkert → flyttes til motsatt gavl (F3).
- Stolpe har alltid mange klienter → bærer østsiden alene; F2 enda viktigere.
- Eier vurderer montering på den fremste hytta (Atom30 nærmest øvre
  toalett) → F6 flyttet dit.
- Eiers idé: bytte retningsløsningen på Nedre-Toalett mot AP460c → F5
  revidert til bytte + gjenbruk av retningsantennen på F6.

## Eierens prioriterte områder (28.07.2026)

- **P1 – Vest-langsiden:** hele langsiden fra 240–244 og helt ned til
  Selvinnsjekk.
- **P2 – Mellom Toalett og Selvinnsjekk.**
- **P3 – «Klokka fem» fra Stolpe:** skrått sørover fra Stolpe og helt ned
  til plass 119.
- **P4 – Hytteryggene:** baksiden av hytterekka som vender mot teltområdet.
- **Nedprioritert:** badeområdet og brygga.
- **Kjent feil:** Stolpe dekker ingenting på sin venstre/vestlige side –
  årsak ukjent. (Forklarer langt på vei P1- og P3-hullene: Stolpe står midt
  i feltet og skulle tatt mye av dette.)

## Prioritet 1 – gjenopprett det som skulle virket (0 nytt utstyr)

**F2 – FIKS Stolpes blinde vestside**
- Sjekk montering først: henger AP-et på østsiden av stolpen/masten, skygger
  selve stolpen hele vestsiden – vanligste årsak til et «halvt» AP. Remonter
  på toppen eller vestsiden, eller drei enheten. Sjekk samtidig om det sitter
  en retningsantenne der uten at det er meningen.
- Gevinst: øvre del av P1 og hele øvre del av P3.

**F3 – FLYTT Toalett-enheten til motsatt gavl (Gaza blir stående)**
- Gaza dekker bobilfeltet bra og røres ikke. Toalett-enheten står oppå Gaza
  (RF −46, null gevinst) og er den som flyttes.
- Ny plass: motsatt gavl av sanitærbygget, retning nordvest mot
  Selvinnsjekk-gapet (P2).
- Kabel: 10–20 m forlengelse langs takfot.

**F4 – LØFT Selvinnsjekk + vinkle mast-antennen**
- AP460c heves til 5–6 m. Dekker da P2 (gapet mot Toalett) og nedre del av
  P1 bedre. 2,4 GHz-antennen på samme stolpe vinkles sørvest mot
  teltfeltet/hytteryggene (P4-støtte).

**F5 – BYTT: AP460c inn på Nedre-Toalett (eiers idé – anbefales)**
- Nedre-Toalett står i et veikryss og skal dekke til alle kanter – der
  passer omni (AP460c) bedre enn dagens 305 + retningsantenne.
- Den frigjorte retningsløsningen GJENBRUKES på F6 (hytteryggen).
- Krever 1× AP460c fra lager.

## Prioritet 2 – nytt utstyr

**F1 – NYTT AP ved lekeplassen/ballfeltet**
- Stolpe mellom 120–122 og 101–119, høyde 4–6 m, nedtilt 5–10°.
- Dekker 101–119, 120–122 og nedre ende av P3 («helt ned til 119») –
  bekreftet hull: Resepsjonen når ikke opp hit.
- Beste valg: AP460S12C (120° sektor) siktet nordvest, så ingenting går inn
  i skogen bak. AP460c (omni) fungerer også.
- Kabel: ca. 80–100 m cat6 fra kjede-switchen i sanitærbygget.

**F6 – Fremste hytta: hytteryggene + teltfeltet (P4)**
- Eiers plassering: den fremste hytta, der Atom30 sitter nærmest øvre
  toalett. Atomene inne i hyttene kommer ikke gjennom bakveggen – derfor er
  ryggsiden mørk.
- Monter på vestveggen/bakhjørnet, siktet sørvest LANGS baksiden av
  hytterekka og ut over teltfeltet 301–342.
- Utstyr: den frigjorte 305 + 2,4 GHz-retningsantennen fra F5-byttet
  (retningsantenne langs en rekke er perfekt bruk). Alternativ: AP460S12C.
- Kabel: fra hyttas Atom-uttak hvis hyttene er kablet (åpent spørsmål).

## Opsjoner – kun ved rest-hull etter måling

- **F7:** ekstra AP460c i nedre vognrekker, hvis Resepsjon fortsatt >~60 %
  kanalbruk etter F1.
- **F8:** sektor-AP (helst AP460S6C – 60° smal stråle langs P1-stripa) på
  stolpe midt på vest-langsiden – bare hvis F2 (Stolpe-fiksen) ikke
  gjenoppretter vestsiden.
- **F9 (nedprioritert av eier):** 305 + retningsantenne på Resepsjonens
  sørgavl mot brygga/badeområdet – kun hvis det blir aktuelt senere.

## Kanal- og effektplan (gjøres i XIQ – ingen montering)

- 2,4 GHz: fast 1/6/11 med geografisk gjenbruk; endelig tildeling settes i
  XIQ etter naboskapsmatrisen når F-tiltakene er gjort.
- Skru NED 2,4 GHz-effekten i resepsjonsbygget (Resepsjon + Restaurant +
  Kafé i samme bygg støyer på hverandre – bidrar til 84 % kanalbruk).
- 5 GHz: 40 MHz kanaler, full effekt ute.
- Dette er «2026-kanalplanen» som også fjerner CRC-feilen på Stolpe.

## Nytt utstyr planen krever (sjekkes mot lagerlisten)

| Tiltak | Utstyr | Antall |
|---|---|---|
| F2, F3, F4 | ingenting nytt (fiks/flytt/løft) | 0 |
| F1 | AP460S12C (helst) eller AP460c | 1 |
| F5 | AP460c (frigjør 305+retning) | 1 |
| F6 | gjenbrukt 305+retning fra F5 | 0 |
| F7/F8 (opsjon) | AP460c / AP460S6C | 0–2 |
| F9 (nedprioritert) | 305 + retningsantenne | 0–1 |

Minimum nytt: **2 enheter** – 1 til F1 (helst S12C-sektor) + 1 AP460c til
F5-byttet; F6 blir da gratis (gjenbruk). Med alle opsjoner: inntil 4.

## Åpne punkter

- Hva er den fysiske forklaringen på Stolpes blinde vestside? (Sjekkes ved
  F2-befaring – montering/skygge/retningsantenne.)
- Kartet viser 10 gule nåler; forrige økt talte 9 Atomer – bekreft antall.
- PoE-budsjett og ledige porter i kjeden ved sanitærbygget (for F1/F3).
- Er Atomene i hyttene kablet (relevant for F6-kabling)?
