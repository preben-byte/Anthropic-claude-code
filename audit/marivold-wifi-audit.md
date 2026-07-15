# Marivold WiFi Audit — 2026-07-15

Denne rapporten er både en dokumentasjon av dagens tilstand og et selvstendig
handoff-dokument. Lim inn hele filen til Claude Code på PC-en for å fortsette
arbeidet uten å måtte forklare konteksten på nytt.

---

## Del 1: Kontekst (for Claude Code på PC-en)

Du hjelper med WiFi-optimalisering på **Marivold Resort**. Anlegget er
XIQ-managed under tenant `VHM-HCPDLLOM`. Adm-nettet oppleves «fullt», og
bruker ønsket først å heve `max clients` på tre AP-er — men diagnose viser at
det egentlige problemet er (a) DHCP-scope-utnyttelse og (b) alvorlig
kanalplan-feil på tvers av fire AP-er.

Utstyrspark og config er kartlagt via SSH-output fra fire AP-er. Ingen
endringer er utført enda — bruker venter på å utføre disse i XIQ og på Palo
Alto brannmuren.

**Bruker jobber lokalt med SSH til AP-er + GUI mot XIQ og Palo Alto.** Du
har ikke direkte tilgang til disse — din rolle er å gi eksakte kommandoer,
GUI-oppskrifter og verifikasjonssteg.

---

## Del 2: Utstyrsinventar

### Access points (alle Extreme AP460C, IQ Engine 10.8r7)

| Navn | Mgmt IP | Uplink switch | 2.4GHz-kanal | 5GHz-kanal | Adm-klienter |
|---|---|---|---|---|---|
| AP460c-Selvinnsjekk | 192.168.200.203 | X435-8P-4S | 1 | 149 | 2+1 |
| AP460-Stolpe | 192.168.200.179 | TSW202-skjaering (via .1.2) | 11 | 60 (DFS) | 1+0 |
| AP460c-Toalett | 192.168.200.183 | SW7-toalett (.8) | 11 | 157 | 1+0 |
| AP460c-Resepsjon | 192.168.200.144 | SW5-ButikkTEMP (.6) | 11 | 157 | 2+0 |

### Andre AP-er (identifisert via LLDP / naboer)
- **AP305cx-Gazastripe-Bobil-Ext** (192.168.200.138) — mesh backhaul til Toalett-APen
- Flere Aerohive/Extreme-AP-er sett i ACSP-scan (Vivendel, Marivold-ny osv)

### Switcher
- **SW5-ButikkTEMP** — HP J9774A 2530-8G-PoEP, YA.16.06.0006, 192.168.200.6
- **SW7-toalett** — HP J9774A 2530-8G-PoEP, YA.15.16.0006, 192.168.200.8
- **X435-8P-4S** — Extreme, ExtremeXOS 30.7.1.1 (des 2020), MAC 0004:96fb:db19, IP antas 192.168.200.3
- **TSW202-skjaering** — industriell gateway på 192.168.1.2 (annet subnet) — uplink for Stolpe-APen. **Undersøkes.**

### Brannmur
- **Palo Alto** på 192.168.200.1 (bekreftet via ARP + default gateway). Har ikke logget inn ennå.

### VLAN / subnet-oversikt
| VLAN | Navn | Subnet | User-profile |
|---|---|---|---|
| 10 | Adm-nett | 192.168.200.0/24 | `Adm-nett` |
| 20 | Marivold-guest | 192.168.202.0/24 | `Marivold-guest` (QoS Rate-Limit-1) |
| 40 | (ukjent) | 192.168.240.0/24 | — |
| — | Annet | 192.168.1.0/24 via TSW202 | — |

### Aktive SSID-er
- **Adm-nett** — WPA2-PSK AES, VLAN 10, kringkastet på både 2.4 og 5GHz på alle AP-er
- **Marivold-ny** — WPA2-PSK AES, VLAN 20, samme oppsett

---

## Del 3: Klienttall (hentet fra ARP-cacher på alle 4 AP-er)

- **Adm-nett (192.168.200.x)**: ~30 unike IP-er, hvorav 6–8 trådløse. Resten kabel.
- **Marivold-guest (192.168.202.x)**: 100+ unike IP-er. Nærmer seg fullt for et /24.

**Konklusjon**: «Fullt for IP-tilkoblede enheter»-meldingen brukeren har fått
gjelder trolig **guest-nettet, ikke Adm**. Må bekreftes på Palo Alto DHCP.

---

## Del 4: Kritiske funn (rangert)

### K1 — Kanalplan er brutt (2.4GHz)
Tre av fire AP-er kjører kanal 11 på 2.4GHz **samtidig**. Egne AP-er stjeler
airtime fra hverandre. Resepsjon-APen viser 24 % CRC error rate og 66 %
airtime utilization som direkte konsekvens.

### K2 — Kanalplan er brutt (5GHz)
Toalett og Resepsjon kjører begge kanal 157 på 5GHz. Samme problem, bare mindre synlig fordi 5GHz-cellene er mindre.

### K3 — ACSP (auto-channel) er disabled overalt
`show acsp _last-selection` viser `Disabled` for wifi0/wifi1 på alle AP-er.
Kanalene er manuelt låst av noen som ikke koordinerte på tvers av AP-er.

**Merk**: hvis du bare skrur på ACSP overalt samtidig, ender de fortsatt på
kanal 11 fordi ekstern interferens gjør 1 og 6 dyrere. ACSP-outputen fra
Stolpe viser: `ch1 cost 48, ch6 cost 20, ch11 cost 17`. Løsningen er
**manuell 1/6/11-plan basert på fysisk plassering**, ikke auto.

