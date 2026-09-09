# infra-sjekkliste.md — nettsjekk: hygiene- og helsesjekk for infrastrukturen

| | |
|---|---|
| **Navn** | infra-sjekkliste.md (del av nettsjekk-settet sammen med sjekk-klient.sh / sjekk-klient.ps1 og roaming-logg.sh / roaming-logg.ps1) |
| **Formål** | Praktisk sjekkliste for leddene klientskriptene ikke ser innenfra: **Fiber/ONT/WAN → Brannmur → Svitsj → AP (ExtremeCloudIQ) → Klient** på Marivold Camping. Går du gjennom listen i admin-grensesnittene i trafokiosken og i XIQ samtidig som du kjører sjekk-klient fra en klient på Adm-nett, har du begge sider av samme kjede. |
| **Kjøring** | Åpne filen på mobilen eller PC-en. Gå gjennom leddene nedenfra og opp (se «Rekkefølge»). Kjør parallelt `bash sjekk-klient.sh` eller `powershell.exe -ExecutionPolicy Bypass -File .\sjekk-klient.ps1` fra en klient på Adm-nett, og lim rapporten inn i chatten sammen med det du fant her. |
| **Krav** | Admin-tilgang til brannmur- og svitsj-grensesnittet i trafokiosken, en XIQ-konto, og plink/PuTTY for AP-CLI (`plink -ssh admin@<ap-ip> "show version"`). Ingen verktøy trengs på selve klienten ut over skriptene. |
| **Versjon** | Versjon 1.0 — 2026-09-09 |
| **Prinsipp** | Endrer ingenting — kun lesing og målinger. Alle punkter er *sjekk og noter*; endringer gjøres bevisst etterpå, i vedlikeholdsvindu, med sikkerhetskopi først. |

Terskler i kolonnen «Forventet / terskel» er de samme som klientskriptene bruker, slik at rapporten fra klienten og funnene herfra kan leses side om side.

---

## Rekkefølge — nedenfra og opp

Feilsøk alltid fra bunnen av stabelen: en feil lenger ned forklarer alle symptomene lenger opp. Hopp ikke til «DNS er tregt» før du vet at kabel, lenke og IP er i orden.

| Trinn | Hva du sjekker | Ledd i denne listen | Seksjon i sjekk-klient |
|---|---|---|---|
| 1. Strøm og kabel | LED-er på ONT, brannmur, svitsj og AP. PoE-budsjett. Patchkabler og fiberpatch. UPS. | Fiber/WAN, Svitsj, AP | 0 System og verktøy |
| 2. Lenke | Hastighet/dupleks på hver port. Wi-Fi: SSID, bånd, kanal, RSSI, SNR. | Svitsj, AP | 1 Lenke og Wi-Fi |
| 3. IP og DHCP | Riktig VLAN, adresse fra riktig scope, ingen 169.254.x.x, én default-rute. | Brannmur, Svitsj | 2 IP og TCP/IP, 3 DHCP |
| 4. DNS | Alle konfigurerte resolvere svarer, NXDOMAIN gir NXDOMAIN, oppslagstid < 50 ms. | Brannmur | 4 DNS |
| 5. Gateway | RTT ≤ 10 ms, 0 % tap, jitter < 5 ms mot gateway. MTU/PMTU 1500 (DF-ping mot gateway og 1.1.1.1). Ingen captive portal. | Brannmur | 5 Gateway og brannmur, 12 Hygiene |
| 6. WAN | Offentlig IP, ISP/ASN, hopp 2 < 10 ms, XIQ-forutsetninger (DNS + TCP 443). | Fiber/WAN | 6 Fiber og WAN |
| 7. Applikasjon | TCP-connect, hastighet ≥ 80 % av forventet, bufferbloat < 30 ms, HLS-video ≥ 25 Mbit/s, roaming. | Alle ledd | 7–11 |

Kort tolkning når klientrapporten viser avvik:

- Avvik allerede i seksjon 1 (RSSI/SNR/2,4 GHz) → start i **AP-leddet**.
- Seksjon 2/3 (169.254, feil scope, flere default-ruter) → **Brannmur** (DHCP) og **Svitsj** (VLAN-tagging på AP-porten).
- Seksjon 4 (resolver svarer ikke, NXDOMAIN kapres) → **Brannmur** (videresendere) eller **Fiber/WAN** (ISP-DNS).
- Seksjon 5 er bra, men 6 er dårlig → **Fiber/WAN**. Seksjon 5 er dårlig fra kablet vert → **Brannmur** eller **Svitsj**; bare fra Wi-Fi → **AP**.
- Seksjon 8/9 dårlig fra kablet vert → **Fiber/WAN** eller **Brannmur** (SQM). Bare dårlig fra Wi-Fi → **AP**.

---

## Ledd A — Fiber / ONT / WAN

Fiberterminalen (ONT) gjør om ISP-ens fiber til Ethernet mot brannmurens WAN-port, og ISP-en leverer adresse, rute og (om ønsket) DNS. Alt som skjer her er utenfor din kontroll, men det er fullt mulig å måle det og å dokumentere hva du kan forvente. Klientskriptets **seksjon 6 Fiber og WAN** (offentlig IP, ISP/ASN, hopp 2, XIQ-forutsetninger) og **seksjon 8 Hastighet** speiler dette leddet; MTU/PMTU-testen mot 1.1.1.1 ligger i **seksjon 5**, og **seksjon 9** blir også påvirket når WAN-linken er metningspunktet.

