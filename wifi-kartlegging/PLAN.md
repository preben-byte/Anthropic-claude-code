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

## Eierens utkast med airMAX (29.07.2026 – `kart-eier-utkast-airmax.png`)

Eier tegnet et utkast der kremgule nåler = Ubiquiti airMAX 5 GHz
basestasjoner (samme nålform som hvite 2,4 GHz-antenner):

- Nedre toalett → grønn AP460c (= F5 ✓). Sanitærbygg: grønn til vestgavl
  (= F3 ✓), hvit 2,4 står igjen, + 2× airMAX-baser (øst + sør).
- 2 nye grønne på hytterekka: fremste hytta (= F6 ✓) + nedre rekke (= F7).
- Resepsjon: 2 hvite 2,4-retningsantenner på nordsiden (mot 120–122).
- Selvinnsjekk og Resepsjon mistet de grønne (trolig gjenbrukt).

Vurdering (Claude):
- Enig i F5/F3/F6/F7-delene.
- ADVARSEL 1: Selvinnsjekk uten AP460c = nytt hull (5 svake, ankrer
  innkjøring/parkering/P1-sør). Behold den grønne der.
- ADVARSEL 2: 120–122 via 2,4-retning fra resepsjonen (200–250 m over
  vognrekkene) gir «fulle streker, dårlig fart» – klientene når ikke tilbake.
  F1 på stolpe ved lekeplassen er fortsatt riktig løsning.
- ANBEFALT ROLLE for airMAX: trådløs backhaul, ikke gjeste-AP. Base på
  sanitærbygget → CPE på F1-stolpen (sparer 80–100 m kabel); base nr. 2 kan
  mate F8 senere. airMAX styres utenfor XIQ (airOS/UISP), har ikke roaming
  med Extreme-nettet, og må låses til én fast 5 GHz-kanal som tas ut av
  XIQ sin auto-kanal-liste.

## Eierens utkast B: «nesten bare AP460c» (29.07.2026 – `kart-eier-utkast-460c.png`)

Innhold i utkastet (lest fra kartet):

- **6× AP460c:** Nedre toalett (byttet ✓), Stolpe, Selvinnsjekk (beholdt ✓),
  sanitærbyggets vestgavl (✓), fremste hytta (✓), Resepsjon (beholdt ✓).
- **2× airMAX 5 GHz-baser** på sanitærbygget (øst + sør) – eneste ikke-460c.
- **Alle hvite 2,4-retningsløsninger fjernet:** Selvinnsjekk-masten,
  Nedre toalett, sanitær-antennen, Vivendel-ext og resepsjonsantennene.
  Grønn i nedre hytterekke fra utkast A er også tatt bort.
- Blå 305 inne i restaurant/kafé og Atomene i hyttene som før.

Vurdering (Claude) – dette er det beste skjelettet så langt:

+ Ensartet: alt gjestenett på AP460c i XIQ, dobbelt bånd overalt, ekte
  roaming, enkel drift. Selvinnsjekk og Resepsjon beholder ankrene sine.
+ Utstyrsregnskap: dagens 5 grønne + tvillingen som frigjøres fra
  sanitærpunktet → trolig bare **1 ny AP460c** å kjøpe for å nå 6.
+ Frigjør alle 305/retningsantenner som reservelager.

− **Hull 1 (størst): 120–122 og 101–119 får ingenting nytt.** Eier har selv
  bekreftet at Resepsjonen ikke når dit. airMAX-basene peker den veien, men
  som gjestedekning er de feil verktøy (utenfor XIQ, ingen roaming, TDMA).
  → Løsning: behold utkast B og legg til F1-stolpen ved lekeplassen, matet
  av den ene airMAX-basen som backhaul. Da får airMAX-ene riktig jobb.
− **Hull 2: Vivendel fjernet** – 45-timersbrukeren (−75) mister sin nærmeste
  radio og faller tilbake på Resepsjon (~80 m). Anbefaling: la Vivendel stå
  til etter måling, den koster ingenting der den henger.
− P4 (teltfelt/hytterygger) bæres av fremste hytta alene – test etter
  montering; retningsantenne fra reservelageret kan suppleres ved behov.
