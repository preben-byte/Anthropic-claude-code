# VOICE_SPEC — stemmeidentitet og Voice Lab

## Ufravikelig stemmegrense

- Ingen kloning av Paul Bettany eller trening på lyd av ham.
- Ingen stemmeutdrag fra Zubairs videoer som treningsdata.
- Ingen omgåelse av leverandørens stemmeverifisering.
- Ingen stemme som med rimelighet kan forveksles med en bestemt skuespiller.
- Ingen markedsføring som «Paul Bettany» eller «den ekte JARVIS-stemmen».

Kandidater som oppfattes som en gjenkjennelig offentlig person forkastes.
Hvis Preben senere leverer en lovlig lisensiert, leverandørverifisert
`voice_id`, byttes den inn via `config/voices.yaml` uten arkitekturendring.

## Målidentitet

Moden mannlig stemme; kontrollert standard sørbritisk uttale; medium-lav
baryton; rolig, presis, autoritativ; intelligent uten å belære; varm nok til
tillit; svært lite overspill; tørr, diskret humor; moderne studiokvalitet;
lett teknologisk polering uten robotklang. Samme identitet i alle profiler.

Språkbruk i drift følger språkpolicyen (PRD §2): tale ut er alltid britisk
engelsk, med korrekt uttale av norske navn/steder/faguttrykk via
`config/pronunciation.yaml`. Stemmen må i tillegg beherske tydelig norsk
bokmål for de tilfellene Preben uttrykkelig ber om norsk svar.

## Voice Design

Basisbeskrivelse: se `BASE_VOICE_DESCRIPTION` i
`src/jarvis/voice_lab/candidates.py` (ingen skuespiller-, film- eller
figurnavn). Modeller undersøkes mot gjeldende ElevenLabs-dokumentasjon:
Voice Design `eleven_ttv_v3`; kvalitet `eleven_v3` / `eleven_multilingual_v2`;
sanntid `eleven_flash_v2_5`. Samme `voice_id` i alle ytelsesprofiler der
leverandøren støtter det.

Fire kontrollerte varianter: A litt varmere/diplomatisk, B kjøligere/
analytisk, C dypere/sonor (aldri «trailer voice»), D lysere/raskere for
lange tekniske svar. Minst 12 blindkodede kandidater: `A01`–`D03`.

## Blind evaluering

Runde 1 viser kun blindkoder og lyd (`blind_listing.json`) — aldri
leverandørbeskrivelse eller variantnavn. Preben scorer 1–5 på: identitet,
autoritet, varme, intelligensinntrykk, tydelighet, britisk uttale, norsk
uttale, teknisk uttale, langtidskomfort, korte kommandoer, lange
forklaringer, og «minner om kjent person» (diskvalifiserende).

Prosess: 12 kandidater → topp 4 → kontrollerte variasjoner → runde 2 med
minst 8 → topp 2 → 30+ ytringer → én hovedstemme + én lovlig reserve.
Hovedstemmen endres aldri automatisk etter godkjenning.

## Testmateriale

`src/jarvis/voice_lab/texts.py`: engelsk testtekst (§6.3), norsk testtekst
(§6.4), blandet tekst med norske stedsnavn i engelske setninger (kjernen i
den endrede språkpolicyen), og stressliste (IP, MAC, VLAN, datoer, telefon,
kronebeløp, produktnavn, Marivold, Paradisbukta, Beverdalen, Golanhøyden,
ExtremeCloud IQ, Hikvision, MikroTik, Home Assistant, PostgreSQL,
Claude Fable 5, GPT-5.6 Sol).

## TTS-innstillinger og profiler

Startområder (avgjøres av tester, ikke fasit): stability 0.65–0.82,
similarity 0.68–0.84, style 0.02–0.15, speed 0.94–1.02, speaker boost
A/B-testes. Intern lyd mono PCM ≥ 24 kHz; avspilling 48 kHz uten unødig
resampling. Tre profiler i `config/voices.yaml`: `realtime`, `technical`,
`warning`.

## Lydbehandling

Minst mulig DSP; kun forsiktig kjede (high-pass 65–75 Hz, mild demping
180–300 Hz ved behov, mild de-esser, ~2:1 kompresjon, limiter −1 dBTP,
−18 til −16 LUFS). Ingen romklang, vocoder, «radio»-effekt eller pitch
shifting. Bypass-sammenligning; DSP beholdes bare ved reell blindtestgevinst.

## Akseptansekrav

Ingen clipping/knepp; stabil identitet over 100+ setninger; norsk uttale
godkjent av Preben; korrekte engelske faguttrykk; entydige tall og
IP-adresser; p50 time-to-first-audio < 450 ms i sanntidsprofil (eller best
dokumenterte resultat); avbrytelse < 250 ms målt; blindscore ≥ 4,3/5;
ingen gjenkjenning av offentlig person; både sanntids- og kvalitetsprofil;
automatisk lovlig fallback. Deretter: Prebens eksplisitte godkjenning.

## Manifest

`config/voice_manifest.json` (skjema i `src/jarvis/voice_lab/manifest.py`)
med internt navn, leverandør, voice_id, modeller, dato, beskrivelse,
innstillinger, språk, testresultater, godkjennings- og lisensstatus,
sjekksummer, kjente svakheter, reserveprofil og neste regresjonstestdato.
Aldri API-nøkler eller hemmeligheter i manifestet.