| Sjekk | Hvor (UI/CLI) | Forventet / terskel | Vanlig feil og konsekvens |
|---|---|---|---|
| ☐ ONT-status-LED (PON / LOS) | Fysisk på ONT-en i trafokiosken | PON lyser fast (registrert hos ISP), LOS er av. Noter LED-mønsteret i ONT-ens hurtigguide. | LOS rødt/blinkende = ikke lys på fiberen (brudd, skitten/løs kontakt, feil hos ISP). PON blinker = registrering pågår eller feiler. Konsekvens: ingen WAN i det hele tatt. |
| ☐ Lenke ONT ↔ brannmur (hastighet/dupleks) | Brannmur-UI: WAN-portens lenkestatus; ONT-ens LAN-LED | 1000 Mbit/s full dupleks, eller 2,5G/10G dersom abonnementet er over 1 Gbit/s og begge ender støtter det. | 100 Mbit/s eller halv dupleks (auto-negotiation-feil, dårlig patchkabel) gir «late collisions», pakketap og seksjon 8 FAIL selv om fiberen er fin. |
| ☐ WAN-adressering: offentlig IP eller CGNAT | Brannmur-UI: WAN-status. Sammenlign med «Offentlig IP» i seksjon 6 (1.1.1.1/cdn-cgi/trace) | WAN-IP på brannmuren er lik den offentlige IP-en klienten ser. | Er WAN-IP i 100.64.0.0/10 (CGNAT) eller en privat adresse som avviker fra den offentlige, sitter du bak ISP-ens NAT: ingen portåpning, ingen innkommende VPN/fjernstyring, og XIQ-uavhengige fjerntjenester virker ikke. Be ISP om offentlig (helst fast) IP hvis du trenger fjerntilgang. |
| ☐ PPPoE eller DHCP/IPoE, og MTU | Brannmur-UI: WAN-type og MTU | DHCP/IPoE: MTU 1500. PPPoE: MTU 1492 og MSS-clamping på. Klientens DF-ping med 1472 byte nyttelast mot gateway og 1.1.1.1 skal gå (seksjon 5: PASS 1500; WARN hvis bare ≤ 1452 går; FAIL < 1400 eller PMTUD-svart hull). | Feil MTU eller ICMP «fragmentation needed» blokkert gir PMTUD-svart hull: nettsider som «henger», opplastinger og VPN som stopper ved store pakker, mens ping virker fint. |
| ☐ IPv6-prefiksdelegering | Brannmur-UI: WAN IPv6-status / delegert prefiks | Enten et delegert prefiks (typisk /56 eller /48) med fungerende rute, eller IPv6 bevisst av. Seksjon 2 rapporterer IPv6 som INFO. | «Halv» IPv6 (adresse, men ingen rute eller DNS over IPv6) gir tidsavbrudd på nettsider før klienten faller tilbake til IPv4. Slå heller helt av enn å la det stå halvveis. |
| ☐ ISP-DNS eller egne videresendere | Brannmur-UI: WAN-DNS (fra ISP) og DNS-videresendere (se Brannmur-leddet) | Bevisst valg dokumentert. Egne (1.1.1.1, 9.9.9.9) gir forutsigbar oppførsel; ISP-DNS kan være raskest, men skal ikke kapre NXDOMAIN (seksjon 4 tester dette). | ISP-DNS som svarer med «søkeside» på ukjente navn gir seksjon 4 FAIL (DNS-kapring) og forvirrer captive-portal-deteksjon på klientene. |
| ☐ Abonnert hastighet mot målt | ISP-avtalen; seksjon 8 fra kablet vert **og** fra Wi-Fi | Skriv abonnert ned/opp her: ____ / ____ Mbit/s, og bruk dem som `--forventet-ned` / `--forventet-opp` (-ForventetNed / -ForventetOpp). PASS ≥ 80 % av forventet, WARN ≥ 50 %, FAIL < 50 %. | Kablet vert måler lavt → ONT, WAN-port eller ISP. Bare Wi-Fi måler lavt → AP-leddet. Standardverdien i skriptene er 100/50 Mbit/s — sett riktig verdi, ellers blir vurderingen feil. |
| ☐ Latens til første ISP-hopp (hopp 2 i traceroute) | Seksjon 6 i klientrapporten; ev. brannmurens egen ping/traceroute-diagnostikk | PASS < 10 ms, WARN < 25 ms, FAIL ≥ 25 ms. Internett-RTT mot 1.1.1.1/8.8.8.8: PASS ≤ 25 ms, WARN ≤ 60 ms, FAIL > 60 ms. | Høy eller ujevn RTT allerede på hopp 2 = metning eller lang vei hos ISP, ikke noe du kan fikse lokalt. Dokumenter og meld ISP med tall. |
| ☐ Strøm og UPS i trafokiosken | Fysisk: UPS-display/LED, hva som er koblet til UPS-utgangene | ONT, brannmur og svitsj (som forsyner AP-ene med PoE) på UPS. Noter batteritid: ____ min. Test med jevne mellomrom. | Et kort strømblink starter hele kjeden på nytt: alle AP-er mister CAPWAP («CAPWAP connection was lost» i XIQ), DHCP-fornyelser hoper seg opp og Wi-Fi er borte i flere minutter. |
| ☐ Fiberpatch: bøyeradius og renhet | Fysisk i trafokiosken | Ingen skarpe bøyer (hold deg til produsentens minste bøyeradius, typisk noen cm), ingen klem under lokk/strips, støvhetter på ubrukte kontakter, strekkavlastning. Se aldri inn i fiberen. | Klemt eller skitten fiber gir demping → periodiske LOS-hendelser og ONT-omregistreringer som ser ut som «tilfeldige» WAN-brudd. |
| ☐ ISP-kontakt og SLA notert | Dokumentasjonen (se «Dokumentasjonshygiene») | Kundenummer, linje-/sambands-ID, feilmeldingstelefon, avtalt responstid: ____ | Uten disse opplysningene tar en feilmelding midt i høysesongen mye lengre tid. |
| ☐ Ett enkelt feilpunkt (SPOF) | Vurdering | Én fiber, én ONT, én brannmur, én svitsj. Noter det bevisst, og vurder reserve-WAN (4G/5G) hvis kostnaden ved nedetid er høy. | Uten reserve stopper alt — inkludert betalingsterminaler og bookingsystem — ved ett enkelt kabelbrudd. |

> **Målinger som isolerer dette leddet**
> - Ping til **hopp 2** (første hopp utenfor brannmuren) fra en **kablet** vert, minst 100 pakker: stabil RTT < 10 ms og 0 % tap → fiber/ISP er i orden. Ujevn RTT eller tap her, mens gateway-ping er perfekt, peker på fiber/ISP.
> - Hastighetstest (seksjon 8) fra en **kablet** vert rett på brannmurens LAN, mot abonnert hastighet. Dette utelukker Wi-Fi og svitsj-porter mot AP.
> - Bruk brannmurens egen ping/traceroute mot 1.1.1.1 hvis den har det: da er ikke engang svitsjen med.
> - RTT til hopp 2 minus RTT til gateway (seksjon 6 mot seksjon 5) er summen av brannmur og fiber/ISP-hopp. Fra kablet vert skal gateway-delen være under 1 ms, så nesten hele differansen er fiber/ISP.
> - ONT-ens LED-er og brannmurens WAN-logg (lenke opp/ned, PPPoE-reconnect, DHCP-fornyelse) viser om WAN-en har «blinket» i perioden klienten opplevde problemer.

---

## Ledd B — Brannmur

Brannmuren er default-gateway for alle VLAN, som regel DHCP-server og DNS-videresender, gjør NAT mot internett, håndhever reglene mellom Adm-nett, gjestenett og AP-enes administrasjons-VLAN, og er stedet bufferbloat oppstår eller temmes. Klientskriptets **seksjon 5 Gateway og brannmur** (RTT, tap, jitter og MTU/PMTU), **3 DHCP**, **4 DNS** og **9 Bufferbloat** speiler dette leddet, i tillegg til NTP/captive portal i **seksjon 12**.

**Modell/firmware: ____**