− P1 står og faller på Stolpe-fiksen (F2) som før.

**Konklusjon utkast A vs B:** B vinner. B + F1(+backhaul) + Vivendel på nåde
= komplett plan. Estimert innkjøp: 1× AP460c + 1× AP460S12C (F1), resten
gjenbruk.

## Eierens utkast C: null-kjøp med retningsvalg (29.07.2026)

Filer: `kart-eier-utkast-nullkjop.png` (eierens plassering) og
`kart-retninger.jpg` (Claudes retningsvalg tegnet inn som sektorer).

Plassering (lest fra kartet): 5× AP460c omrokkert uten kjøp – Nedre toalett
(fra Selvinnsjekk), Stolpe, sanitærbyggets NORD- og SØR-gavl (tvillingene
splittet), Resepsjon. 4× hvite 2,4 GHz-retningsantenner utplassert uten
retning: 2 på Selvinnsjekk-stolpen, 1 midt i hytterekka, 1 på Vivendel-hytta.

### Retningsvalg (Claudes anbefaling)

| Antenne | Posisjon | Retning (asimut) | Mål | 2,4-kanal |
|---|---|---|---|---|
| W1 | Selvinnsjekk-stolpen, øverst | NNØ (~30°) | P1: vestveien og 240–244-sløyfa | 11 |
| W2 | Selvinnsjekk-stolpen, under W1 | SSV (~205°) | Teltfeltet 301–342 | 6 |
| W3 | Hytta midt i rekka | VSV (~255°) | Hytteryggene + teltfeltets sørdel (P4) | 1 |
| W4 | Vivendel-hytta | ØNØ (~70°) | Nedre vognrekker (F7-området) | 11 |

Grønne (omni): Nedre toalett kanal 1 · Stolpe 6 · sanitær-N 11 ·
sanitær-S 1 · Resepsjon 6. Nedtilt 5–10° på W1 (langt kast).

### Vurdering

+ Genialt utstyrsregnskap: 0 kjøp. Sanitær-splitten N/S er en god idé –
  nordgavlen tar P2-retningen, sørgavlen tar 120–122-retningen.
+ W2+W3 løser teltfelt + hytterygger (P4) i tospann.
+ W4 gir nedre vognrekker et løft og beholder nærdekning for
  45-timersbrukeren.
− Selvinnsjekk-kiosken selv står igjen med bare baksidelober fra W1/W2 –
  test innsjekk-opplevelsen på stedet; ev. flytt W2 10° mot vest.
− Alt det nye kastet er 2,4 GHz: dekning ja, fart måtelig. P1 får streker,
  men 5 GHz når ikke ut dit uten Stolpe-fiksen (F2 fortsatt kritisk).
− **101–119 og østre del av 120–122 er fremdeles tynnest.** Sanitær-S
  hjelper 120–122 (ca. 90 m åpen sikt), men 101–119 ligger 160–240 m unna
  alt. Det ENE kjøpet som fortsatt anbefales: AP460S12C på stolpe ved
  lekeplassen (F1). Ellers: aksepter kant-dekning der i sesong én og mål.

## Eierens utkast D: grønn i østfeltet (29.07.2026)

Filer: `kart-eier-utkast-D.png` (eierens plassering) og
`kart-retninger-v2.jpg` (Claudes sektorer + omni-sirkler tegnet inn).

Plassering: 4× AP460c – Nedre toalett (G1), Stolpe (G2), **NY: fritt i
østfeltet (G3, ca. px 923,2150)**, sanitærbyggets vestende (G4). 5× hvite
2,4-retningsantenner: 2 på Selvinnsjekk-stolpen (W1/W2), midt i hytterekka
(W3), Vivendel (W4), **NY: sanitærbyggets østside (W5)**. Resepsjonen har
INGEN uteradio igjen – kun de to blå 305 inne.

### Retninger og kanaler (Claudes valg)

