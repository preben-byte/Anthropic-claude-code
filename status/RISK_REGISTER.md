# RISK_REGISTER

| # | Risiko | Sanns. | Konsekvens | Motvirkning |
|---|---|---|---|---|
| R1 | Stemmekandidat oppfattes som kjent person | M | Juridisk/etisk; må forkastes | Original beskrivelse uten navn; diskvalifiserende spørsmål i blindtesten; forkast ved gjenkjenning |
| R2 | ElevenLabs-API avviker fra antatt kontrakt | M | Fase 1-forsinkelse | Adapter er quarantined; verifiseres mot offisiell dokumentasjon før live-kall (A1) |
| R3 | Norsk uttale i engelske setninger blir dårlig | M | Kjernekrav i endret §7 ryker | Uttaleordbok + dedikert blandet testtekst + eget scoringskriterium i lyttetesten |
| R4 | Latensmål (p50 < 800 ms) nås ikke med valgt kjede | M | Dårlig samtaleopplevelse | Flash-modell for sanntid; streaming hele veien; måling før optimalisering |
| R5 | Hemmeligheter havner i git/logger | L | Alvorlig | .gitignore fra dag én; presence-only i CLI; manifest-test uten secrets; senere secret-scanning i CI |
| R6 | Kostnadsgalopp ved API-bruk | M | Økonomisk | Mock som standard; kostnadsgrenser og varsling (§20) før produksjonsautomatisering |
| R7 | Scope-kryp før stemmen er godkjent | H | Fase 1 forsinkes | Faseplanen håndheves: ingen agentbygging før stemmeprototypen står |
| R8 | Gjestedata/CCTV lekker til skymodeller | L | Personvernbrudd | `restricted`-sperre i ruting; CCTV aldri til cloud; integrasjoner starter deaktivert |