| Sjekk | Hvor (UI/CLI) | Forventet / terskel | Vanlig feil og konsekvens |
|---|---|---|---|
| ☐ Firmware oppdatert og konfig-sikkerhetskopi datert | Admin-UI: system/firmware og sikkerhetskopi/eksport | Støttet versjon uten kjente sikkerhetshull. Siste sikkerhetskopi datert ____ og lagret utenfor brannmuren. | Uten fersk sikkerhetskopi blir en maskinvarefeil en full omkonfigurering fra hukommelsen midt i sesongen. |
| ☐ Admin-UI kun fra Adm-nett, aldri fra WAN | Admin-UI: administrasjonstilgang / tillatte kilder | Web/SSH-administrasjon tillatt bare fra Adm-nett-VLAN (ev. VPN). WAN-side administrasjon av. | Åpen administrasjon mot internett er det vanligste angrepspunktet på små nett. Åpen administrasjon fra gjestenettet er nesten like ille. |
| ☐ Sterke, unike admin-passord og MFA | Admin-UI: brukere/administratorer | Ingen standardbruker/-passord, ett navngitt konto per person, MFA på der det finnes. Lagret i passordhvelv. | Delt «admin/admin» eller passord i en chat gir ingen sporbarhet og lett tilgang. |
| ☐ NTP satt og riktig tidssone | Admin-UI: dato/tid | NTP mot pålitelige kilder, tidssone Europe/Oslo, klokken i synk. Seksjon 12 på klient: avvik < 1 s PASS, < 5 s WARN, ellers FAIL. | Feil klokke gir ubrukelige logger, TLS-feil og DHCP-leietider som ser ut til å utløpe «feil». |
| ☐ Logging/syslog og oppbevaring | Admin-UI: logging | Logg til ekstern syslog eller lokalt med ≥ 30 dagers oppbevaring. Logg blokkerte pakker fra AP-VLAN i feilsøkingsperioder. | Uten logg finner du aldri hvorfor «AP-en mistet XIQ i natt». |
| ☐ DHCP-scope per VLAN, fornuftig leietid, ingen overlapp | Admin-UI: DHCP-server per VLAN/grensesnitt | Ett scope per VLAN. Gjest: kort leietid (1–4 t, mange turister kommer og går). Adm-nett/AP-VLAN: lang (1–7 døgn). Ingen overlapp mellom scope, reservasjoner og statiske adresser. Utnyttelse < 80 % i høysesong. Seksjon 3: leietid < 10 min → WARN; 169.254.x.x → FAIL. | Fullt scope på gjestenettet gir 169.254-adresser hos nye gjester. Overlapp gir dupliserte IP-er og «virker av og til». |
| ☐ DHCP-reservasjoner for infrastruktur | Admin-UI: DHCP-reservasjoner / statiske tildelinger | AP-er, svitsj, skrivere, ev. kamera/betalingsutstyr har reservasjon (eller statisk adresse utenfor scope), dokumentert i IP-planen. | AP som bytter IP blir vanskelig å nå med plink, og ACL-er basert på IP slutter å virke. Seksjon 3 gir INFO når DHCP-server ≠ gateway — oppgi begge. |
| ☐ DNS-videresendere: hvilke, DNSSEC, ingen kapring | Admin-UI: DNS / videresendere | Bevisst valg (f.eks. 1.1.1.1 og 9.9.9.9, eller ISP). DNSSEC-validering på der det støttes. Seksjon 4: hver resolver median < 50 ms PASS, < 150 ms WARN, ≥ 150 ms/feil FAIL; alle konfigurerte resolvere må svare; NXDOMAIN-test må feile, ellers FAIL. | Én av to videresendere død gir «annenhver sideinnlasting er treg». NXDOMAIN som gir en IP betyr kapring/portal og bryter automatisk deteksjon på mobiler. |
| ☐ Interne DNS-navn for infrastruktur | Admin-UI: lokale DNS-oppføringer / vertsnavn | brannmur, svitsj og hver AP har navn (f.eks. `ap-resepsjon.adm.lan`). Bruk dem i `--interne-navn a,b,c` (-InterneNavn) så seksjon 4 tester at lokal DNS virker. | Uten interne navn feilsøker du med IP-lister fra hukommelsen, og lokale oppslag blir aldri testet. |
| ☐ VLAN-plan: Adm-nett adskilt fra gjest/IoT | Admin-UI: VLAN/grensesnitt og regler mellom soner | Adm-nett, gjestenett, IoT og AP-administrasjon i hvert sitt VLAN. Regler mellom VLAN: nekt som standard, tillat bare det som trengs. Gjesteisolasjon på (ingen trafikk gjest ↔ gjest, gjest → Adm-nett). | Gjester som når skrivere, kasse eller AP-administrasjon. Flatt nett gjør broadcast-støy fra hundrevis av gjesteenheter til alles problem. |
| ☐ NAT/sesjonstabell og UDP-timeout (conntrack) | Admin-UI: sesjons-/tilstandstabell, timeout-innstillinger | Kapasitet > forventet sesjoner i høysesong (mange gjester × mange apper). UDP-timeout ≥ 60–120 s slik at AP-enes CAPWAP-sesjon (UDP 12222) holdes i live mellom keepalives. | Full sesjonstabell gir tilfeldig pakketap for alle. For kort UDP-timeout gir gjentatte «CAPWAP connection was lost» uten at noe annet er galt. |
| ☐ Utgående regler for AP-ene (AP-VLAN → internett) | Admin-UI: regler fra AP-/administrasjons-VLAN | Tillatt: DNS 53 (UDP/TCP), NTP UDP 123, CAPWAP UDP 12222, HTTPS TCP 443 mot XIQ og `redirector.aerohive.com` / `extremecloudiq.com`. Seksjon 6 i klientrapporten (XIQ-forutsetninger, INFO) tester DNS + TCP 443 fra **klientens** VLAN — er AP-ene i et annet VLAN, må du sjekke reglene der. | Blokkert DNS eller 443 fra AP-VLAN: AP-en får aldri kontakt med XIQ etter omstart («Unmanaged»/«Disconnected»). Blokkert NTP: sertifikatfeil mot skyen. |
| ☐ SIP ALG av | Admin-UI: ALG-innstillinger | SIP ALG (og andre ALG-er du ikke trenger) av. | ALG «hjelper» ved å skrive om pakker og ødelegger IP-telefoni og enkelte apper. |
| ☐ DPI/IPS blokkerer ikke QUIC eller strømme-CDN | Admin-UI: IPS/app-kontroll/webfilter | QUIC (UDP 443) tillatt. Strømmetjenester og CDN-er (inkl. teststrømmene i seksjon 10) ikke i blokkeringsliste for gjester. Seksjon 12: captive-portal-testene skal gi 204 og 200 «Success». | Blokkert QUIC gjør Google/YouTube tregere og gir merkelige feil. Blokkerte CDN-er gir «video buffrer» (seksjon 10 FAIL) mens hastighetstesten er fin. |
| ☐ SQM/QoS mot bufferbloat | Admin-UI: trafikkforming / QoS (fq_codel, CAKE eller tilsvarende) | Aktivert på WAN, satt til ca. 90–95 % av **målt** WAN-hastighet begge veier. Seksjon 9: økning i median-RTT under nedlasting < 30 ms PASS, < 100 ms WARN, ≥ 100 ms FAIL. | Uten SQM: én gjest som laster opp video gjør videomøtene på Adm-nett hakkete. Feil satt (for høyt) virker ikke; for lavt kaster bort båndbredde. |
| ☐ UPnP av | Admin-UI: UPnP/NAT-PMP | Av. | Enhver gjesteenhet kan ellers åpne porter innover. |
| ☐ IPv6-brannmur tilstandsbasert | Admin-UI: IPv6-regler | Innkommende IPv6 nektet som standard, kun etablerte/relaterte tilbake. | Med IPv6 er hver enhet direkte adresserbar fra internett hvis brannmuren ikke stopper det. |
| ☐ Reserve-WAN (failover) hvis det finnes | Admin-UI: WAN-grupper / failover | Testet nylig (dato ____), overvåket, og tilbakefall til fiber skjer automatisk. | Utestet failover virker ikke den dagen du trenger den. Manglende tilbakefall lar deg gå på 4G i uker uten å merke det. |
| ☐ CPU-, minne- og sesjonsgrafer | Admin-UI: dashbord/overvåking | Topper under 70–80 % i høysesong. Noter toppverdier: CPU ____ %, sesjoner ____. | En brannmur i knestående gir høy jitter og pakketap for alle — det ligner på Wi-Fi-problemer, men er det ikke. |
| ☐ IGMP-proxy/snooping hvis IPTV/multicast | Admin-UI: multicast | Bare på hvis det faktisk brukes IPTV eller multicast, og da konsekvent med svitsjen. | Ukontrollert multicast fyller Wi-Fi-luften (sendes på laveste rate). |
| ☐ Geo-/trusselblokkering treffer ikke norske tjenester | Admin-UI: geo-blokkering / trusselfeeder | nrk.no, vg.no, telenor.no (seksjon 5/7-målene), bank/BankID, Vipps, offentlige tjenester og XIQ-endepunkter er ikke blokkert. | For ivrig blokkering ser ut som «internett virker delvis» og er vanskelig å feilsøke uten logg. |

