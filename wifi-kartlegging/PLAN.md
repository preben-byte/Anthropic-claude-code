# Marivold – forslag til dekningsplan (v2, til bekreftelse mot lagerliste)

Mål: 100 % dekning overalt der det ikke er skog.
Utstyrstyper: grønn = utendørs AP460c · hvit = 305-serie med 2,4 GHz
retningsantenne · blå = 305-serie innendørs · Atom30 i hyttene.

Forslagene F1–F9 ligger som turkise ruter i `naalkart-v4.html`, og eierens
prioriterte områder som lilla felt P1–P4. Ingenting er besluttet – planen
skal bekreftes/avkreftes mot lagerlisten.

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

**F3 – FLYTT Gazastripe-enheten til østgavlen av sanitærbygget**
- I dag står Toalett + Gazastripe på samme punkt (RF −46) – null gevinst.
- Ny plass: østgavlen (eller stolpe like øst), retning sørøst mot 101–119 –
  midtre del av P3. VIP-TV-en (−80) får et nært AP.
- Kabel: 10–20 m forlengelse langs takfot.

**F4 – LØFT Selvinnsjekk + vinkle mast-antennen**
- AP460c heves til 5–6 m. Dekker da P2 (gapet mot Toalett) og nedre del av
  P1 bedre. 2,4 GHz-antennen på samme stolpe vinkles sørvest mot
  teltfeltet/hytteryggene (P4-støtte).

**F5 – JUSTER retningsantennen på Nedre-Toalett**
- Sikt den sørvest inn langs 240–244-sløyfa (øvre ende av P1), over
  takhøyde med fri sikt.

## Prioritet 2 – nytt utstyr

**F1 – NYTT AP460c ved lekeplassen/ballfeltet**
- Stolpe mellom 120–122 og 101–119, høyde 4–6 m, nedtilt 5–10°.
- Dekker 101–119, 120–122 og nedre ende av P3 («helt ned til 119»).
- Kabel: ca. 80–100 m cat6 fra kjede-switchen i sanitærbygget.

**F6 – NYTT AP på ryggen av hytterekka (P4)**
- Atomene sitter inne i hyttene og kommer ikke gjennom bakveggen – derfor er
  hytteryggene/teltsiden mørk selv om hyttene er friske.
- Monter AP460c på vestveggen/baksiden av en hytte midt i rekka, retning vest
  over teltfeltet 301–342. Alternativ hvis lageret har: 305-serie med 2,4 GHz
  retningsantenne samme sted.
- Kabel: fra hyttens Atom-uttak hvis hyttene er kablet (åpent spørsmål).

## Opsjoner – kun ved rest-hull etter måling

- **F7:** ekstra AP460c i nedre vognrekker, hvis Resepsjon fortsatt >~60 %
  kanalbruk etter F1.
- **F8:** AP460c på stolpe midt på vest-langsiden (mellom 240–244 og
  Selvinnsjekk) – bare hvis F2 (Stolpe-fiksen) ikke gjenoppretter vestsiden.
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
| F2–F5 | ingenting nytt (fiks/flytt/løft/vinkle) | 0 |
| F1 | AP460c utendørs | 1 |
| F6 | AP460c (evt. 305 + 2,4 GHz retningsantenne) | 1 |
| F7/F8 (opsjon) | AP460c | 0–2 |
| F9 (nedprioritert) | 305 + retningsantenne | 0–1 |

Minimum: **2× AP460c** (F1 + F6). Med alle opsjoner: inntil 4× AP460c + 1× 305-sett.

## Åpne punkter

- Hva er den fysiske forklaringen på Stolpes blinde vestside? (Sjekkes ved
  F2-befaring – montering/skygge/retningsantenne.)
- Kartet viser 10 gule nåler; forrige økt talte 9 Atomer – bekreft antall.
- PoE-budsjett og ledige porter i kjeden ved sanitærbygget (for F1/F3).
- Er Atomene i hyttene kablet (relevant for F6-kabling)?
