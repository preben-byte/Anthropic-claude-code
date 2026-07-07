# Om InStay – og hva vi tar med oss inn i Marivolds gjesteportal

## Hva InStay egentlig er

InStay er en digital gjesteportal utviklet av det norske selskapet **Invite AS**
(visitinvite.com, med hovedkontor i Førde og avdeling i Stockholm). Portalen
åpnes av gjesten via en personlig lenke som sendes på SMS og e-post et par
dager før ankomst – ingen app å laste ned, ingen konto å opprette. Lenken
inneholder en engangsnøkkel som identifiserer gjesten og lar dem gå rett inn
i sitt eget skreddersydde reise-univers.

Der en tradisjonell resepsjon møter deg med kø, papirskjema og en plastnøkkel,
lar InStay hele oppholdet skje gjennom telefonen: booking-oversikt, digital
innsjekk, digital nøkkel til rom og fellesarealer, praktisk informasjon,
lokale anbefalinger, direkte chat med verten, mersalg, og til slutt en
tilbakemelding rett i lommen på gjesten. Alt sammen tilpasset hotellets eller
utleiestedets egen profil – i logo, farger og språk.

## Historien og posisjonen

Selskapet omtales med selvironi som «alt-i-én-digital-gjestereise»-plattform,
og listen med kunder er allerede tung: Radisson, Best Western, Forsvarsbygg,
Sammen, Hemavan, ETN og en rekke uavhengige hoteller, campingplasser,
hyttegrender og anleggshoteller i Norden. Størst er de i Norge og Sverige,
men de tar plass på det danske og tyske markedet også.

InStay er én av fire moduler i Invite-plattformen:

- **Invite InStay** – gjesteportalen
- **Invite Adgang** – digitale nøkler og adgangsstyring
- **Invite Energisparing** – smart temperaturstyring som følger bookingen
- **Invite Kontrollpanel** – det driftsrommet der resepsjonisten eller
  eieren styrer alt fra ett sted

De selger seg modulbasert: du velger de bitene du trenger, og skrur dem på
etter hvert som behovet vokser. Alt integrerer med de vanligste
bookingsystemene, låsleverandørene og betalingsløsningene i bransjen.

## Hva gjester faktisk møter

Når gjesten trykker på lenken, lander hun eller han i en portal som er
minimalistisk, snakkende og full av handlinger. De typiske «flatene» er:

1. **Forside / velkomst.** Bookingoversikt, navn, dato, rom/bolig og en
   tidslinje som viser hvor hun er i reisen: bekreftet → digital velkomst
   → innsjekk → nøkkel → utsjekk → tilbakemelding.
2. **Digital innsjekk.** Skjema med legitimasjon, signering av husregler,
   og tilbud om tidlig innsjekk mot et lite gebyr – det klassiske mersalget
   som ofte betaler for hele portalen alene.
3. **Digital nøkkel.** En stor «Åpne dør»-knapp på romdør, felles­innganger,
   bommer og badstuebrygga. Aktiveres til innsjekk-tidspunkt, deaktiveres
   ved utsjekk. Kan deles med medreisende.
4. **Ditt rom / bolig.** Info om selve boligen, hva som finnes ombord,
   hvordan man styrer termostaten, TV-en, peisen. Fjerner 8 av 10
   resepsjonsspørsmål før de blir stilt.
5. **Opplevelser.** Håndplukkede aktiviteter, restauranter, severdigheter
   og turer i nærområdet – ofte med direktebooking mot lokale
   partnere. Dette er der Invite skiller seg fra en trykt velkomstmappe.
6. **Shop / mersalg.** Frokost, spa, sen utsjekk, ekstra rengjøring,
   husdyravgift, transfer. Alt legges rett på oppholdet og
   samlefaktureres. Invite oppgir at riktig oppsatt shop kan øke
   omsetningen per gjest merkbart.
7. **Praktisk info.** WiFi (nettverk + passord + QR-kode), husregler,
   parkering, avfall, nødinformasjon, FAQ, bærekraft. Alt sammenslått
   til én lettleselig ressurs.