> **Målinger som isolerer dette leddet**
> - Ping til brannmurens LAN-IP fra en **kablet** vert på samme svitsj: < 1 ms, 0 % tap, jitter < 1 ms. Sammenlign med seksjon 5 fra Wi-Fi-klienten (PASS ≤ 10 ms, 0 % tap, jitter < 5 ms): differansen er svitsj + AP + luft.
> - RTT til hopp 2 (seksjon 6) minus RTT til gateway (seksjon 5): brannmurens eget bidrag skal være ~0–1 ms. Er det flere ms, er brannmuren belastet (CPU, sesjonstabell, DPI).
> - DNS: seksjon 4 spør både brannmurens videresender og 1.1.1.1/8.8.8.8/9.9.9.9 direkte. Er direkte-oppslag raske, men brannmurens trege eller feilende, er det brannmurens DNS.
> - Bufferbloat (seksjon 9) fra en **kablet** vert: FAIL der betyr WAN/SQM, ikke Wi-Fi.
> - Regler mot AP-VLAN: koble en kablet PC til en svitsjport i AP-ens administrasjons-VLAN og kjør sjekk-klient derfra; XIQ-forutsetningene i rapporten gjelder da faktisk AP-enes vei ut. AP-ens eget svar er `show capwap client` (vedlegg).
> - Brannmurens egne grafer i samme tidsrom som klientrapporten: CPU-topp, sesjoner, WAN-utnyttelse.

---

## Ledd C — Svitsj

Svitsjen er lag 2-transporten mellom brannmur og AP-er, leverer strøm (PoE) til AP-ene og bærer VLAN-taggingen som gjør at hvert SSID havner i riktig nett. Feil her viser seg som «rare» problemer på ett AP, som duplikate adresser, eller som hastighet som aldri når over 100 Mbit/s. Klientskriptets **seksjon 2 IP og TCP/IP** (adresser, ARP, default-ruter), MTU/PMTU-testen i **seksjon 5**, **7 TCP-ytelse** (retransmisjoner) og **8 Hastighet via iperf** (`--iperf-server` / -IperfServer mot en kablet vert) speiler dette leddet.

**Modell/firmware: ____**

| Sjekk | Hvor (UI/CLI) | Forventet / terskel | Vanlig feil og konsekvens |
|---|---|---|---|
| ☐ Firmware og konfig-sikkerhetskopi | Admin-UI/CLI: system, sikkerhetskopi | Støttet firmware, sikkerhetskopi datert ____ lagret eksternt. | Se brannmur — samme konsekvens. |
| ☐ STP/RSTP: rotbro valgt bevisst | Admin-UI/CLI: spanning tree-status, rotbro-ID, prioritet | RSTP (ikke gammel STP). Kjernesvitsjen har lavest prioritet (f.eks. 4096) og er rot. Antall topologiendringer stabilt. | Rot havner på en tilfeldig liten svitsj eller et AP → dårlig sti. Hyppige topologiendringer gir 30 sekunders «pauser» i hele nettet. |
| ☐ Edge/portfast + BPDU guard på AP- og tilgangsporter | Admin-UI/CLI: port-STP-innstillinger | AP-porter og tilgangsporter satt som edge/portfast med BPDU guard. Uplink ikke edge. | Uten edge: AP-en venter 30 s på lenke etter omstart. Uten BPDU guard: en gjest med en «switch fra Elkjøp» kan ta over topologien. |
| ☐ Stormkontroll | Admin-UI/CLI: storm control per port | Broadcast/multicast begrenset på tilgangs- og AP-porter (nivå etter produsentens anbefaling). | Én defekt enhet med broadcast-storm legger ned hele campingen. |
| ☐ Sløyfebeskyttelse (loop protection) | Admin-UI/CLI: loop protection/loop detect | På. | Kabel som patches i to porter på samme svitsj (skjer i kiosker) gir full stopp. |
| ☐ PoE-budsjett mot AP-enes forbruk | Admin-UI/CLI: PoE-status per port, totalt budsjett | Sum av AP-enes maksforbruk < svitsjens PoE-budsjett med ~20 % margin. AP460C trenger 802.3at/PoE+ (sjekk databladet). AP305C/AP305CX kjører på 802.3af med reduserte funksjoner — hva som reduseres: sjekk databladet, og gi dem helst 802.3at. Atom AP30 er en vegguttaks-AP uten PoE. Noter: budsjett ____ W, brukt ____ W. | Overtrukket budsjett: AP-er starter på nytt, mister radioer eller kommer aldri opp, og XIQ viser «CAPWAP connection was lost» i bølger. |
| ☐ LLDP / LLDP-MED på | Admin-UI/CLI: LLDP-naboer; AP: `show lldp neighbor` | LLDP på alle AP-porter og uplink. XIQ viser da riktig svitsj/port for hvert AP, og PoE forhandles via LLDP-MED. | Uten LLDP forhandles PoE bare på klasse, og AP-en kan få for lite strøm; XIQ-topologien blir tom. |
| ☐ Portfeil: CRC/FCS, drops, late collisions | Admin-UI/CLI: portstatistikk per port | Null eller ikke-økende feiltellere på AP-porter og uplink. Noter tallene nå og sammenlign etter 24 timer. | CRC/FCS-feil = dårlig kabel/kontakt/lengde. Late collisions = dupleks-mismatch. Konsekvens: retransmisjoner (seksjon 7 FAIL ≥ 2 %) og lav hastighet på ett AP. |
| ☐ Hastighet/dupleks matcher AP-ens kapasitet | Admin-UI/CLI: portstatus | 1000/full mot hvert AP som minimum. mGig (2,5G) der AP-en støtter det — sjekk databladet for AP305C/CX og AP460C, og at svitsjporten støtter det. | 100/half etter en dårlig kabel begrenser hele AP-en til under 100 Mbit/s uansett hvor fin luften er. |
| ☐ Ensartet trunk-konfig på alle AP-porter | Admin-UI/CLI: VLAN-medlemskap per port | Native/utagget = AP-administrasjons-VLAN (der AP-en får IP), tagget = VLAN for Adm-nett, gjest, IoT osv. Identisk på alle AP-porter og på uplink mot brannmur. | Ett AP-port uten gjeste-VLAN tagget: klienter på det AP-et får 169.254-adresse (seksjon 3 FAIL) eller havner i feil nett. |
| ☐ Ubrukte porter deaktivert eller i «svart hull»-VLAN | Admin-UI/CLI: portstatus/VLAN | Ubrukte porter administrativt nede, eller parkert i et VLAN uten gateway. | Åpen port i trafokiosken = direkte vei inn i administrasjons-VLAN. |
| ☐ Administrasjon kun i administrasjons-VLAN | Admin-UI/CLI: management-IP/VLAN | Svitsjens IP ligger i administrasjons-VLAN, ikke i gjeste-VLAN. Reservasjon i DHCP eller statisk, dokumentert. | Svitsj-UI synlig fra gjestenettet. |
| ☐ SNMPv3 — ingen v1/v2c med «public» | Admin-UI/CLI: SNMP | SNMPv3 med autentisering og kryptering hvis overvåking brukes; v1/v2c og «public/private» fjernet. | Alle på nettet kan lese (og noen ganger skrive) svitsjens konfig. |
| ☐ NTP og syslog | Admin-UI/CLI: tid og logging | NTP satt (samme kilde som brannmur), syslog til samme mottaker. | Uten tidsstempel kan ikke svitsjlogg og AP-logg sammenholdes. |
| ☐ IGMP snooping | Admin-UI/CLI: multicast | På med querier hvis IPTV/multicast brukes; konsekvent med brannmuren. Ellers vurder av — snooping uten querier kan stoppe multicast. | Multicast flommer alle porter (og luften) hvis snooping mangler, eller stopper helt hvis querier mangler. |
| ☐ Kabelstrekk > 90 m og utendørsstrekk | Patch-liste / befaring | Kobber maks 90 m + patcher (100 m totalt). Lengre strekk og strekk mellom bygg → fiber eller mediekonvertere. Utendørs kabel skal være utendørsgradert (UV/vann). | På en camping er strekkene lange: kabler over 100 m gir CRC-feil og 100 Mbit/s-forhandling; innendørskabel utendørs råtner. |
| ☐ Skjermet kabel jordet + overspenningsvern mellom bygg | Befaring, elektriker | Skjermet kabel mellom bygg jordet i én ende etter regelverk, overspenningsvern på begge sider — eller fiber (galvanisk skille, best). | Lynnedslag og potensialforskjeller mellom bygg tar med seg svitsjporter og AP-er. |
| ☐ Jumbo frames ikke nødvendig, MTU 1500 | Admin-UI/CLI: MTU per port | 1500 overalt (samme som brannmur og AP). | Blandet MTU gir stille pakketap for store pakker — ligner PMTUD-svart hull. |
| ☐ Uplink mot brannmur: hastighet/dupleks | Admin-UI/CLI: uplink-port | 1000/full (eller høyere hvis begge støtter det), trunk med alle VLAN, ingen feiltellere. | Uplinken er alles flaskehals: en 100 Mbit/s-forhandling her begrenser hele campingen. |
| ☐ Portbeskrivelser fylt ut | Admin-UI/CLI: portbeskrivelse | Hver port har navn: «AP-resepsjon», «Uplink brannmur», «Kiosk PC». | Uten navn feilsøker du med lommelykt og kabelfølging i trafokiosken. |