### K4 — 11ax-features slått av på tvers av alle AP-er
- **BSS Color = 0** (spatial reuse deaktivert)
- **MU-MIMO = disabled** på 5GHz (4x4-radio brukes som 1x1)
- **A-MSDU = disabled** (frame aggregation)
- **Tx Chain = static 2** på 2.4GHz på Resepsjon (kunne vært 4)

### K5 — Firmware/utstyr aldrende
- **X435 kjører 30.7.1.1** fra desember 2020. Fem år gammel.
- **HP 2530-serien** er 1 Gbit, 8 porter, 802.3at (ikke bt) — begrenser
  Wi-Fi 7 og full 460C USB-effekt.

### K6 — Adm-nett kringkastes på 5GHz uten klienter
Alle AP-er har `wifi1.2 SSID=Adm-nett` uten klienter. Enten er signalet for
svakt, klientene er 2.4-only (POS/skrivere), eller band steering mangler.
Verdt å vurdere Adm-nett som 2.4GHz-only for å frigjøre 5GHz-airtime til
guest.

### K7 — Merkelig arkitektur: Stolpe → TSW202 (192.168.1.2)
Stolpe-APen uplinker til en TSW202 industriell gateway på 192.168.1.2 —
helt annet subnet. **Årsak må undersøkes.** Kan være medieomformer, kan
være misconfig.

---

## Del 5: «Gjort riktig»-liste (bra ting)

- CAPWAP til XIQ stabil (Selvinnsjekk uptime 21 dager, 843 GB tunnellet)
- Temperatur på alle AP-er 41–44°C — OK
- Ingen radar detected på DFS-kanaler
- Mesh backhaul (Toalett ↔ Gazastripe-Bobil-Ext) fungerer
- PoE er 802.3at overalt, 7 W usage — god margin
- Klienter kobler seg på 11ax der utstyret støtter det

---

## Del 6: Prioritert fikselite

### P0 — Kanalplan (i XIQ Radio Profile / Device Template)
Manuell tildeling per AP:

| AP | 2.4GHz | 5GHz |
|---|---|---|
| Selvinnsjekk | 1 | 36 |
| Stolpe | 6 | 100 (DFS) |
| Toalett | 11 | 149 |
| Resepsjon | 6 | 157 |

Alternativ: slå på ACSP med **manual channel list** (bare tillat 1/6/11) og
la algoritmen fordele.

### P1 — 11ax-features (i Radio Profile)
På både `Marivold-AP460C-Outdoor-2G` og `-5G`:
- BSS Coloring: **Auto**
- MU-MIMO: **On** (5GHz)
- A-MSDU: **On**

### P2 — TX power ned
Radio Profile 2G: **Max TX = 10 dBm** (senk fra 12). Reduserer overlap
mellom dine egne AP-er.

### P3 — Verifiser guest-DHCP scope på Palo Alto
SSH til `admin@192.168.200.1`:
```
show dhcp server settings all
show dhcp server lease interface all
```
Sannsynlig funn: guest-scope er mindre enn /24 (f.eks. `.100-.200` = 100 addr).
Fix: utvid til hele /24 eller flytt til /23.

### P4 — Firmware
Oppgrader X435 fra 30.7.1.1 til nyeste 32.x GA. Etter det: vurder om
HP 2530 skal byttes.

### P5 — Undersøk TSW202
Hva står den for? Hvorfor uplinker Stolpe-APen gjennom `192.168.1.2`?

---

## Del 7: Neste steg for Claude Code

Når du blir promptet på PC-en, kan bruker be deg om ett av følgende:

1. **Skriv XIQ-oppskrift** for P0/P1/P2 med eksakte klikk-stier i XIQ GUI
2. **Skriv Palo Alto commit-blokk** for guest-DHCP utvidelse — trenger
   først output fra kommandoene i P3
3. **Skriv rollback-plan** før noen endring gjøres
4. **Bygg videre på scaffoldet** i `agents/wifi/` for å automatisere
   XIQ-audit (repo: `preben-byte/Anthropic-claude-code`, branch
   `claude/wifi-config-optimization-tzoxnf`)

**Ikke gi CLI-kommandoer for IQ Engine 10.8 uten å sjekke syntax først** —
feil kommando kan ta radioen ned. Alle endringer skal helst inn i XIQ
(overlever strømbrudd og re-provisioning).

**Bruker har både Palo Alto og Cisco.** Palo Alto er brannmur på .1. Cisco
er ikke identifisert enda — de kan være en av switcher, eller sitter et
annet sted i topologien.

---

## Del 8: Referansedata

### Radio-profiler i bruk
- `Marivold-AP460C-Outdoor-2G`
- `Marivold-AP460C-Outdoor-5G`

### QoS-policy
`Rate-Limit-1` brukes for Marivold-guest (VLAN 20). 1 Gbps user limit.

### CAPWAP / XIQ
- Primary: `se-cws-0.extremecloudiq.com`
- Backup: `se-cwm.extremecloudiq.com`
- VHM: `VHM-HCPDLLOM`
- Region: World, Country code 410 (Norway)

### Native VLAN på alle AP-eth0
VLAN 10 (Adm). Betyr AP-management går på Adm-VLAN.

### Sikkerhet
Alle SSID-er WPA2-PSK / AES CCMP. Ingen WPA3, ingen 802.1X, ingen PPSK.
Verdt oppgradering på sikt.
