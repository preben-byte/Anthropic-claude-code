# OPERATIONS — Project Jarvis

## Installasjon (Fase 0-tilstand)

```bash
git clone <repo> && cd <repo>
pip install -e ".[dev]"      # eller: uv pip install -e ".[dev]"
jarvis doctor                # skal rapportere status: ok (mock mode uten nøkkel)
pytest                       # hele testsuiten skal passere
```

## Legge inn ElevenLabs-nøkkel (den ene trygge handlingen)

```bash
cp .env.example .env.local
# Rediger .env.local og sett ELEVENLABS_API_KEY=<nøkkelen din>
```

`.env.local` er gitignorert. Lim aldri nøkkelen inn i chat, commit eller
konfigfiler. `jarvis doctor` bekrefter med `elevenlabs_api_key: present`
uten å vise verdien.

## Endre assistentens navn eller wake word

Rediger `config/assistant.yaml` (`assistant_name`, `wake_word`,
`wake_word_aliases`) — eller sett `JARVIS_ASSISTANT_NAME` /
`JARVIS_WAKE_WORD` per enhet. Ingen ny bygging; stemmen berøres ikke.

## CLI

Implementert nå:

```
jarvis doctor                 # read-only helsesjekk (--json støttes)
jarvis config                 # effektiv konfigurasjon
jarvis voice test             # syntetiser faste testtekster (mock uten nøkkel)
jarvis voice candidates       # generer blindkodede kandidater A01–D03
jarvis models list            # modellroller fra config/models.yaml
```

Kommer per fase (masteroppdrag §18): `start`, `stop`, `status`,
`voice benchmark`, `models test`, `models route --explain`, `tools list`,
`tools test --read-only`, `jobs list`, `jobs cancel`, `memory search`,
`memory export`, `audit show`, `backup`, `restore --dry-run`,
`emergency-stop`. Alle med konsistent hjelp og valgfri JSON-output.

## Generert lyd

Voice Lab skriver til `var/` (gitignorert). Mock-modus lager gyldige
WAV-filer (24 kHz mono PCM) med sidecar-transkripsjoner, slik at hele
pipelinen kan kjøres og måles uten nøkkel og uten nettverk.

## Backup og gjenoppretting

Fase 8. Krav: automatisk backup, dokumentert restore-test,
`jarvis restore --dry-run`, og at installasjon kan gjentas fra tom maskin.