> **Målinger som isolerer dette leddet**
> - iperf3 mellom **to kablede verter på samme svitsj** (`iperf3 -s` på den ene, `iperf3 -c <ip> -t 20` på den andre, deretter `-R`): ca. 930–940 Mbit/s på 1 GbE i begge retninger, 0 retransmisjoner. Lavere → port, kabel eller svitsj.
> - Ping mellom de to kablede vertene: < 1 ms, 0 % tap.
> - Feiltellere på begge porter og uplink før og etter testen: skal ikke øke.
> - Kjør deretter sjekk-klient fra Wi-Fi-klienten med `--iperf-server <kablet vert>` (-IperfServer): differansen mellom kablet↔kablet og Wi-Fi↔kablet er AP-leddet, ikke svitsjen.
> - PoE-status per port under last (alle radioer aktive): tildelt effekt/klasse mot AP-ens behov.

---

## Ledd D — AP (Extreme Networks / ExtremeCloudIQ)

AP-ene (AP305C, AP305CX, AP460C og Atom AP30) gir klientene lenke og radio, tagger trafikken inn i riktig VLAN og rapporterer til XIQ. XIQ er administrasjon og telemetri — mister AP-en kontakten med skyen, fortsetter den å levere Wi-Fi med siste konfigurasjon. Klientskriptets **seksjon 1 Lenke og Wi-Fi** (RSSI, SNR, bånd, PHY-rate) og **11 Roaming** speiler dette leddet, sammen med **roaming-logg.sh / roaming-logg.ps1** for vandring rundt på området. XIQ-forutsetningene i **seksjon 6** av klientrapporten (DNS + TCP 443 mot `redirector.aerohive.com` og `extremecloudiq.com`, INFO) viser hva AP-ene trenger ut mot skyen.

Menynavnene under er slik de vanligvis heter i XIQ; de kan avvike litt mellom versjoner. AP-CLI-kommandoene står i vedlegget.

