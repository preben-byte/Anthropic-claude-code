# Marivold – forslag til dekningsplan (v1, til bekreftelse mot lagerliste)

Mål: 100 % dekning overalt der det ikke er skog.
Utstyrstyper: grønn = utendørs AP460c · hvit = 305-serie med 2,4 GHz
retningsantenne · blå = 305-serie innendørs · Atom30 i hyttene.

Alle posisjoner refererer til forslags-markørene F1–F7 i `naalkart-v4.html`
(turkise ruter). Ingenting av dette er bestilt eller besluttet – det er
forslaget eieren skal bekrefte/avkrefte mot lagerlisten.

## Prioritet 1: Sør-hullet (rødt felt – alt henger på Resepsjon, 84 % kanalbruk)

**F1 – NYTT utendørs AP460c ved lekeplassen/ballfeltet**
- Hvor: stolpe (gjerne lysstolpe) mellom 120–122 og 101–119, ved lekeplassen.
- Høyde: 4–6 m (over vogn-/bobiltak), svak nedtilt 5–10°.
- Dekker: hele 101–119, 120–122, ballfeltet og gressletta – i dag ligger alt
  dette i randsonen til Toalett-AP-et og Resepsjon.
- Kabel: kortest trasé er fra sanitærbygget (samme sted som Toalett/Gazastripe
  står kablet i kjede) langs veien østover, ca. 80–100 m utendørs cat6.
  Verifiser at kjede-switchen har ledig port/PoE-budsjett.

**F2 – NY hvit retningsløsning (305 + 2,4 GHz retningsantenne) på Resepsjonens sørgavl**
- Hvor: sørgavlen/sørhjørnet av resepsjonsbygget, over takrenne.
- Retning: sørøst, langs brygga og båtplassene, mot badeområdet.
- Effekt: avlaster Resepsjon-AP-et for de fjerneste klientene (bryggegjester og
  badeområdet er dagens 6 svake). Resepsjonens AP460c beholdes som den er og
  tar nærområdet.
- Kabel: kort innvendig trasé fra resepsjons-switchen, gjennom sørveggen.

## Prioritet 2: Splitt tvillingpunktet på sanitærbygget

**F3 – FLYTT Gazastripe-enheten til østgavlen (eller stolpe like øst for bygget)**
- I dag: Toalett + Gazastripe står på samme punkt (RF −46, kablet i kjede) –
  to enheter dekker samme luft, null gevinst.
- Flytt Gazastripe-enheten til motsatt gavl av sanitærbygget, retning øst/sørøst
  mot 101–119-siden. VIP-TV-en (−80) får dermed et mye nærmere AP.
- Kostnad: 0 nytt utstyr – kun kabelforlengelse langs/under takfot (10–20 m).

## Prioritet 3: Løft og vinkling (0 nytt utstyr)

**F4 – LØFT Selvinnsjekk-punktet og vinkle mastantennen mot teltområdet**
- AP460c på stolpen heves til 5–6 m hvis den står lavere i dag.
- 2,4 GHz-antennen på samme stolpe vinkles sørvest mot teltområdet 301–342
  (i dag har teltfeltet ingen egen dekning og ligger 150 m unna bak hytterekka).

**F5 – JUSTER retningsantennen på Nedre-Toalett**
- Sikt den hvite 2,4 GHz-retningsantennen mot 240–244-sløyfa (sørvest),
  montert over takhøyde med fri sikt. Nordfeltet har tre AP-er rundt seg –
  problemet der var kanalkaos, ikke antall (16 % CRC på Stolpe).

## Opsjoner – kun hvis målinger etter F1–F5 viser rest-hull

**F6 – OPSJON: AP460c (evt. ledig Atom) på hyttegavl mot teltfeltet 301–342**
- Bare hvis F4-vinklingen ikke løfter teltfeltet nok. Gavl på nærmeste hytte,
  retning vest over teltene. Kabel fra hyttens Atom-uttak hvis kablet.

**F7 – OPSJON: ekstra AP460c i nedre vognrekker (mellom Resepsjon og 120–122)**
- Bare hvis Resepsjon fortsatt ligger over ~60 % kanalbruk etter F1+F2.
  Stolpemontert midt i rekka.

## Kanal- og effektplan (gjøres i XIQ – ingen montering)

- 2,4 GHz: fast 1/6/11 med geografisk gjenbruk, f.eks. Nedre-Toalett 1,
  Stolpe 6, Selvinnsjekk 11, Toalett 1, Gazastripe (flyttet) 6, Resepsjon 11,
  F1 1, F2 6. Endelig tildeling settes i XIQ etter naboskapsmatrisen.
- Skru NED 2,4 GHz-effekten i resepsjonsbygget (Resepsjon + Restaurant + Kafé
  står i praksis i samme bygg og støyer på hverandre – bidrar til 84 %).
- 5 GHz: 40 MHz kanaler, full effekt ute.
- Dette er «2026-kanalplanen» som også fjerner CRC-feilen på Stolpe.

## Nytt utstyr planen krever (sjekkes mot lagerlisten)

| Tiltak | Utstyr | Antall |
|---|---|---|
| F1 | AP460c utendørs | 1 |
| F2 | 305-serie + 2,4 GHz retningsantenne | 1 |
| F3–F5 | ingenting nytt (flytt/løft/vinkle) | 0 |
| F6/F7 (opsjon) | AP460c | 0–2 |

Minimum: 1× AP460c + 1× 305/retningsantenne. Med opsjoner: inntil 3× AP460c.

## Åpne punkter

- Kartet viser 10 gule nåler; forrige økt talte 9 Atomer – bekreft antall.
- PoE-budsjett og ledige porter i kjeden ved sanitærbygget (for F1/F3).
- Er Atomene i hyttene kablet (relevant for F6-kabling)?
