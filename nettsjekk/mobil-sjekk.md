# mobil-sjekk.md — nettsjekk fra mobilen (Adm-nett)

| | |
|---|---|
| **Navn** | mobil-sjekk.md (del av nettsjekk-settet sammen med sjekk-klient.sh / sjekk-klient.ps1, roaming-logg.sh / roaming-logg.ps1, infra-sjekkliste.md og README.md) |
| **Formål** | Det du kan gjøre *akkurat nå* fra en mobiltelefon som står på Adm-nett på Marivold Camping. Chatten kan ikke nå det lokale nettet selv, så telefonen er måleinstrumentet: enten kjører den de ekte skriptene (Android/Termux), eller du bruker innebygde Wi-Fi-detaljer, apper og en manuell 15-minutters runde. Resultatet limes inn i chatten for analyse. |
| **Kjøring (eksempel)** | Android/Termux: `bash sjekk-klient.sh --forventet-ned 300 --interne-navn 10.0.0.1,10.0.0.2` og deretter `bash roaming-logg.sh` mens du går. Uten Termux: følg del 1b / del 2 og fyll ut malen i del 3. |
| **Krav** | En telefon på SSID «Adm-nett». Android: Termux + Termux:API fra F-Droid (valgfritt, for å kjøre skriptene). iPhone/iPad: kun gratisapper. Abonnementshastigheten (Mbit/s ned/opp) fra fiberavtalen er nyttig å ha for hånden. |
| **Versjon** | Versjon 1.0 — 2026-09-09 |
| **Prinsipp** | Endrer ingenting — kun lesing og målinger. Ingen innstillinger på telefonen, AP-ene, svitsjen eller brannmuren skal endres underveis; skriv ned det du ser, og la endringer vente til analysen er gjort. |

Innhold:

1. [Android](#1-android) — 1a kjør de ekte skriptene i Termux, 1b uten Termux (Wi-Fi-detaljer og apper)
2. [iPhone og iPad](#2-iphone-og-ipad)
3. [15-minutters manuell runde (alle telefoner)](#3-15-minutters-manuell-runde-alle-telefoner) med mal for resultater
4. [Hva du limer inn i chatten, og hva som analyseres](#4-hva-du-limer-inn-i-chatten-og-hva-som-analyseres)
5. [Det telefonen ikke ser](#5-det-telefonen-ikke-ser)

Terskler som brukes i hele settet (samme som i skriptene og infra-sjekkliste.md):

| Måling | PASS | WARN | FAIL |
|---|---|---|---|
| Wi-Fi RSSI | ≥ −65 dBm | ≥ −72 dBm | < −72 dBm |
| SNR (der støy vises) | ≥ 25 dB | ≥ 15 dB | < 15 dB |
| Bånd | 5 GHz / 6 GHz | 2,4 GHz (Adm-nett bør bruke 5/6 GHz) | — |
| Gateway-RTT (snitt) | ≤ 10 ms | ≤ 30 ms | > 30 ms |
| Internett-RTT (1.1.1.1 / 8.8.8.8) | ≤ 25 ms | ≤ 60 ms | > 60 ms |
| Hastighet mot abonnement | ≥ 80 % | ≥ 50 % | < 50 % |
| Video (segment-gjennomstrømning) | ≥ 25 Mbit/s (4K-margin) | ≥ 8 Mbit/s (1080p) | < 8 Mbit/s |
| DNS-oppslag (median) | < 50 ms | < 150 ms | ≥ 150 ms eller feil |
| DHCP | vanlig lease | lease < 10 min | 169.254.x.x-adresse |

---

## 1. Android

### 1a. Kjør de ekte skriptene i Termux

Dette gir den samme rapporten som fra en PC (alle 13 seksjoner, Markdown + JSON), og roaming-loggen kan kjøres mens du går rundt på området.

**Trinn 1 — installer Termux og Termux:API fra F-Droid.**
Bruk F-Droid (https://f-droid.org), ikke Google Play: Play-utgaven av Termux er utdatert og får ikke oppdateringer. Begge appene må komme fra samme kilde (F-Droid), ellers nekter de å snakke sammen.

- Termux (terminalen)
- Termux:API (broen til Wi-Fi-info, utklippstavle og deling)

**Trinn 2 — installer pakkene.** Åpne Termux og lim inn:

```bash
pkg update && pkg install git termux-api iputils traceroute dnsutils curl python jq
```

Svar «Y»/Enter på spørsmålene. `iputils` gir `ping`, `dnsutils` gir `dig`/`nslookup`, `termux-api` gir kommandoene `termux-wifi-connectioninfo`, `termux-clipboard-set` og `termux-share`.

**Trinn 3 — gi Termux:API tilgang til posisjon.** Android gir ikke ut SSID/BSSID/RSSI til apper uten posisjonstillatelse.

- Innstillinger → Apper → Termux:API → Tillatelser → Posisjon → «Tillat» (velg «Bare mens appen er i bruk» eller «Alltid»). Får du spørsmål om «Enheter i nærheten», tillat det også.
- Stedstjenester (GPS-bryteren i hurtigpanelet) må være på mens du måler.
- Test: `termux-wifi-connectioninfo` skal skrive ut JSON med `ssid`, `bssid`, `rssi`, `frequency_mhz` og `link_speed_mbps`. Står det `<unknown ssid>` eller `rssi: -127`, mangler posisjonstillatelsen.

**Trinn 4 — hent settet og kjør klientsjekken.** Bytt ut `<ditt abonnement>` med nedlastingshastigheten i fiberavtalen (Mbit/s), og `<gateway-ip>,<svitsj-ip>` med IP-adressene til brannmuren og svitsjen i trafokiosken (de interne navnene/adressene du vil ha pinget og navneoppslått i seksjon 4 og 5).

```bash
git clone https://github.com/preben-byte/Anthropic-claude-code.git && cd Anthropic-claude-code/nettsjekk && bash sjekk-klient.sh --forventet-ned <ditt abonnement> --interne-navn <gateway-ip>,<svitsj-ip>
```

Eksempel med tall (bytt til dine egne):

```bash
bash sjekk-klient.sh --forventet-ned 300 --forventet-opp 300 --interne-navn 10.0.0.1,10.0.0.2
```

- Er repoet privat, bruk et personlig tilgangstoken fra GitHub som passord ved `git clone`, eller last ned ZIP fra GitHub i nettleseren og pakk ut i `~/storage/shared/Download` (se trinn 6 for `termux-setup-storage`).
- Har du dårlig tid: `bash sjekk-klient.sh --hurtig` hopper over seksjon 8, 9 og 10 (hastighet, bufferbloat, video) og er ferdig på under 2 minutter. Full kjøring tar under 6 minutter.
- Skjermen bør holdes på under kjøringen. Android kan ellers sette Termux på pause, og målingene får hull. Hold telefonen i ro på ett sted under hastighets- og bufferbloat-målingen.
- Forventede [SKIP]/[INFO]-linjer på Android: DHCP-server og konfigurerte DNS-resolvere er ikke lesbare for apper på Android 8 og nyere (skriptet sier fra og henviser til Wi-Fi-detaljskjermen, se 1b). `dig` i Termux bruker sin egen resolv.conf (8.8.8.8), ikke Android sin DNS. Traceroute kan gi færre hopp enn på PC. Det er greit — resten av rapporten er fullverdig.

**Trinn 5 — roaming-logg mens du går.** Start loggen, ikke lås skjermen (hold Termux i forgrunnen), og gå rundt hele området i 10–15 minutter — forbi alle AP-er, inn i resepsjonen, bort til trafokiosken og ut til ytterpunktene. Ctrl-C (tastene «CTRL» + «c» på Termux-tastaturet) avslutter når som helst og skriver oppsummeringen.

```bash
bash roaming-logg.sh
```

Valgfritt: `bash roaming-logg.sh --varighet 900 --intervall 1` for 15 minutter med ett punkt per sekund. Loggen viser SSID, BSSID (hvilken AP), kanal, bånd, RSSI og gateway-ping per sekund, oppdager hvert AP-bytte (roam), måler avbruddet rundt byttet og finner «sticky client»-episoder (telefonen henger igjen på en AP med dårlig signal). Mangler `termux-wifi-connectioninfo`, gir skriptet [SKIP] på Wi-Fi-delen — bruk da WiFiman (1b) som Wi-Fi-kilde og noter for hånd.

**Trinn 6 — få rapporten ut av Termux.** Rapportene heter `nettsjekk-rapport-<host>-<YYYYMMDD-HHMMSS>.md` og `.json` og ligger i mappen du kjørte fra (eller i `--rapportmappe`). Velg én av disse veiene:

- *Del direkte til chat-appen:* `termux-share -a send nettsjekk-rapport-*.md` (åpner Android sin delingsmeny — velg Claude-appen, e-post eller en meldingsapp).
- *Kopier til utklippstavlen:* `termux-clipboard-set < nettsjekk-rapport-*.md` og lim inn i chatten. Er rapporten svært lang, lim inn seksjon for seksjon.
- *Legg den i Nedlastinger:* kjør `termux-setup-storage` én gang (godta lagringstilgang), deretter `cp nettsjekk-rapport-* ~/storage/shared/Download/`. Da kan du åpne filen fra Filer-appen eller vedlegge den i chatten. Tips: `bash sjekk-klient.sh --rapportmappe ~/storage/shared/Download` skriver rapporten rett dit.
- *Nødløsning:* `cat nettsjekk-rapport-*.md`, hold fingeren på skjermen i Termux, velg «Select»/marker alt og kopier.

Roaming-loggen skriver på samme måte en CSV-logg og en Markdown-oppsummering i rapportmappen — del begge.

### 1b. Uten Termux: Wi-Fi-detaljer og apper

**Innebygd Wi-Fi-detaljskjerm.** Innstillinger → Wi-Fi (på noen telefoner: Nettverk og internett → Internett) → trykk på tannhjulet eller pilen ved «Adm-nett». Noter:

- Frekvens/bånd (2,4 GHz eller 5 GHz — Adm-nett skal helst være på 5 GHz; 6 GHz vises som «6 GHz» på telefoner som støtter det)
- Overføringshastighet / linkhastighet (Tx/Rx i Mbit/s — dette er PHY-raten, ikke den reelle hastigheten)
- Signalstyrke (stock Android viser bare «Utmerket/God/Middels» — for dBm-verdi trenger du WiFiman nedenfor)
- Under «Avansert»/«Nettverksdetaljer»: IP-adresse, gateway, nettmaske, DNS-servere, MAC-adresse som brukes. Lease-tid vises bare på noen produsenters telefoner; noter den om den finnes.
- **Tilfeldig MAC-adresse:** i det samme nettverkets innstillinger under «Personvern» står valget «Bruk tilfeldig MAC-adresse» (standard) eller «Bruk enhetens MAC-adresse». Med tilfeldig MAC får telefonen en annen MAC per SSID enn den fysiske, og en DHCP-reservasjon på Adm-nett som er laget på den fysiske MAC-adressen vil ikke treffe — telefonen får da en adresse fra det vanlige DHCP-området. Noter hvilket valg som er aktivt og hvilken MAC som vises; ikke endre det nå.

**Apper (alle gratis eller med gratis grunnfunksjoner):**

| App | Bruk den til |
|---|---|
| **WiFiman** (Ubiquiti) | Leverandørnøytral og gratis. Fanen for Wi-Fi viser RSSI i dBm, kanal, båndbredde, BSSID (hvilken AP du står på) og linkhastighet — live, så du ser byttene mens du går. Har hastighetstest og LAN-skanning (finner IP/MAC på svitsj, brannmur, AP-er og andre enheter på Adm-nett). Dette er den viktigste appen for del 3. |
| **Speedtest by Ookla** | Hastighet ned/opp, ping og jitter. Velg samme server hver gang (helst en norsk, f.eks. i Oslo/Kristiansand) så tallene kan sammenlignes. |
| **PingTools Network Utilities** | Ping mot gateway, 1.1.1.1 og 8.8.8.8 med 20 pakker (gir snitt/maks/tap), traceroute (hopp 2 = første hopp utenfor brannmuren), DNS-oppslag, portsjekk (TCP 443 mot extremecloudiq.com og redirector.aerohive.com — det AP-ene trenger mot XIQ), LAN-skanning. |
| **ExtremeCloud IQ Companion** (Extreme Networks) | Extremes egen app for XIQ. Logg inn med XIQ-kontoen og se AP-enes status (tilkoblet/frakoblet mot skyen, klienter, alarmer) fra telefonen — nyttig for å se om en AP mistet CAPWAP samtidig som du opplevde problemer. |

**To raske portal-/kapringssjekker i nettleseren** (skal gjøres på Adm-nett):

- http://captive.apple.com/hotspot-detect.html skal vise teksten «Success» (ren side).
- http://connectivitycheck.gstatic.com/generate_204 skal gi en helt tom side (HTTP 204). Får du en innloggingsside, omdirigering eller feilside, er det en fangeportal, proxy eller DNS-kapring i veien — noter det.

## 2. iPhone og iPad

**Innebygde detaljer.** Innstillinger → Wi-Fi → trykk på (i) ved «Adm-nett». Noter:

- IP-adresse, nettverksmaske, **Ruter** (= gateway) og **DNS** (under «Konfigurer DNS»: står den på «Automatisk», er DNS det DHCP delte ut — noter adressene som vises).
- **Privat Wi-Fi-adresse**: av/på (på iOS 18 og nyere: «Av», «Fast» eller «Roterende»). Samme virkning som tilfeldig MAC på Android — en DHCP-reservasjon på fysisk MAC treffer ikke når denne er på. Noter «Wi-Fi-adresse» som vises. Ikke endre valget nå.
- Knappen **«Forny leie»** fornyer DHCP-leasen — *ikke* trykk på den under målingen (settet er lese-bare). iOS viser ikke lease-tiden som tall.
- iOS viser ikke RSSI, kanal eller BSSID her — det får du fra AirPort-verktøy nedenfor.

**AirPort-verktøy (Apple) med Wi-Fi-skanner** — den beste gratis Wi-Fi-skanneren på iOS, selv om Apple ikke lenger selger AirPort-utstyr (appen finnes fortsatt i App Store):

1. Installer «AirPort-verktøy» (AirPort Utility) fra App Store.
2. Innstillinger → bla ned til «AirPort-verktøy» → slå på «Wi-Fi-skanner» (Wi-Fi Scanner).
3. Åpne appen og trykk «Wi-Fi-skann» (Wi-Fi Scan) øverst til høyre → «Skann». Listen viser alle synlige nettverk med BSSID, kanal og RSSI i dBm, og oppdateres mens du går. Nettverket du er koblet til, står også der — det er den raden du noterer i del 3. Skanningen kan settes til å gå kontinuerlig; tidsstempel vises per rad.

**Andre apper:**

| App | Bruk den til |
|---|---|
| **Speedtest by Ookla** | Hastighet ned/opp, ping, jitter. Samme server hver gang. |
| **Network Analyzer** (Techet) | Ping (gateway, 1.1.1.1, 8.8.8.8), traceroute, DNS-oppslag, portsjekk (TCP 443 mot extremecloudiq.com og redirector.aerohive.com), LAN-skanning og Wi-Fi-info (SSID, BSSID, IP, gateway, DNS). Gratisversjonen (Lite) holder. |
| **Fing** | LAN-skanning (hvem er på Adm-nett: svitsj, brannmur, AP-er), ping og enkel enhetsidentifisering. |
| **WiFiman** (Ubiquiti) | Finnes også for iOS: hastighetstest, LAN-skanning og Wi-Fi-info for det nettet du er på. Kanal/BSSID-skanning av *alle* nettverk er begrenset på iOS — bruk AirPort-verktøy til det. |
| **ExtremeCloud IQ Companion** (Extreme Networks) | AP-status fra XIQ, som på Android. |

De to portalsjekkene i nettleseren (captive.apple.com og connectivitycheck.gstatic.com, se 1b) gjelder også her — Safari fungerer fint.

## 3. 15-minutters manuell runde (alle telefoner)

Fungerer på hvilken som helst telefon uten skript. Målet er å få tall fra fem faste punkter pluss en gåtur mellom dem, slik at analysen kan se både dekning per punkt og roaming.

**Forberedelse (2 min):**

- Skriv ned telefonmodell/OS, abonnementshastighet (ned/opp), dato og klokkeslett i toppen av malen.
- Åpne WiFiman (Android/iOS) eller AirPort-verktøy → Wi-Fi-skann (iOS) så du kan lese BSSID/kanal/RSSI live.
- I YouTube-appen: Innstillinger → Generelt → slå på «Aktiver statistikk for nerder» (Stats for nerds). Finn en 4K-video (søk «4K 60fps demo»), sett kvaliteten manuelt til 2160p.
- Ha en videosamtale klar (FaceTime, Teams eller WhatsApp) med noen som kan si fra når bildet fryser.

**De fem punktene** (bruk disse navnene i malen så rapportene kan sammenlignes over tid):

1. **resepsjon**
2. **trafokiosk** (utenfor kiosken der brannmur og svitsj står)
3. **ytterpunkt nord** (den nordligste plassen gjester bruker)
4. **ytterpunkt sør** (den sørligste)
5. **der folk klager** (stedet klagene kommer fra — skriv hvor)

**På hvert punkt (ca. 2 min):**

1. Stå stille i 10–15 sekunder, og noter SSID, BSSID, bånd (2,4/5/6 GHz), kanal og RSSI i dBm. Ser du at telefonen hopper mellom BSSID-er uten at du flytter deg, noter begge.
2. Kjør en hastighetstest (Speedtest eller WiFiman). Noter ned/opp i Mbit/s og ping i ms.
3. Spill 4K-videoen i 2 minutter. Følg med i «Statistikk for nerder»: noter oppløsningen som faktisk spilles (f.eks. 2160p eller om den faller til 1080p/720p), «Connection Speed», og om videoen stopper for å bufre («Buffer Health» som går mot 0). Antall stopp og kvalitetsfall går i malen.
4. Se raskt på Wi-Fi-detaljskjermen: har telefonen samme IP/gateway/DNS som ved forrige punkt? (Endring i gateway/DNS mellom punkter tyder på VLAN-/DHCP-avvik mellom AP-ene.)

**Gåturen (5 min):** Start videosamtalen på punkt 1 og gå i normalt tempo 1 → 2 → 3 → 4 → 5 med WiFiman/AirPort-verktøy synlig innimellom. Hver gang bildet fryser eller lyden hakker, noter klokkeslett, hvor du var, og BSSID før/etter (om du rakk å se det). En roam på Adm-nett skal ikke merkes i samtalen; et frys på over 1–2 sekunder er verdt å notere.

**Mal — kopier, fyll ut og lim inn i chatten:**

```markdown
## Mobil-sjekk Marivold Camping — Adm-nett

- Dato/klokkeslett: 
- Telefon og OS-versjon: 
- Abonnement (ned/opp, Mbit/s): 
- Tilfeldig MAC / privat Wi-Fi-adresse: på / av
- IP / gateway / DNS (fra Wi-Fi-detaljer): 
- Portalsjekk (captive.apple.com «Success», generate_204 tom side): OK / avvik: 
- Verktøy brukt (WiFiman, AirPort-verktøy, Speedtest, annet): 

### Punktmålinger

| Punkt | Kl. | SSID | BSSID | Bånd | Kanal | RSSI (dBm) | Ned (Mbit/s) | Opp (Mbit/s) | Ping (ms) | 4K-video: stopp / kvalitetsfall | IP/gateway/DNS uendret? | Merknad |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| resepsjon | | Adm-nett | | | | | | | | | | |
| trafokiosk | | Adm-nett | | | | | | | | | | |
| ytterpunkt nord | | Adm-nett | | | | | | | | | | |
| ytterpunkt sør | | Adm-nett | | | | | | | | | | |
| der folk klager (hvor: ) | | Adm-nett | | | | | | | | | | |

### Gåtur med videosamtale (app: FaceTime / Teams / WhatsApp)

| Strekning | Kl. | Frys/hakking (sek) | BSSID før | BSSID etter | Merknad |
|---|---|---|---|---|---|
| resepsjon → trafokiosk | | | | | |
| trafokiosk → ytterpunkt nord | | | | | |
| ytterpunkt nord → ytterpunkt sør | | | | | |
| ytterpunkt sør → der folk klager | | | | | |

### Annet jeg la merke til

- 
```

Lim gjerne inn skjermbilder i tillegg (WiFiman-skjermen, Speedtest-resultatet, «Statistikk for nerder»-boksen) — tallene i tabellen er det viktigste.

## 4. Hva du limer inn i chatten, og hva som analyseres

**Lim inn (i denne rekkefølgen, så mye du har):**

1. Hele `nettsjekk-rapport-<host>-<tid>.md` fra Termux (eller `.json` om `.md` blir for lang for ett innlegg — del den opp seksjon for seksjon).
2. Markdown-oppsummeringen fra `roaming-logg.sh` (og CSV-loggen om den er kort).
3. Den utfylte malen fra del 3.
4. Det du så i Wi-Fi-detaljskjermen (IP, gateway, DNS, MAC-valg) og i ExtremeCloud IQ Companion (AP-er som er frakoblet, alarmer, tidspunkt).
5. Hvis noe skjedde underveis: klokkeslett og hva du gjorde (f.eks. «kl. 14:32 frøs Teams i 4 s mellom trafokiosk og nord»).

**Dette analyseres ut fra det du limer inn:**

- **RSSI per punkt mot tersklene**: PASS ≥ −65 dBm, WARN ≥ −72 dBm, FAIL < −72 dBm. FAIL på et punkt betyr dekningshull eller feil AP-plassering/effekt; WARN over store deler av området tyder på for få AP-er eller for lav sendeeffekt i radioprofilen.
- **2,4 GHz-klistring**: står telefonen på 2,4 GHz på Adm-nett (WARN), selv med god 5 GHz-dekning, peker det på bånd-styring/BSS-transition-innstillingene i radioprofilen eller at 5 GHz-radioen på den AP-en ikke sender Adm-nett.
- **Hastighet mot abonnement**: PASS ≥ 80 % av forventet, WARN ≥ 50 %, FAIL < 50 %. Lav hastighet på *alle* punkter med god RSSI = flaskehals i fiber/brannmur/svitsj (se infra-sjekkliste.md); lav hastighet bare der RSSI er dårlig = radio. Sammenlignes også med linkhastigheten (PHY) — stor avstand mellom PHY-rate og reell hastighet tyder på støy/retransmisjoner.
- **Video**: kvalitetsfall under 2160p eller stopp ved hastigheter over 25 Mbit/s tyder på bufferbloat/jitter heller enn ren kapasitet; under 8 Mbit/s er kapasiteten for lav for 1080p.
- **Roam-hull**: frys i videosamtalen som sammenfaller med BSSID-bytte = tregt AP-bytte (802.11r/k/v, DHCP ved roam, eller VLAN som ikke er lik på alle AP-er). Frys *uten* BSSID-bytte = telefonen henger igjen på en fjern AP («sticky client»). Roaming-loggen gir dette i sekunder per bytte.
- **DNS og gateway**: gateway-RTT over 10 ms fra stille posisjon med god RSSI peker på AP/svitsj/brannmur, ikke radio. DNS-medianer over 50 ms, en resolver som ikke svarer, eller et NXDOMAIN-navn som likevel «svarer», gir FAIL og tyder på DNS-problemer/kapring i brannmur eller ISP-resolver. Ulik gateway/DNS mellom punkter = VLAN-/DHCP-avvik mellom AP-ene.
- **DHCP/MAC**: 169.254.x.x-adresse = FAIL (DHCP nådde ikke frem). DHCP-server ≠ gateway noteres som INFO. Tilfeldig MAC/privat adresse på forklarer hvorfor en reservasjon ikke treffer.
- **Portal/kapring**: avvik på captive.apple.com eller generate_204 = FAIL (fangeportal, proxy eller DNS-kapring i veien).
- **XIQ-forutsetninger**: klarer telefonen DNS-oppslag og TCP 443 mot redirector.aerohive.com og extremecloudiq.com, kan AP-ene på samme VLAN normalt også nå skyen; feiler det, forklarer det «CAPWAP connection was lost» i XIQ (AP-ene trenger DNS, UDP 12222 og TCP 443 ut).

## 5. Det telefonen ikke ser

Telefonen måler bare det som er synlig fra klientsiden: radio, IP/DHCP/DNS, gateway-RTT og hastigheten ende-til-ende. Den kan ikke se innsiden av fiberen/ONT-en, brannmurens sesjonstabell og WAN-status, svitsjens portfeil/PoE/VLAN-oppsett eller AP-enes kabelside — det står i **infra-sjekkliste.md**, som går gjennom fiber → brannmur → svitsj → AP → klient fra admin-grensesnittene i trafokiosken og XIQ (med plass til å skrive inn brannmur- og svitsjmodell, som ikke er kjent ennå).

Hele skriptsettet (sjekk-klient.ps1 og roaming-logg.ps1 med alle seksjoner, iperf3-støtte, TCP-tellere, DF-ping/PMTU og AP-status via plink) kjører best fra Windows-admin-PC-en på Adm-nett — se **README.md** for oppsett og eksempler. Telefonrunden i denne filen er ment som første, raske datagrunnlag mens du er på området, og som supplement til PC-rapporten senere.