| Sjekk | Hvor (UI/CLI) | Forventet / terskel | Vanlig feil og konsekvens |
|---|---|---|---|
| ☐ Alle AP-er «Connected» og «Managed» | XIQ: Manage → Devices | Alle enheter grønne, «Managed», ingen «Disconnected»/«Unmanaged». Noter antall AP-er: ____ | Et AP som er «Disconnected» leverer kanskje Wi-Fi ennå, men får ingen konfigendringer og rapporterer ingenting. |
| ☐ Samme IQ Engine-versjon på alle AP-er | XIQ: Manage → Devices (kolonne IQ Engine) | Samme versjon per plattform; oppdatering i vedlikeholdsvindu (AP-en starter på nytt). | Blandede versjoner gir ulik roaming-oppførsel og funksjoner som virker på noen AP-er og ikke andre. |
| ☐ CAPWAP-tilstand og hva «CAPWAP connection was lost» betyr | AP-CLI: `show capwap client`; XIQ: hendelser/alarmer for AP-en | CAPWAP mot XIQ i kjøretilstand med korrekt server. «CAPWAP connection was lost» = administrasjons-/telemetrilenken til XIQ falt ut; lokal Wi-Fi-tjeneste fortsetter. Sjekk i rekkefølge: strøm/PoE, lenke, DHCP i AP-VLAN, DNS, UDP 12222 og TCP 443 ut, NTP, brannmurens UDP-timeout. | Gjentatte hendelser på alle AP-er samtidig = brannmur/WAN/DHCP. På ett AP = PoE, kabel eller port. |
| ☐ DNS, NTP og gateway nås fra AP-en | AP-CLI: `show ip route` (default-rute mot gateway), `ping <gateway>`, `ping 1.1.1.1`, `ping redirector.aerohive.com` | Default-rute til riktig gateway, ping svarer, navnet slår opp. | AP med IP, men uten DNS, kommer aldri til XIQ. Feil gateway = AP-VLAN uten rute. |
| ☐ Radio 2,4 GHz: 20 MHz, kanal 1/6/11, lavere effekt enn 5 GHz | XIQ: Configure → Common Objects → Radio Profiles (eller via enhetsmalen i nettverkspolicyen); AP-CLI: `show interface wifi0` | 20 MHz kanalbredde, bare kanal 1, 6 og 11, sendeeffekt tydelig lavere enn 5 GHz. Klient tilkoblet på 2,4 GHz gir WARN i seksjon 1. | 40 MHz eller «alle kanaler» på 2,4 GHz overlapper naboene. For høy effekt på 2,4 GHz gjør klienter «klissete» der og hindrer dem i å velge 5 GHz. |
| ☐ Radio 5 GHz: 40 MHz, ACSP kjører, fornuftig kanalplan | XIQ: radioprofil; AP-CLI: `show acsp`, `show acsp neighbor` | 40 MHz (80 MHz bare med få AP-er og lite naboer). ACSP i kjøretilstand med ferdig valgt kanal; nabo-AP-er på ulike kanaler. | 80 MHz på mange AP-er gir samkanalstøy og lavere total kapasitet. ACSP som aldri blir ferdig hopper kanal og kaster ut klienter. |
| ☐ DFS: radarhendelser på et kystnært anlegg | AP-CLI: `show logging buffered` (søk etter «DFS»/«radar»); XIQ: hendelser for AP-en | Ingen eller sjeldne DFS-hendelser. Ved hendelser på innendørs-AP-er: vurder ikke-DFS-kanaler (36–48). Merk: i Norge/EU er 5150–5350 MHz (kanal 36–64) normalt kun tillatt innendørs, så utendørs-AP-en (AP460C) må bruke DFS-kanalene 100–140 — bekreft mot Nkom-regelverket og landkoden i XIQ. | Skipsradar langs kysten trigger DFS: AP-en må forlate kanalen umiddelbart og alle klienter mister lenken i sekunder til minutter. |
| ☐ Båndstyring / dual-5G, klientlastbalansering | XIQ: SSID-/radioprofil (band steering, load balancing) | Båndstyring på slik at 5 GHz foretrekkes. Lastbalansering forsiktig — kan avvise klienter i kanten. Dual-5G på AP-er som støtter det (sjekk databladet) bare med god kanalplan. | For aggressiv balansering gir «får ikke koble til» ved AP-er med mange klienter. |
| ☐ 802.11k (naboliste) og 802.11v (BSS transition) på | XIQ: SSID-innstillinger / radioprofil (802.11k/v) | Begge på, på alle SSID-er. Seksjon 11 og roaming-loggen viser om klienter faktisk roamer i tide. | Uten k/v henger klienter igjen på fjerne AP-er («sticky client») med lav rate og høy luftbruk for alle. |
| ☐ 802.11r (fast transition) bare med WPA2/3-PSK og bare hvis klientene støtter det | XIQ: SSID-innstillinger (802.11r) | Av som standard på gjestenett (ukjente klienter). På Adm-nett kun hvis alle kjente klienter støtter FT; test med roaming-loggen. | Eldre klienter og enkelte IoT-enheter kobler ikke til i det hele tatt når FT er på. |
| ☐ Laveste basisrater | XIQ: radioprofil (rate sets) | 2,4 GHz: 1, 2 og 5,5 Mbit/s deaktivert, basisrate 11 eller 12 Mbit/s. 5 GHz: 12 Mbit/s som basisrate. | Med 1 Mbit/s tillatt sendes beacon/multicast ekstremt sakte og cellene «vokser» langt utover nyttig rekkevidde — det ødelegger roaming og kapasitet. |
| ☐ DTIM 1–3 | XIQ: SSID-innstillinger | DTIM 1–3 (lav for sanntid/roaming, 2–3 sparer batteri). | Høy DTIM gir treg multicast/mDNS og «ser ikke Chromecast/skriver». |
| ☐ Maks 4 SSID per radio | XIQ: nettverkspolicy → SSID-er per AP-mal | ≤ 4 SSID per radio. Adm-nett, Marivold, Marivold-5G og ev. ett til — vurder om alle trengs. | Hver SSID sender beacons hele tiden; åtte SSID-er bruker en stor del av lufttiden på ingenting. |
| ☐ Klientisolasjon på gjeste-SSID | XIQ: SSID-innstillinger (isolasjon / trafikk mellom klienter) | På for gjestenett. Av for Adm-nett (skrivere, Chromecast) — men da med VLAN-skille i stedet. | Uten isolasjon kan gjester skanne og angripe hverandre — og Adm-nett-enheter, hvis VLAN-planen også er svak. |
| ☐ PSK-hygiene og rotasjon | XIQ: SSID-innstillinger; passordhvelv | Adm-nett: langt, unikt PSK som bare finnes i hvelvet (skriptene leser aldri PSK). Gjest: roteres hver sesong, dato ____. Ingen PSK i chat/e-post. | Et gjeste-PSK som har vært det samme i fem år står på alle nabocampingenes oppslagstavler. |
| ☐ WPA3 eller WPA2/3-overgang på Adm-nett | XIQ: SSID-innstillinger (sikkerhet) | WPA3-Personal eller WPA2/WPA3-overgangsmodus med PMF. Aldri WPA/TKIP. | TKIP begrenser rate til 54 Mbit/s og er usikkert. Ren WPA3 uten overgangsmodus kan stenge ute eldre Adm-nett-enheter — test først. |
| ☐ Klientgrense per radio | XIQ: radioprofil / SSID (maks klienter) | Satt til et nivå som passer AP-en og formålet (gjestenett gjerne 50–100 per radio); noter valgt verdi: ____. | Uten grense samler ett populært AP alle klienter mens nabo-AP-en står tom. |
| ☐ Airtime fairness | XIQ: radioprofil | På. | Én gammel 802.11g-klient i kanten kan ellers spise mesteparten av lufttiden. |
| ☐ Svak-signal-probeundertrykking / «safety net» (hvis brukt) | XIQ: radioprofil (weak signal probe suppression, safety net) | Enten av, eller forsiktig terskel med «safety net» på så klienter uten alternativ likevel slipper inn. Test i kanten av dekningen. | For streng terskel = «finner nettet, men får ikke koble til» i ytterkanten av campingen. |
| ☐ Kanalutnyttelse < 50 % og støygulv | XIQ: ML Insights → Network 360 Monitor → Wireless Health; Device 360 for hvert AP; Client 360 for én klient; AP-CLI: `show interface wifi0` / `wifi1` | Kanalutnyttelse < 50 % i rushtid. Støygulv rundt -95 dBm er normalt; nærmere -85 dBm eller høyere betyr støy. Seksjon 1: SNR ≥ 25 dB PASS, ≥ 15 dB WARN, < 15 dB FAIL. | Høy utnyttelse med få egne klienter = naboer eller støy. Høyt støygulv gir lav SNR selv med sterkt signal — klassisk «full styrke, men tregt». |
| ☐ Retransmisjoner (retries) | XIQ: Wireless Health / Client 360; AP-CLI: `show station` | Lavt retry-nivå; jevnt over 15–20 % tyder på støy, interferens eller for høy sendeeffekt/for store celler. | Høye retries = lav reell hastighet og dårlig video selv om PHY-raten ser fin ut. |
| ☐ Interferenskilder på en camping | Befaring + Wireless Health over tid | Kjente kilder notert: mikrobølgeovner (2,4 GHz), skipsradar (5 GHz DFS), DECT-telefoner, Bluetooth, mobile hotspots og bobil-rutere hos gjestene (2,4 og 5 GHz), naboenes Wi-Fi. | Interferens er ofte tidsavhengig (middagstid, helg). Sammenlign målinger på ulike tidspunkter før du endrer kanalplan. |
| ☐ Dekningsoverlapp: cellekant ved -67 til -70 dBm | roaming-logg.sh/.ps1 mens du går; seksjon 1 på faste punkter; XIQ: Client 360 | På grensen mellom to AP-er skal begge høres ved omtrent -67 til -70 dBm. Seksjon 1: RSSI ≥ -65 dBm PASS, ≥ -72 dBm WARN, < -72 dBm FAIL. | For lite overlapp: klienten faller til 2,4 GHz eller mister lenken før den finner neste AP. For mye: alle AP-er hører alle klienter og samkanalstøyen øker. |
| ☐ Atom AP30: kablet eller mesh-tilkobling? | XIQ: Device 360 for hver Atom; AP-CLI: `show interface eth0`, `show amrp neighbor` | Helst kablet (eth0 opp med lenke). Mesh bare der kabel er umulig, med sterk lenke til rot-AP. Noter per Atom: kablet / mesh. | Mesh halverer gjennomstrømningen per hopp og arver rot-AP-ens kanalbelastning. En Atom på mesh i kanten gir «Wi-Fi virker, men alt er tregt» for dem den betjener. |
| ☐ Plassering, montering og utendørsgradering | Befaring | Innendørs-AP-er i fri sikt (ikke i skap, over himling eller bak metall). AP460C montert som utendørs-AP med riktig kapsling og antenner (IP-gradering: sjekk databladet). Riktig høyde og antenneretning. | AP i et metallskap i trafokiosken dekker trafokiosken. Innendørs-AP utendørs dør ved første vinter. |
| ☐ PoE-klasse forhandlet | AP-CLI: `show lldp neighbor`, `show interface eth0`; svitsjens PoE-status per port | Den effekten AP-en trenger for alle radioer (AP460C: 802.3at/PoE+, sjekk databladet). | AP som får for lite strøm slår av en radio eller kjører redusert — uten tydelig feilmelding hos klienten. |
| ☐ Oppetid og siste omstartsårsak | AP-CLI: `show version` (oppetid), `show logging buffered` (omstart/årsak); XIQ: Device 360 | Lang oppetid, planlagte omstarter kun ved oppdatering. | Korte oppetider/omstarter uten plan = PoE-budsjett, kabel, firmwarefeil eller strømblink i kiosken. |
| ☐ Konfig-sikkerhetskopi | XIQ (skyen holder konfigurasjonen) + lagret `show running-config` per AP via plink, datert ____ | Både XIQ-policyen og en tekstkopi av hver AP-s kjørende konfig i dokumentasjonsmappen. | Uten tekstkopi er det vanskelig å se hva som faktisk endret seg mellom to datoer. |
| ☐ Admin-kontoer og MFA i XIQ | XIQ: Global Settings → Accounts / brukeradministrasjon | Én navngitt konto per person, minste nødvendige rolle, tofaktor på der det tilbys. Ingen delte kontoer. | Delt XIQ-konto uten MFA gir full kontroll over alle AP-er til den som finner passordet. |
| ☐ Varsler/e-post i XIQ | XIQ: Manage → Alerts (regler og varslingsmottakere) | E-post ved AP «Disconnected», CAPWAP-tap, høy kanalutnyttelse og oppdateringsfeil. Mottaker: ____ | Uten varsler oppdages et dødt AP først når gjestene klager. |

