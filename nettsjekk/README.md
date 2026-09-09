# nettsjekk — ende-til-ende klientsjekk for Adm-nett (Marivold Camping)

| | |
|---|---|
| **Navn** | README.md — inngangsdøren til nettsjekk-settet |
| **Formål** | Forklare hva settet måler, hvorfor det må kjøres fra en enhet på Adm-nett, hvordan du kjører det, og hva du limer tilbake i chatten for analyse. |
| **Kjøring (eksempel)** | Windows: `powershell -ExecutionPolicy Bypass -File .\sjekk-klient.ps1 -ForventetNed 500 -ForventetOpp 500 -InterneNavn 10.0.0.1,10.0.0.2` — macOS/Linux/Termux: `bash sjekk-klient.sh --forventet-ned 500 --forventet-opp 500 --interne-navn 10.0.0.1,10.0.0.2` |
| **Krav** | En PC, Mac eller Android-telefon på SSID «Adm-nett». Windows: PowerShell 5.1 eller 7. macOS/Linux/Termux: bash og curl. Alt annet er valgfritt og gir [SKIP] med installasjonskommando hvis det mangler. |
| **Versjon** | Versjon 1.0 — 2026-09-09 |
| **Prinsipp** | Endrer ingenting — kun lesing og målinger. |

Innhold:

1. [Hva dette er](#1-hva-dette-er)
2. [Hvorfor sjekken ikke kunne kjøres fra chatten](#2-hvorfor-sjekken-ikke-kunne-kjøres-fra-chatten)
3. [Tre måter å få en ekte ende-til-ende-sjekk](#3-tre-måter-å-få-en-ekte-ende-til-ende-sjekk)
4. [Filene](#4-filene)
5. [Kjøring](#5-kjøring)
6. [Parametere](#6-parametere)
7. [Seksjoner og terskler](#7-seksjoner-og-terskler)
8. [Roaming-test](#8-roaming-test)
9. [Hva du limer tilbake](#9-hva-du-limer-tilbake)
10. [Sikkerhet og personvern](#10-sikkerhet-og-personvern)
11. [Feilsøking av selve skriptene](#11-feilsøking-av-selve-skriptene)

---

## 1. Hva dette er

nettsjekk er et sett med lesende skript og sjekklister som måler hele kjeden **fiber – brannmur – svitsj – AP – klient** slik den ser ut fra en klient på Adm-nett. Du kjører det fra admin-PC-en, en bærbar, en Mac eller en Android-telefon, og limer rapporten inn i chatten. Analysen gjøres der.

Det klientskriptene måler (14 seksjoner, 0–13):

- **Klient**: system, verktøy, MTU, IPv4/IPv6, ruter, VPN/proxy, klokke, TCP-retransmisjoner.
- **AP / radio**: SSID, BSSID, bånd, kanal, RSSI, SNR, PHY-rate, nabo-BSSID-er, roaming (øyeblikksbilde + egen gå-logg).
- **Svitsj**: forskjellen mellom Wi-Fi og kablet port på samme svitsj, lokal hastighet med iperf3.
- **Brannmur**: gateway-RTT, pakketap, jitter, DHCP, DNS (inkl. NXDOMAIN-test og interne navn), PMTU, captive portal, XIQ-forutsetninger.
- **Fiber / WAN**: første hopp utenfor brannmuren, internett-RTT, offentlig IP, ISP/ASN, hastighet mot abonnement, bufferbloat, video (HLS).

Det settet **ikke** gjør:

- Det logger ikke inn i brannmuren eller svitsjen (leverandør og modell er ukjent). De leddene sjekkes manuelt etter **infra-sjekkliste.md**, som har plass til å skrive inn modell.
- AP-ene sjekkes ikke av klientskriptene, men av **ap-status.ps1** (read-only `show`-kommandoer over SSH med plink) og i ExtremeCloudIQ.
- Ingenting endres. Ingen innstilling, ingen lease, ingen cache, ingen adapter. Skriptene ber aldri om sudo/admin.

---

## 2. Hvorfor sjekken ikke kunne kjøres fra chatten

Chat-økten kjører i en isolert sky-container, ikke på Adm-nett. Containeren har én adresse (192.0.2.2, et dokumentasjonsnett), ingen ruter, og verktøy som `ping`, `traceroute`, `dig` og `ssh` finnes ikke der.
All trafikk ut går gjennom en utgående HTTPS-proxy. Alle private IP-adresser (10.x, 172.16–31.x, 192.168.x) besvares av proxyen med HTTP 403 «private_dest_ip» — gateway, svitsj og AP-er er derfor uoppnåelige uansett.
At telefonen din står på Adm-nett, gjelder telefonen. Det strekker seg ikke til økten i skyen, som bare ser teksten du sender.
Derfor: kjør settet fra en enhet på Adm-nett og lim rapporten tilbake i chatten. Rapporten er laget for nettopp det.

---

## 3. Tre måter å få en ekte ende-til-ende-sjekk

**A) Kjør skriptene på Windows-admin-PC-en eller en bærbar på Adm-nett (anbefalt).**
Hent mappen `nettsjekk/` fra repoet (git clone eller ZIP), kjør kommandoene i [del 5](#5-kjøring), og lim `.md`-rapporten inn i chatten. Kjør gjerne én gang på Wi-Fi og én gang på kablet port i samme svitsj — da kan Wi-Fi-leddet skilles fra WAN-leddet.

**B) Installer Claude Code på en maskin på Adm-nett.**
Da kjører analysen på innsiden av nettet og kan selv kjøre skriptene, `ap-status.ps1` og `plink` mot AP-ene direkte. Krever Node.js 18 eller nyere.

```bash
npm install -g @anthropic-ai/claude-code
cd Anthropic-claude-code
claude
```

Skriv deretter i Claude Code, for eksempel: «Kjør nettsjekk fra denne maskinen (sjekk-klient og roaming-logg), deretter ap-status.ps1 mot AP-ene i ap-liste.txt, og analyser rapportene per ledd.»

**C) Fra telefonen, akkurat nå.**
Se **mobil-sjekk.md**: Android med Termux kjører de ekte skriptene; ellers en 15-minutters manuell runde med innebygde Wi-Fi-detaljer og gratisapper (Android og iPhone).

---

## 4. Filene

| Fil | Plattform | Hva den gjør | Kjøretid |
|---|---|---|---|
| README.md | alle | Denne filen. | — |
| sjekk-klient.ps1 | Windows (PowerShell 5.1 / 7) | Full klientsjekk, seksjon 0–13. Skriver `nettsjekk-rapport-<host>-<tid>.md` og `.json`. | < 6 min, `-Hurtig` < 2 min |
| sjekk-klient.sh | macOS, Linux, Android/Termux | Samme sjekk og samme rapport som PowerShell-varianten. | < 6 min, `--hurtig` < 2 min |
| roaming-logg.ps1 | Windows | Logger SSID/BSSID/kanal/bånd/signal og gateway-ping hvert sekund mens du går. Oppdager roaming, måler gap, finner «sticky client». Skriver `roaming-logg-<host>-<tid>.csv` og `.md`. | 10 min (standard), Ctrl-C når som helst |
| roaming-logg.sh | macOS, Linux, Termux | Samme som roaming-logg.ps1. | 10 min (standard), Ctrl-C når som helst |
| ap-status.ps1 | Windows med plink.exe (PuTTY); også pwsh på Linux/macOS med putty-tools | Read-only status fra alle AP-er i `ap-liste.txt` over SSH: versjon, oppetid, CAPWAP mot XIQ, klienter, ACSP/naboer, logg. Skriver `ap-status-<tid>\oppsummering.md` + rå utdata per AP. | 1–3 min for fire AP-er |
| ap-liste.eksempel.txt | — | Mal for `ap-liste.txt` (én AP per linje: `navn;ip`). | — |
| ap-kommandoer.txt | — | `show`-kommandoene ap-status.ps1 kjører. Sikkerhetsfilter stopper alt som ikke er lesende. | — |
| infra-sjekkliste.md | manuelt: brannmur, svitsj, XIQ | Sjekkliste for leddene klienten ikke ser innenfra: fiber/ONT/WAN → brannmur → svitsj → AP → klient. | 30–60 min |
| mobil-sjekk.md | Android, iPhone/iPad | Det du kan gjøre fra telefonen nå: Termux-kjøring, Wi-Fi-detaljer, apper, 15-minutters runde med mal. | 15 min |
| .gitignore | — | Holder rapporter, roaming-logger, ap-status-mapper og `ap-liste.txt` utenfor git. | — |

Alle rapporter havner i gjeldende mappe med mindre du angir rapportmappe.

---

## 5. Kjøring

Tallene i eksemplene (500/500 Mbit/s og 10.0.0.1/10.0.0.2) er bare eksempler. Sett inn **abonnementshastighetene fra fiberavtalen** og **IP-adressene (eller DNS-navnene) til brannmuren og svitsjen** i trafokiosken.

### 5a. Windows (admin-PC-en)

Åpne PowerShell i mappen `nettsjekk` (Shift + høyreklikk i Utforsker → «Åpne PowerShell-vindu her»), og kjør:

```powershell
powershell -ExecutionPolicy Bypass -File .\sjekk-klient.ps1 -ForventetNed 500 -ForventetOpp 500 -InterneNavn 10.0.0.1,10.0.0.2
```

Hurtigmodus (uten hastighet, bufferbloat og video, under 2 minutter):

```powershell
powershell -ExecutionPolicy Bypass -File .\sjekk-klient.ps1 -Hurtig
```

Roaming-logg mens du går (1 s intervall, 10 min; `-Varighet 0` = til Ctrl-C):

```powershell
powershell -ExecutionPolicy Bypass -File .\roaming-logg.ps1
```

AP-status over SSH (plink.exe fra PuTTY må finnes i PATH, i `C:\Program Files\PuTTY\` eller ved siden av skriptet):

```powershell
copy ap-liste.eksempel.txt ap-liste.txt
notepad ap-liste.txt
powershell -ExecutionPolicy Bypass -File .\ap-status.ps1 -KunNaabar
powershell -ExecutionPolicy Bypass -File .\ap-status.ps1
```

- Rediger `ap-liste.txt` med AP-enes navn og adresser på Adm-nett (se «Devices» i XIQ eller DHCP-leaselisten i brannmuren). Filen er unntatt fra git.
- `-KunNaabar` tester bare TCP 22 mot hver AP, uten plink og uten passord. Kjør den først.
- Første gang må SSH-vertsnøkkelen til hver AP være kjent for PuTTY: koble til hver AP én gang manuelt med `plink -ssh admin@<ap-ip>` og svar «y», eller kjør skriptet med `-HostKeyGodta` (godtar nøkkelen blindt første gang — bare på et nett du stoler på).
- Skriptet spør om passord én gang (maskert). Med `-Session <PuTTY-økt>` og privat nøkkel brukes ikke passord i det hele tatt. Se [del 10](#10-sikkerhet-og-personvern).

### 5b. macOS og Linux

```bash
cd nettsjekk
bash sjekk-klient.sh --forventet-ned 500 --forventet-opp 500 --interne-navn 10.0.0.1,10.0.0.2
bash roaming-logg.sh
```

Hurtigmodus: `bash sjekk-klient.sh --hurtig`. Hjelp: `bash sjekk-klient.sh --hjelp`.

### 5c. Android (Termux)

Følg **mobil-sjekk.md**, del 1a: installer Termux og Termux:API fra F-Droid, gi Termux:API posisjonstillatelse, og kjør de samme `bash`-kommandoene som over. Del 1a forklarer også hvordan du får rapporten ut av Termux og inn i chatten.

### 5d. Anbefalt oppsett for å skille Wi-Fi fra WAN

1. Kjør `sjekk-klient` én gang på **Wi-Fi (Adm-nett)** og én gang på en **kablet port i samme svitsj**. Er tallene like, ligger flaskehalsen i svitsj/brannmur/fiber. Er kablet klart bedre, ligger den i AP/radio.
2. Start en iperf3-server på en **kablet** vert, for eksempel admin-PC-en: `iperf3 -s` (Windows: last ned fra https://iperf.fr, pakk ut `iperf3.exe` og `cygwin1.dll`; Linux: `sudo apt install iperf3`; macOS: `brew install iperf3`). Windows-brannmuren må slippe inn TCP 5201 på den PC-en (Windows spør vanligvis første gang `iperf3 -s` startes).
3. Kjør klientsjekken fra Wi-Fi med `--iperf-server <ip-til-admin-pc>` / `-IperfServer <ip-til-admin-pc>`. Da måles Wi-Fi-leddet alene, uavhengig av fiber og ISP.
4. Gå roaming-runden i [del 8](#8-roaming-test) med `roaming-logg`.
5. Gå gjennom **infra-sjekkliste.md** i brannmur-/svitsj-grensesnittet og XIQ, og kjør `ap-status.ps1`.

---

## 6. Parametere

Samme navn og betydning i bash og PowerShell.

### sjekk-klient.sh / sjekk-klient.ps1

| bash | PowerShell | Betydning | Standard |
|---|---|---|---|
| `--rapportmappe DIR` | `-Rapportmappe` | Mappe der `.md` og `.json` skrives | gjeldende mappe |
| `--hurtig` | `-Hurtig` | Hopper over seksjon 8, 9 og 10 (hastighet, bufferbloat, video) | av |
| `--forventet-ned N` | `-ForventetNed` | Forventet nedlasting i Mbit/s (abonnementet) | 100 |
| `--forventet-opp N` | `-ForventetOpp` | Forventet opplasting i Mbit/s (abonnementet) | 50 |
| `--iperf-server IP` | `-IperfServer` | iperf3-server på LAN for lokal hastighetsmåling (valgfritt) | ingen |
| `--interne-navn a,b,c` | `-InterneNavn` (string[]) | Interne DNS-navn som skal kunne slås opp (kommaseparert), f.eks. brannmur og svitsj | ingen |
| `--gateway IP` | `-Gateway` | Overstyr gateway-adressen | fra rutetabellen |
| `--grensesnitt IF` | `-Grensesnitt` | Overstyr nettverksgrensesnitt (`en0`, `wlan0`, «Wi-Fi») | grensesnittet med standardruten |
| `--ingen-farger` | `-IngenFarger` | Ingen farger på konsollen (for logging/omdirigering) | av |
| `--hjelp` | `Get-Help .\sjekk-klient.ps1 -Full` | Hjelpetekst | — |

### roaming-logg.sh / roaming-logg.ps1

| bash | PowerShell | Betydning | Standard |
|---|---|---|---|
| `--intervall N` | `-Intervall` | Sekunder mellom hver prøve (1–60) | 1 |
| `--varighet N` | `-Varighet` | Total loggetid i sekunder, 0 = til Ctrl-C | 600 |
| `--rapportmappe DIR` | `-Rapportmappe` | Mappe for CSV og `.md` | gjeldende mappe |
| `--gateway IP` | `-Gateway` | Gateway som pinges | fra rutetabellen |
| `--grensesnitt IF` | `-Grensesnitt` | Wi-Fi-grensesnitt som logges | automatisk |
| `--ingen-farger` | `-IngenFarger` | Ingen farger | av |
| `--hjelp` | `Get-Help .\roaming-logg.ps1 -Full` | Hjelpetekst | — |

### ap-status.ps1 (bare PowerShell)

| Parameter | Betydning | Standard |
|---|---|---|
| `-ApListe` | Fil med AP-er, `navn;ip` per linje | `.\ap-liste.txt` |
| `-Kommandoer` | Fil med `show`-kommandoer | `.\ap-kommandoer.txt` |
| `-Bruker` | SSH-brukernavn | `admin` |
| `-PlinkPath` | Full sti til plink.exe | søkes i PATH og PuTTY-mappen |
| `-Rapportmappe` | Mappe for utdata | `.\ap-status-<YYYYMMDD-HHMMSS>` |
| `-TimeoutSek` | Tidsavbrudd per kommando (3–600) | 25 |
| `-HostKeyGodta` | Godta ukjente SSH-vertsnøkler automatisk første gang | av |
| `-Session` | Lagret PuTTY-økt (nøkkelbasert, ingen `-pw`) | ingen |
| `-KunNaabar` | Test bare TCP 22 mot AP-ene, uten plink/passord | av |
| `-TillatEndringer` | Slår av sikkerhetsfilteret for kommandoer — ikke anbefalt | av |
| `-IngenFarger` | Ingen farger | av |

---

## 7. Seksjoner og terskler

Alle skriptene bruker de samme seksjonsnumrene og tersklene, og tersklene skrives inn i rapporten. Statuslinjer har formen `[PASS] <seksjon>: <sjekk> — <verdi> (terskel <t>)` med statusene PASS, WARN, FAIL, INFO og SKIP.

| Seksjon | Hva måles | Terskler |
|---|---|---|
| 0 System og verktøy | OS, skriptversjon, parametre, admin-status, hvilke verktøy som finnes | INFO; manglende verktøy → SKIP med nøyaktig installasjonskommando |
| 1 Lenke og Wi-Fi | SSID, BSSID, bånd, kanal, RSSI, SNR, PHY/tx-rate, synlige BSSID-er | RSSI PASS ≥ −65 dBm, WARN ≥ −72 dBm, FAIL < −72 dBm. SNR (der støy finnes) PASS ≥ 25 dB, WARN ≥ 15 dB, FAIL < 15 dB. Tx-rate/PHY INFO. Tilkoblet på 2,4 GHz → WARN (Adm-nett bør bruke 5/6 GHz) |
| 2 IP og TCP/IP | IPv4, maske, MTU på grensesnitt, default-ruter, IPv6 | Flere default-ruter → WARN. IPv6 → INFO. MTU på grensesnitt under 1500 → WARN (ende-til-ende PMTU måles i seksjon 5) |
| 3 DHCP | DHCP-server, lease-tid, 169.254-adresse | Lease-tid < 10 min → WARN. DHCP-server ≠ gateway → INFO (begge oppgis). 169.254.x.x → FAIL |
| 4 DNS | Oppslagstid per konfigurert resolver og mot 1.1.1.1 / 8.8.8.8 / 9.9.9.9 (median av 5 ulike navn), NXDOMAIN-test, interne navn, XIQ-navn | PASS < 50 ms, WARN < 150 ms, FAIL ≥ 150 ms eller feil. Alle konfigurerte resolvere må svare (ellers FAIL). Et navn som skal gi NXDOMAIN må feile (ellers FAIL: DNS-kapring/portal). Interne navn må svare |
| 5 Gateway og brannmur | 20 ping mot gateway: RTT, pakketap, jitter. DF-ping 1472 byte nyttelast mot gateway og 1.1.1.1 (PMTU) | RTT snitt PASS ≤ 10 ms, WARN ≤ 30 ms, FAIL > 30 ms. Pakketap PASS 0 %, WARN ≤ 1 %, FAIL > 1 %. Jitter (std.avvik/mdev) PASS < 5 ms, WARN < 20 ms, FAIL ≥ 20 ms. PMTU PASS 1500 ende-til-ende, WARN hvis bare ≤ 1452 går (PPPoE/tunnel), FAIL hvis < 1400 eller PMTUD-svart hull |
| 6 Fiber og WAN | Offentlig IP (1.1.1.1/cdn-cgi/trace, reserve api.ipify.org), ISP/ASN (ipinfo.io), internett-RTT, traceroute hopp 2, XIQ-forutsetninger | Internett-RTT snitt mot 1.1.1.1 og 8.8.8.8 PASS ≤ 25 ms, WARN ≤ 60 ms, FAIL > 60 ms. Hopp 2 (første hopp utenfor brannmuren, fiber/ISP-siden) PASS < 10 ms, WARN < 25 ms, FAIL ≥ 25 ms. Offentlig IP/ISP INFO. XIQ: DNS-oppslag + TCP 443 mot redirector.aerohive.com og extremecloudiq.com → INFO |
| 7 TCP-ytelse | TCP-connect til 443 hos 5 mål (1.1.1.1, 8.8.8.8, 9.9.9.9, nrk.no, vg.no, telenor.no), TLS-handshake, retransmisjoner før/etter hastighetstesten | TCP-connect median PASS < 40 ms, WARN < 100 ms, FAIL ≥ 100 ms. TLS-handshake INFO. Retransmisjoner (differanse i tellere delt på sendte segmenter) PASS < 0,5 %, WARN < 2 %, FAIL ≥ 2 % |
| 8 Hastighet | Nedlasting `https://speed.cloudflare.com/__down?bytes=100000000`, opplasting POST `https://speed.cloudflare.com/__up`, iperf3 mot LAN-server (valgfritt) | PASS ≥ 80 % av forventet, WARN ≥ 50 %, FAIL < 50 % (forventet = `--forventet-ned` / `--forventet-opp`) |
| 9 Bufferbloat og jitter under last | Median RTT under nedlasting minus median RTT i ro, mot gateway og 1.1.1.1 | PASS < 30 ms, WARN < 100 ms, FAIL ≥ 100 ms |
| 10 Video og strømming | HLS-teststrøm (høyeste bitrate-variant, minst 6 segmenter): primær test-streams.mux.dev, reserve devstreaming-cdn.apple.com | Gjennomsnittlig segment-gjennomstrømning PASS ≥ 25 Mbit/s (4K-margin), WARN ≥ 8 Mbit/s (1080p), FAIL < 8 Mbit/s. Maks/median segment-hentetid > 3 → WARN (stalling-risiko) |
| 11 Roaming | Øyeblikksbilde: roamingkandidater (samme SSID), henvisning til roaming-logg | INFO. Gap-terskler i roaming-logg: PASS ≤ 100 ms, WARN ≤ 500 ms, FAIL > 500 ms |
| 12 Hygiene | NTP/klokke, captive portal, VPN, proxy-variabler, WLAN-rapport (Windows, bare med admin) | Klokkeavvik < 1 s PASS, < 5 s WARN, ellers FAIL; ikke synkronisert → FAIL. Captive portal: `http://connectivitycheck.gstatic.com/generate_204` skal gi 204 og `http://captive.apple.com/hotspot-detect.html` skal gi 200 med «Success», ellers FAIL (portal/proxy/DNS-kapring). VPN aktiv → WARN (målingene går gjennom VPN). Proxy-variabler satt → WARN |
| 13 Oppsummering | Antall PASS/WARN/FAIL/SKIP/INFO, filnavn på rapportene | — |

`--hurtig` / `-Hurtig` hopper over seksjon 8, 9 og 10.

---

## 8. Roaming-test

Roaming måles ikke med et øyeblikksbilde, men ved å gå. Protokoll:

1. Start loggen på den enheten du går med: `roaming-logg.ps1` (Windows) eller `bash roaming-logg.sh` (macOS/Linux/Termux). Standard er **1 s intervall i 10 min**. Bruk `-Varighet 0` / `--varighet 0` om du vil avslutte selv med Ctrl-C.
2. Start en **videosamtale** på samme enhet (Teams, FaceTime, WhatsApp — det som er tilgjengelig) og hold den i gang hele runden.
3. Gå en **fast rute forbi hver AP** (AP305C, AP305CX, AP460C, Atom AP30): resepsjon, servicebygg, uteområde, trafokiosk, ytterpunktene. Gå i vanlig gangfart, ikke stopp lenge på hvert sted.
4. **Noter klokkeslett** hver gang bildet eller lyden fryser, og hvor du var.
5. Etter runden: sammenlign notatene med `ROAM`-linjene i oppsummeringen. Hver linje viser gammel → ny BSSID, kanal, bånd, signal før/etter, gap og tid til første vellykkede ping.

Terskler i oppsummeringen:

| Måling | PASS | WARN | FAIL |
|---|---|---|---|
| Gap ved roaming (tapte gateway-ping × intervall) | ≤ 100 ms | ≤ 500 ms | > 500 ms |
| Pakketap mot gateway over hele runden | < 1 % | < 3 % | ≥ 3 % |
| Sticky client (signal < −75 dBm i > 10 s uten roaming) | — | WARN | — |
| Andel prøver på 2,4 GHz | 0 % | > 0 % | — |

Tolkning: frys som faller sammen med en ROAM-linje = tregt AP-bytte (802.11r/k/v, DHCP ved roam, VLAN som ikke er lik på alle AP-er). Frys **uten** ROAM-linje mens signalet er dårlig = enheten henger igjen på en fjern AP (sticky client). Gap-oppløsningen er lik intervallet (1 s = 1000 ms), så kjør med 1 s for å skille PASS fra WARN.

---

## 9. Hva du limer tilbake

Lim inn i chatten, i denne rekkefølgen, så mye du har:

1. Hele `nettsjekk-rapport-<host>-<tid>.md` (fra Wi-Fi, og gjerne én fra kablet port). Blir den for lang for ett innlegg, del den opp seksjon for seksjon. `.json` er en reserve om du heller vil sende strukturerte data.
2. `roaming-logg-<host>-<tid>.md` fra gå-runden, og CSV-loggen om den er kort (eller bare linjene rundt hendelsene).
3. `ap-status-<tid>\oppsummering.md` fra `ap-status.ps1`, og `all.txt` for AP-er med avvik.
4. Det du fant i **infra-sjekkliste.md** (brannmur, svitsj, XIQ), med modell og fastvare der du vet det.
5. Klokkeslett og hva du gjorde når noe skjedde underveis.

Rapporten inneholder statuslinjer per seksjon pluss rå kommandoutdata i kodeblokker, slik at analysen kan gå bak tallene. Analysen dekker hvert ledd:

| Ledd | Hva vurderes ut fra rapporten |
|---|---|
| Fiber / WAN | Hopp 2-RTT, internett-RTT, offentlig IP og ISP/ASN, hastighet mot abonnement, bufferbloat, video-gjennomstrømning. Dårlig her fra **kablet** klient = fiber/ISP eller brannmur, ikke Wi-Fi. |
| Brannmur | Gateway-RTT/tap/jitter, DHCP (server, lease, 169.254), DNS (resolvere, oppslagstid, NXDOMAIN-kapring), PMTU, captive portal, XIQ-forutsetninger (DNS + TCP 443; AP-ene trenger i tillegg UDP 12222 ut). |
| Svitsj | Forskjell Wi-Fi mot kablet på samme svitsj, iperf3 lokalt, MTU/PMTU mot gateway, VLAN-avvik (ulik gateway/DNS mellom AP-er i roaming-loggen). |
| AP / radio | RSSI, SNR, bånd (2,4 GHz-klistring), kanal og samkanal-naboer, PHY-rate mot reell hastighet, roaming-gap, sticky client, CAPWAP-status og ACSP fra ap-status. |
| Klient | MTU, IPv6, VPN/proxy, flere default-ruter, klokkeavvik, TCP-retransmisjoner, drivere (Windows `netsh wlan show drivers`, wlanreport). |

---

## 10. Sikkerhet og personvern

- **Read-only.** Skriptene endrer ingen nettverksinnstillinger, fornyer eller slipper ikke DHCP-lease, tømmer ikke DNS-cache og slår ikke av/på adaptere. `ap-kommandoer.txt` inneholder bare `show`-kommandoer, og et sikkerhetsfilter i ap-status.ps1 nekter å kjøre linjer med `config`, `reset`, `reboot`, `save`, `write`, `erase`, `clear`, `delete`, `no ` eller `set `.
- **Ingen sudo/admin.** Skriptene ber aldri om forhøyede rettigheter. Der admin gir ekstra data (Windows wlanreport, macOS `wdutil`), prøves det bare hvis det allerede går uten passord (`sudo -n`), ellers [SKIP].
- **Rapporten inneholder** IP-adresser, MAC-adresser/BSSID-er, SSID-er, vertsnavn, offentlig IP og ISP. Det er greit å lime inn i en privat chat. Fjern eller erstatt det om rapporten deles videre (forum, leverandør, e-post til andre).
- **Aldri Wi-Fi-passord/PSK.** Skriptene leser ikke `netsh wlan show profile key=clear`, nøkkelring eller `wpa_supplicant.conf`, og rapporten inneholder ingen passord.
- **ap-status.ps1 og passord:** passordet spørres én gang (maskert, `Read-Host -AsSecureString`), holdes bare i minnet og skrives aldri til rapportfilene. Det sendes til plink som `-pw`, og `-pw` er **synlig i prosesslisten** på PC-en (Oppgavebehandling, `tasklist`, `Get-Process`) mens hver plink-prosess kjører. Bedre: nøkkelbasert pålogging via en lagret PuTTY-økt eller Pageant og `-Session <øktnavn>` — da brukes ikke `-pw`. `-HostKeyGodta` godtar AP-ens SSH-nøkkel blindt første gang; bruk den bare på et administrasjonsnett du stoler på, eller koble til hver AP manuelt én gang i stedet.
- **ap-liste.txt** med ekte adresser er unntatt fra git via `.gitignore`, sammen med alle rapporter og logger.

---

## 11. Feilsøking av selve skriptene

| Symptom | Årsak og løsning |
|---|---|
| Windows: «kjøring av skript er deaktivert på dette systemet» | Execution policy. Kjør med `powershell -ExecutionPolicy Bypass -File .\sjekk-klient.ps1` som i eksemplene. Er filene lastet ned som ZIP, kan Windows ha merket dem som blokkert: `Unblock-File .\*.ps1` i mappen. |
| `[SKIP] ... mangler 'ping'/'traceroute'/'dig'/'iw'/'iperf3'` | Verktøyet finnes ikke. Statuslinjen oppgir nøyaktig kommando. Linux (Debian/Ubuntu): `sudo apt install iputils-ping traceroute dnsutils iw iperf3 jq curl`. macOS: `ping`, `traceroute` og `dig` er innebygd; `brew install iperf3 jq`. Termux: `pkg install termux-api iputils traceroute dnsutils curl python jq` + appen Termux:API. Windows: iperf3 fra https://iperf.fr (legg `iperf3.exe` og `cygwin1.dll` ved siden av skriptet), plink fra https://www.putty.org eller `winget install PuTTY.PuTTY`. |
| Windows 11: `[SKIP] Synlige BSSID-er` / roaming uten BSSID | Windows 11 24H2 og nyere krever plasseringstillatelse for BSSID-lister fra `netsh wlan show networks mode=bssid`. Innstillinger → Personvern og sikkerhet → Plassering: slå på Stedstjenester og tillat skrivebordsapper/terminal. Kjør på nytt. |
| macOS: ingen SSID/BSSID/RSSI | macOS 14.4 og nyere har fjernet `airport`-verktøyet. Skriptet bruker `system_profiler SPAirPortDataType`, `ipconfig getsummary` og `wdutil` (bare hvis `sudo -n` går uten passord). SSID/BSSID kan være skjult uten stedstillatelse for Terminal: Systeminnstillinger → Personvern og sikkerhet → Stedstjenester → tillat Terminal. |
| Termux: `[SKIP] Wi-Fi-detaljer` eller `<unknown ssid>` / `rssi: -127` | Appen **Termux:API** må være installert fra F-Droid (samme kilde som Termux), pakken `termux-api` må være installert, og Termux:API må ha posisjonstillatelse med Stedstjenester på. Test med `termux-wifi-connectioninfo`. |
| Termux: DHCP-server og resolvere står som [SKIP]/[INFO] | Android 8 og nyere gir ikke apper tilgang til DHCP-/DNS-detaljer. Les dem av i Innstillinger → Wi-Fi → Adm-nett → detaljer og skriv dem inn i chatten. Det er forventet. |
| Alt mot internett er tregt eller FAIL, men gateway er fin | Bedrifts-proxy eller VPN er aktiv (skriptet gir WARN i seksjon 12). Målingene går da gjennom proxy/VPN og sier lite om Adm-nett. Koble fra VPN før du måler, og kjør på nytt. |
| Hastigheten stopper på samme tall uansett | Wi-Fi-lenken er taket. Sammenlign med PHY-rate i seksjon 1 og med kablet kjøring. Bruk `--iperf-server` mot en kablet vert for å måle Wi-Fi-leddet alene. |
| Roaming-loggen gir ingen ROAM-linjer | Ingen AP-bytte skjedde, eller BSSID er utilgjengelig (se punktene om plassering over). På enheter uten BSSID anslås roaming fra kanalskifte/signalhopp ≥ 12 dB og merkes «mulig roam». |
| ap-status.ps1: avslutter med kode 2 | `plink.exe` ble ikke funnet. Installer PuTTY, eller angi `-PlinkPath 'C:\sti\til\plink.exe'`. |
| ap-status.ps1: «host key is not cached» / alle AP-er FAIL | plink kjører med `-batch` og nekter ukjente vertsnøkler. Koble til hver AP én gang manuelt (`plink -ssh admin@<ap-ip>`) og svar «y», eller bruk `-HostKeyGodta`. |
| ap-status.ps1: tidsavbrudd på enkeltkommandoer | Treg AP eller lang logg. Øk `-TimeoutSek 40`. Utdata for de andre kommandoene er allerede lagret. |
| Rapportfil mangler | Skriptet skriver alltid rapport, også når det meste er [SKIP]/[FAIL]. Sjekk at rapportmappen finnes og er skrivbar, eller angi `--rapportmappe` / `-Rapportmappe` uttrykkelig. |
| Norsk Windows: verdier fra `netsh` tolkes ikke | Skriptene tolker både engelske og norske `netsh`-nøkler. Lim uansett inn rå utdata fra rapporten — de ligger i kodeblokkene. |

Versjon 1.0 — 2026-09-09. Endrer ingenting — kun lesing og målinger.
