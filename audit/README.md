# Audit-modul

Struktur for å versjonere eksporterte configer og diff-e dem mot en gullstandard.

## Layout

```
audit/
├── baselines/          # Gullstandard-configer (committed)
│   ├── firewall.baseline
│   ├── switch.baseline
│   └── xiq-network-policy.baseline.json
├── configs/            # Faktiske dumper (committed etter sanitizing)
│   ├── firewall/
│   ├── switch/
│   └── xiq/
└── diff.py             # baseline vs current
```

## Flyt

1. **Eksporter** current config fra utstyret:
   - FortiGate: `execute backup config tftp <fil> <server>` eller GUI-eksport
   - Palo Alto: `show config running` → lagre til fil
   - Cisco/Extreme switch: `show running-config`
   - XIQ: bruk `agents/wifi` — `xiq_get_network_policy` skriver JSON

2. **Vask secrets FØR commit**:
   - `ENC` / hash-verdier for passord
   - PSK / VPN pre-shared keys
   - SNMP community strings
   - API-tokens

   Bruk `git diff --cached` og lete etter `password`, `secret`, `key`, `psk`, `community`
   før du committer. Aldri push urensede dumper.

3. **Diff** mot baseline:
   ```bash
   python -m audit.diff baselines/firewall.baseline configs/firewall/current.conf
   ```

4. **Kjør WiFi-agenten** for XIQ-siden — den henter selv fra API og
   sammenligner mot baseline hvis den finnes:
   ```bash
   python -m agents.main wifi "Diff current network policies mot audit/baselines/"
   ```

## Hva som IKKE hører hjemme her

Live secrets, PCAP-fangster, klientlister med MAC-adresser. Bruk et privat repo eller en
lokal notes-vault for slikt.
