# VISION — Project Jarvis

> «Jarvis» er internt arbeidsnavn. Assistentens navn og wake word er
> konfigurasjon (`config/assistant.yaml`) og kan endres når som helst uten
> kodeendring, uten å endre stemmen og uten å bygge systemet på nytt.
> Systemet fremstilles ikke som et offisielt Marvel-, Disney-, Iron Man-
> eller Paul Bettany-produkt.

## Hva vi bygger

Et modulært, lokalt forankret og produksjonsklart personlig AI-system for
Preben, driftet ved Marivold og tilgjengelig fra PC, telefon og fremtidige
stemmeenheter.

Systemet skal:

- Føre naturlige talesamtaler. Preben snakker norsk bokmål; systemet svarer
  alltid muntlig på naturlig britisk engelsk (se språkpolicy i PRD §2).
- Bruke én konsekvent, original og profesjonell stemme — aldri en klone av
  en virkelig person.
- Kunne avbrytes mens det snakker (barge-in).
- Svare raskt på enkle spørsmål og starte kompliserte bakgrunnsoppdrag
  asynkront med jobb-ID og muntlig kvittering.
- Bytte mellom flere AI-modeller via en utvidbar modellgateway, med
  personvern som hard sperre.
- Ha langtidshukommelse med dokumenterte kilder og menneskestyrt godkjenning
  av nye «fakta».
- Bruke verktøy og automasjoner bak strenge tillatelser og full
  revisjonslogg.
- Kunne utvides uten at kjernen bygges på nytt.

## Hva vi ikke bygger

- Ingen stemmekloning av Paul Bettany eller andre gjenkjennelige personer.
- Ingen språkmodell med direkte, ukontrollert tilgang til OS, nettverk,
  e-post, betalinger eller produksjonssystemer.
- Ingen «gjør hva som helst»-automasjon.

## Ledestjerner

1. Stemmen bygges først (Fase 1) — resten av systemet er verdiløst hvis
   samtaleopplevelsen ikke holder.
2. Personvern er en sperre, ikke et poengtall.
3. Alt eksternt starter read-only eller simulert.
4. Menneske-i-løkken for alt som har ekstern effekt.
5. Leverandørspesifikk kode holdes i adaptere; kjernen er leverandørnøytral.