> **Målinger som isolerer dette leddet**
> - iperf3 fra en **kablet vert på samme svitsj** (`--iperf-server` / -IperfServer i sjekk-klient) til en Wi-Fi-klient som står nær AP-en: differansen mot kablet↔kablet er Wi-Fi-leddet. Forventet verdi avhenger av AP-modell, bånd, kanalbredde og klientens antenner (2×2 på 5 GHz/80 MHz gir typisk noen hundre Mbit/s; sjekk databladet for teoretisk maks).
> - Samme klient mot **to ulike AP-er** (gå til hver): ulikt resultat = AP/plassering/kanal. Samme AP med **to ulike klienter**: ulikt resultat = klienten.
> - Seksjon 1 fra klienten på stedet (RSSI, SNR, PHY-rate, bånd) samtidig med kanalutnyttelse i XIQ for samme AP og tidspunkt.
> - roaming-logg mens du går ruten resepsjon → plasser → sanitærbygg: roam-hendelser med små avbrudd og ingen «sticky client»-episoder (se oppsummeringen loggen skriver).
> - AP-CLI: `show station` (per klient: RSSI, rate, retries), `show interface wifi0` / `wifi1` (kanal, effekt, utnyttelse), `show acsp neighbor` (hvem AP-en hører og på hvilke kanaler).

---

## Ledd E — Klient

Klienten er der målingene tas, og klientskriptene dekker det meste av dette leddet (seksjon 0, 1, 2, 3, 4 og 12). Listen under er de innstillingene som oftest gir «bare min PC har problemer».

| Sjekk | Hvor (UI/CLI) | Forventet / terskel | Vanlig feil og konsekvens |
|---|---|---|---|
| ☐ Driver/firmware for Wi-Fi-kortet oppdatert | Windows: Enhetsbehandling → nettverkskort → driverversjon; produsentens driver (f.eks. Intel), ikke bare Windows Update | Nyeste driver fra kortprodusenten. Seksjon 0 viser OS og adapter. | Gamle drivere gir dårlig roaming, manglende 802.11ax/WPA3 og tilfeldige frakoblinger. |
| ☐ Strømstyring av for Wi-Fi-kortet | Windows: adapterens egenskaper → Strømstyring; Intel-innstillinger for strømsparing | «La datamaskinen slå av denne enheten» av på arbeidsmaskiner; strømsparing lav/av under målinger. | Strømsparing gir høy jitter og tapte pakker mot gateway (seksjon 5 WARN) og tregere roaming. |
| ☐ Roaming-aggressivitet middels-høy og foretrukket bånd 5 GHz (Intel) | Windows: adapterens egenskaper → Avansert (Roaming Aggressiveness, Preferred Band) | «Medium-High» og «Prefer 5GHz band» på Intel-kort; tilsvarende hos andre produsenter. | Standardinnstillingen holder på det gamle AP-et for lenge (seksjon 11 / roaming-logg viser «sticky»). |
| ☐ 802.11ax aktivert | Windows: adapterens egenskaper → Avansert (trådløsmodus) | 802.11ax (Wi-Fi 6) på. Seksjon 1 viser PHY som INFO. | Kort låst til 802.11n/ac gir lavere rate og eldre roaming-funksjoner. |
| ☐ Tilfeldig/privat MAC-adresse per SSID | Windows: Wi-Fi-innstillinger → nettverket → «Tilfeldige maskinvareadresser»; iOS: «Privat Wi-Fi-adresse»; Android: «Randomisert MAC» | **Av** for Adm-nett på enheter med DHCP-reservasjon eller MAC-basert tilgang. På gjestenett spiller det ingen rolle. | Tilfeldig MAC gjør at DHCP-reservasjoner og MAC-ACL-er på Adm-nett ikke treffer: enheten får «feil» IP eller ingen. iOS/Android kan også bytte adresse per SSID og over tid. |
| ☐ Ingen statisk IP eller DNS-overstyring | Windows: adapterens IPv4-innstillinger; seksjon 2 og 4 i rapporten | DHCP for både IP og DNS med mindre det er dokumentert. | En glemt statisk DNS (f.eks. 8.8.8.8) skjuler feil på brannmurens DNS, og statisk IP kolliderer når planen endres. |
| ☐ Nettleser-DoH (DNS over HTTPS) | Nettleserens innstillinger (Chrome/Edge: sikker DNS; Firefox: DNS over HTTPS) | Vær klar over om den er på. Seksjon 4 tester **operativsystemets** resolver — en nettleser med DoH går utenom brannmurens DNS og lokale navn. | «Interne navn virker i terminal, men ikke i nettleseren» = DoH. |
| ☐ VPN av under testing | Klientens VPN-app | Av mens sjekk-klient og roaming-logg kjører. Seksjon 12 gir WARN ved aktiv VPN (målingene går gjennom tunnelen). | Med VPN på måler du VPN-leverandøren, ikke Marivold-nettet. |
| ☐ Vertsbrannmur på | Windows: Windows-sikkerhet → Brannmur | På, med Adm-nett satt som privat/pålitelig nett om nødvendig for skrivere. | Av brannmur på en admin-PC på et delt nett er en unødvendig risiko. |
| ☐ Klokke synkronisert | Windows: Dato og klokkeslett → synkroniser; seksjon 12 (NTP) | Avvik < 1 s PASS, < 5 s WARN, ellers FAIL; ikke synkronisert → FAIL. | Feil klokke gir TLS-feil og «kan ikke logge inn i XIQ» på klienten. |
| ☐ Oppdateringer installert | Windows Update / OS-oppdatering | Nyeste OS-oppdateringer (Wi-Fi-stakken oppdateres ofte via OS). | Kjente Wi-Fi-feil i OS-et som allerede er rettet. |