8. **Kontakt / meldinger.** Chat direkte med verten – ingen apper å
   laste ned. Statistikk fra Invite viser svartider på under 10 minutter
   som norm.
9. **Tilbakemelding.** NPS 0–10 og/eller 5-stjerners rangering, utløst
   ved utsjekk. 77 % svar-rate ifølge selskapet – hvilket er
   ekstremt høyt sammenlignet med tradisjonelle e-postspørreskjemaer.
10. **Språkbytte.** Norsk, engelsk, dansk, svensk, tysk – for uten språk
    er hele grepet dødt.

## Hvorfor det spiller en rolle

Grunnfortellingen deres er kort: **83 % av alle gjester vil ha
informasjon på telefonen.** Fra det følger resten – kortere kø,
tilfredsere gjester, mer mersalg, mindre nøkkeltap, mindre
energiforbruk (opptil 30 % via Energisparing-modulen), lavere
lønnskostnad, høyere anmeldelses-score. Frits Olufsen på Villa Havblikk
sier det slik: «Invite gir oss fleksibilitet. Spesielt overfor kunder
som ankommer utenfor hotellets åpningstider.»

Innsalgspoenget for eieren er altså ikke bare gjesteopplevelse –
det er drift. Kontrollpanelet fjerner én person i resepsjonen om
kvelden, én låsesmed når kortet er borte, og én tømmermann som
regulerer temperaturen manuelt mellom bookingene.

---

## Hvordan dette henger sammen med Marivold Gjesteportal

Filen `index.html` i dette repoet er en Marivold-versjon av
det samme grepet. Den demper Invite-fargene (mørk teal og dyp
gull), skriver innholdet på nordisk kysthospitalitet, og
setter alle modulene på plass:

| InStay-modul               | Tilsvarende i Marivold-portalen                                     |
|----------------------------|---------------------------------------------------------------------|
| Forside / booking          | `#hjem` – hero-kort med bookingref, tidslinje, hurtighandlinger    |
| Digital innsjekk           | `#innsjekk` – 3-stegs skjema, tidlig innsjekk-tillegg, signatur     |
| Digital nøkkel             | `#nokkel` – hoved-nøkkelkort, felles­dører, historikk, deling       |
| Ditt rom / bolig           | `#opphold` – boliginfo, fasiliteter, bookingoversikt, forleng       |
| Opplevelser                | `#opplevelser` – aktiviteter · restauranter · severdigheter · turer · familie · kart |
| Shop / mersalg             | `#shop` – frokost · spa · ekstra tjenester · lokale produkter · kurv |
| Praktisk info              | `#info` – WiFi · husregler · parkering · avfall · nød · FAQ · bærekraft |
| Kontakt / meldinger        | `#kontakt` – live chat, telefoner, adresse, meld problem            |
| Tilbakemelding / NPS       | `#tilbakemelding` – NPS 0–10, 5-stjerner, delrangering, kommentar   |
| Språkvelger (5 språk)      | Globe-ikon øverst til høyre                                         |
| Kontroll­panelets datalag  | Simulert i JS – shop-kurv, chat, digital nøkkel-status               |
| Merkevare-tilpasning       | Tre paletter forberedt via `data-theme` (lys/mørk/system)           |

**Undersider** åpnes gjennom pillene under hver seksjon
(f.eks. under Opplevelser: Aktiviteter / Restauranter /
Severdigheter / Turer / Familie / Kart), og **undersidens
underside** er modalvinduene som åpnes når du trykker på
et enkelt kort – med bilde-plassholder, pris, varighet,
inkludert-liste og en «Legg til på oppholdet»-knapp
som mater rett inn i handlekurven.

## Bruk

Åpne `index.html` direkte i nettleseren. Portalen bruker
ingen eksterne ressurser – alt (styling, ikoner via emoji,
JavaScript-logikk, flagg via CSS-gradienter) ligger i filen.
Den fungerer offline, i mørk og lys modus, og på både mobil
og desktop.

Videre steg er å bytte plassholder-innholdet (bilder, farger,
tekster, boliger, opplevelser, priser) mot ekte Marivold-data –
og koble portalen til bookingsystem, låsleverandør og
betalingsløsning når den skal produksjonssettes.