| Radio | Retning (asimut) | Mål | 2,4-kanal |
|---|---|---|---|
| W1 Selvinnsjekk øvre | NNØ ~32° | P1: vestveien + 240–244 | 11 |
| W2 Selvinnsjekk nedre | SSV ~205° | Teltfeltet 301–342 | 6 |
| W3 hytterekka | VSV ~255° | Hytteryggene (P4) | 1 |
| W4 Vivendel | Ø ~88° | Nedre vognrekker + resepsjonsområdet | 11 |
| W5 sanitær-øst | ØSØ ~118° | 120–122 og 101–119 | 6 |
| G1 Nedre toalett (omni) | – | veikrysset/240-sløyfa nordøst | 1 |
| G2 Stolpe (omni, blind vest til F2-fiks) | – | østre nordfelt | 6 |
| G3 østfeltet (omni) | – | soner 201–264 øst + nordre 101–119 | 11 |
| G4 sanitær-vest (omni) | – | P2 mot Selvinnsjekk + bobilfeltet | 1 |

Finjustering i XIQ etter naboskap; W3(1) står 80 m fra G4(1) men peker
motsatt vei – bytt om ved behov.

### Vurdering

+ **Beste null-kjøps-dekningen så langt.** G3 i østfeltet er et smart trekk:
  endelig ekte dobbeltbånd midt i P3, og W5 forlenger mot 101–119.
  P1 (W1+G2-fiks), P2 (G4), P3 (G2+G3+W5), P4 (W2+W3) – alle truffet.
- **Prisen er resepsjonen:** ingen uteradio sør for hytterekka. Uteserveringen,
  forplassen og nærmeste vognrekke får bare W4-kanten og innendørs-305-ene
  gjennom veggen. Rødstiplet ring på tegningen.
- G3 i østfeltet trenger stolpe + strøm/kabel ute i feltet – sjekk om det
  finnes lysstolpe med strøm der; ellers er airMAX-backhaul fra
  sanitærbygget løsningen (radene fra utkast A).
- 101–119 sørende ligger fortsatt ytterst i W5-kastet – mål etter montering.

**Anbefaling:** kjør D, men sett inn én AP460c ved resepsjonen igjen hvis
lageret har (eller kjøp én – det er det ene kjøpet som gjenstår i D).
D + resepsjons-AP = den mest komplette planen av alle utkastene.

## Claudes ideal-oppsett (29.07.2026 – `kart-claude-ideal.jpg`)

Forutsetning fra eier: strømstolper med gatelys langs hele veinettet
(asfalt) – stolpemontering med strøm er mulig overalt langs vei.
Stolpe (AP-et) skal stå der det står. Null kjøp: 5 grønne + 5 hvite + 2 airMAX.

### AP460c (grønne, omni ~75 m nytteradius)

| # | Plassering | Rolle | Kanal |
|---|---|---|---|
| G1 | STOLPE (står, F2-fiks forutsatt) | østre nordfelt + midtre P3 | 6 |
| G2 | Selvinnsjekk-stolpen | innsjekk, parkering, P1-sør, telt-nord | 1 |
| G3 | Sanitærbygget (ett punkt, midt/tak) | P2, bobilfeltet, 120–122-vest | 11 |
| G4 | **Lysstolpe ved lekeplassen** (F1-punktet!) | 101–119, 120–122, P3-sør | 1 |
| G5 | Resepsjonen | forplass, uteservering, nærmeste rekker | 6 |

G4 = tvillingen som frigjøres fra sanitærbygget. Strøm fra lysstolpen;
data via **airMAX-link fra sanitærbygget** (150 px ≈ 60 m fri sikt, tegnet
turkis stiplet) – null graving. airMAX-base 2 = reserve.

### 2,4 GHz retningsantenner (hvite)

| # | Plassering | Retning | Mål | Kanal |
|---|---|---|---|---|
| W1 | Selvinnsjekk-stolpen | NNØ ~32° | P1-vestveien + 240–244 | 11 |
| W2 | Selvinnsjekk-stolpen | SSV ~205° | teltfeltet 301–342 | 6 |
| W3 | Nedre toalett | SV ~228° | 240-sløyfa + nordøstfeltet | 1 |
| W4 | Hytterekka midt | VSV ~255° | hytteryggene (P4) | 11 |
| W5 | Vivendel | Ø ~88° | nedre vognrekker | 6 |