> **Målinger som isolerer dette leddet**
> - Kjør sjekk-klient på **to ulike klienter på samme AP** samtidig: avvik på bare én av dem er klienten.
> - Samme PC **kablet** (USB-Ethernet) i en svitsjport i Adm-nett-VLAN mot **trådløst**: alt som forsvinner når du er kablet, er Wi-Fi-kortet/driveren/AP-leddet.
> - Sammenlign seksjon 1 (RSSI/SNR/PHY) mellom klientene på samme sted: en klient med 10 dB dårligere RSSI enn de andre har antenne-/driverproblem.

---

## Dokumentasjonshygiene

Dokumentasjonen er det som gjør at neste feil løses på ti minutter i stedet for en hel kveld i trafokiosken. Alt under bør ligge samlet (delt mappe eller wiki), være datert, og ha én ansvarlig.

| Dokument | Innhold | Hvor det ligger / oppdatert sist |
|---|---|---|
| ☐ IP-plan | Per VLAN: nett, gateway, DHCP-scope (fra–til), reservasjoner og statiske adresser (brannmur, svitsj, hvert AP, skrivere, kasse, kamera), DNS-navn. | ____ |
| ☐ VLAN-plan | VLAN-ID, navn, formål (Adm-nett, Marivold/gjest, Marivold-5G, IoT, AP-administrasjon), hvilke SSID-er som havner hvor, regler mellom VLAN. | ____ |
| ☐ Patch-liste | Svitsjport → kabel-ID → endepunkt (AP-navn/plassering, uplink, bygg), kabellengde/type, PoE ja/nei. Skisse over campingen med AP-plasseringer. | ____ |
| ☐ Konfig-sikkerhetskopier | Brannmur, svitsj og `show running-config` per AP, datert filnavn, minst siste tre versjoner. Kopi utenfor trafokiosken. | ____ |
| ☐ Passordhvelv | Admin-kontoer for brannmur, svitsj, XIQ, ONT (hvis tilgjengelig), AP-CLI, ISP-portal; Wi-Fi-PSK-er. Aldri i chat, e-post eller på lapper i kiosken. | ____ |
| ☐ Endringslogg | Dato, hvem, hva, hvorfor, hvordan rulle tilbake. Særlig for radioprofil-endringer (11ax, kanalbredde, kort guardintervall, ACSP, BSS transition, rate sets) — de er lette å glemme og vanskelige å se i ettertid. | ____ |
| ☐ Overvåking og varsler | Hva som overvåkes (XIQ-varsler, brannmurens grafer, ev. ping-overvåking av AP-er), hvem som får e-post, hva som skal gjøres ved hvert varsel. | ____ |
| ☐ Leverandør- og SLA-kontakter | ISP (se Ledd A), maskinvareleverandør, XIQ-lisens/-utløp, elektriker for trafokiosken. | ____ |
| ☐ Rapportarkiv fra nettsjekk | `nettsjekk-rapport-*.md/.json` og `roaming-logg-*` fra kjente gode dager, som referanse når noe endrer seg. | ____ |

---

## Vedlegg — Extreme AP CLI (IQ Engine / HiveOS): nyttige read-only kommandoer

Logg inn med plink fra admin-PC-en, f.eks. `plink -ssh admin@<ap-ip> "show version"` (Windows) — eller interaktivt med PuTTY. Alle kommandoene under leser bare ut tilstand og endrer ingenting. Nøyaktig syntaks og utdata varierer mellom versjoner av IQ Engine/HiveOS (og den gamle AP141 skiller seg fra AP305C/AP460C) — trykk `?` på enheten for å bekrefte kommandoen før du stoler på den.

| Kommando | Hva du ser etter |
|---|---|
| `show version` | Firmware-/IQ Engine-versjon (skal være lik på alle AP-er av samme plattform) og oppetid (kort oppetid = uplanlagt omstart). |
| `show running-config` | Hele kjørende konfigurasjonen — lagre utskriften datert som sikkerhetskopi og sammenlign mellom AP-er/datoer. |
| `show interface` | Oversikt over alle grensesnitt: hvilke som er oppe, IP på mgt0, radioene wifi0/wifi1 og deres modus. |
| `show interface mgt0` | AP-ens administrasjonsgrensesnitt: IP-adresse, nettmaske, VLAN, DHCP/statisk — skal stemme med IP-planen og reservasjonen. |
| `show interface eth0` | Kablet uplink: lenke opp, hastighet og dupleks (1000/full som minimum, mGig der det støttes), feiltellere. |
| `show interface wifi0` / `show interface wifi1` | Per radio: bånd, kanal, kanalbredde, sendeeffekt, modus (11ax), antall klienter — sammenlign med radioprofilen i XIQ. |
| `show acsp` | Status for automatisk kanal-/effektvalg: i kjøretilstand med ferdig valgt kanal, eller står den fast i skanning? |
| `show acsp neighbor` | Hvilke nabo-AP-er (egne og fremmede) AP-en hører, på hvilke kanaler og hvor sterkt — grunnlaget for kanalplanen og for å finne interferens. |
| `show capwap client` | CAPWAP-tilstand mot XIQ: server, transport/port, tilstand (skal være kjøretilstand) — første stopp ved «CAPWAP connection was lost». |
| `show station` | Tilkoblede klienter: MAC, SSID, kanal, RSSI, rate, retries, tilkoblingstid — finn klienter med svakt signal eller høye retries. |
| `show roaming cache` | Roaming-cache: hvilke klienter/naboer AP-en har nøkler for — tomt eller manglende naboer tyder på at roaming ikke er satt opp slik du tror. |
| `show ip route` | Rutetabell: default-rute skal peke på riktig gateway i AP-VLAN; ingen rute = AP-en når ikke XIQ. |
| `show lldp neighbor` | Hvilken svitsj og port AP-en henger på, og PoE-forhandling via LLDP-MED — bekreft patch-listen. |
| `show amrp neighbor` | Naboer i AMRP (mesh/backhaul): for Atom AP30 viser den om AP-en går på mesh og mot hvem; ingen naboer = kablet eller mesh nede. |
| `show cpu` | CPU-belastning: vedvarende høy last gir treg roaming og tapte pakker. |
| `show memory` | Minnebruk: lite ledig minne over tid tyder på lekkasje — planlegg omstart/oppdatering i vedlikeholdsvindu. |
| `show logging buffered` | Loggbuffer: DFS/radarhendelser, CAPWAP-brudd og årsak, omstartsårsak, DHCP-/DNS-feil, klienter som avvises. |

Tips til bruk sammen med klientrapporten: kjør `show station` og `show interface wifi0`/`wifi1` på AP-en klienten er koblet til **samtidig** som sjekk-klient kjører seksjon 1 og 8, og lim begge deler inn i chatten. Da kan AP-ens og klientens syn på RSSI, rate og retries sammenholdes direkte.