W1 og W3 møtes midt på P1-stripa – hele langsiden dekket fra to kanter.

### Hvorfor dette er mitt oppsett

- Hvert prioritetsområde har en primærradio OG en sekundær: P1 (W1+W3+G1),
  P2 (G2+G3), P3 (G1+G3+G4), P4 (W2+W4). Ingen enkelt boks er lenger
  «ensom» slik Resepsjon var i RF-matrisen.
- G4 på lysstolpen løser det best dokumenterte hullet (101–119/120–122)
  med dobbeltbånd på kloss hold – og strømstolpene + airMAX gjør det gratis
  i infrastruktur.
- Resepsjonen beholder uteradio (G5) – ingen nye hull skapes.
- Nedre toalett trenger ikke omni: W3 kaster all energien inn i feltet i
  stedet for inn i skogen bak.
- Kanalene over er startverdier; finjuster i XIQ etter naboskapsmatrisen.

## KORREKSJON fra eier (29.07) + Claudes ideal-oppsett v2 (`kart-claude-ideal-v2.jpg`)

**Viktig faktakorreksjon:** Resepsjonen har INGEN utendørs enhet i dag – kun
to enheter INNE (de blå). Det betyr at «Resepsjon» i XIQ (6 svake, 84 %
kanalbruk) er en innendørs enhet som betjener uteområdet gjennom veggen.
Forklarer sør-hullet fullstendig. (Tidligere antagelse om grønn ute ved
resepsjonen var feil.)

Reell grønn-beholdning i dag: 4× AP460c = Selvinnsjekk, Stolpe, Toalett,
Gaza. Eier ser ikke poenget med grønn på Selvinnsjekk (enig: de 5 svake der
var gjester ute i feltene, som nå tas av W1/W2) – den frigjøres.

### Ideal v2 – tegnforklaring

- **Grønn sirkel** = AP460c utendørs (omni); enheten i sentrum, ~75 m radius.
- **Farget kjegle** = hvit 2,4 GHz retningsantenne (305); står i spissen,
  sender dit kjeglen peker. Farge kun for å skille: W1 rød, W2 blå,
  W3 oransje, W4 gul, W5 lilla.
- **Turkis stiplet** = airMAX 5 GHz punkt-til-punkt (kun backhaul til G3).
- **Blå nåler** = 305 inne i restaurant/kafé (uendret).

### Plassering (4 grønne – ingen kjøp)

| # | Enhet | Plassering | Kanal |
|---|---|---|---|
| G1 | AP460c (står) | Stolpe – F2-fiks forutsatt | 6 |
| G2 | AP460c (Toalett-tvilling 1) | Sanitærbygget, ett punkt | 11 |
| G3 | AP460c (Gaza-tvilling 2) | Lysstolpe ved lekeplassen; airMAX-matet | 1 |
| G4 | AP460c (fra Selvinnsjekk) | Resepsjonens NORDVEGG, ute | 6 |

G4 = første utendørs radio noensinne ved resepsjonen – tetter sør-hullet
ved kilden. W-antenner: W1 Selvinnsjekk→NNØ (11), W2 Selvinnsjekk→SSV
telt (6), W3 Nedre toalett→SV 240-sløyfa (1), W4 hytterekka→VSV rygger
(11), W5 lysstolpe nedre vognrekke→NØ over søndre 101–119/ballfeltet (6,
sømmen mellom G3 og G4; del kanal-finjustering i XIQ).

Svakeste punkt i v2 (bevisst valg): selve innkjøringen/parkeringen får kun
baksidelober fra W1/W2 – mål etter montering; behold ev. grønn der i stedet
for G4 hvis innsjekk-dekning viser seg viktigere enn sør-hullet.

## Åpne punkter

- Hva er den fysiske forklaringen på Stolpes blinde vestside? (Sjekkes ved
  F2-befaring – montering/skygge/retningsantenne.)
- Kartet viser 10 gule nåler; forrige økt talte 9 Atomer – bekreft antall.
- PoE-budsjett og ledige porter i kjeden ved sanitærbygget (for F1/F3).
- Er Atomene i hyttene kablet (relevant for F6-kabling)?
