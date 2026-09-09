#!/usr/bin/env bash
# ============================================================================
# roaming-logg.sh — nettsjekk: roaming-logg for Wi-Fi (gå rundt på området)
#   Marivold Camping / Adm-nett — Extreme Networks AP-er (XIQ)
#
# Formål : Logger Wi-Fi-tilkoblingen (SSID, BSSID, kanal, bånd, RSSI, støy,
#          tx-rate) og gateway-ping hvert sekund mens du går rundt på området.
#          Oppdager roam-hendelser (bytte av BSSID/AP), måler avbrudd (gap)
#          rundt hver roam, finner «sticky client»-episoder og skriver
#          CSV-logg + Markdown-oppsummering som kan limes inn i chatten.
# Kjøring: bash roaming-logg.sh
#          bash roaming-logg.sh --varighet 900 --intervall 1 --rapportmappe ~/nettsjekk
#          bash roaming-logg.sh --gateway 10.0.0.1 --grensesnitt wlan0 --ingen-farger
#          Ctrl-C avslutter når som helst og skriver oppsummeringen.
# Krav   : bash 3.2+ (macOS), bash 4/5 (Linux, Android Termux).
#          Linux : iw (anbefalt) eller nmcli/iwconfig, ping, ip.
#          macOS : wdutil (via sudo -n, valgfritt), system_profiler, ipconfig, ping.
#          Termux: termux-api (termux-wifi-connectioninfo) og Termux:API-appen,
#                  iputils (ping).
#          Manglende verktøy gir [SKIP] med installasjonskommando — skriptet
#          stopper aldri av den grunn.
# Versjon 1.0 — 2026-09-09
# Endrer ingenting — kun lesing og målinger.
# ----------------------------------------------------------------------------
# Innhold (søk etter "### N." for å hoppe dit):
#   ### 1. Standardverdier og globale variabler
#   ### 2. Hjelpefunksjoner: farger, statuslinjer, tall, timeout, klokke
#   ### 3. Parameterhåndtering og hjelpetekst
#   ### 4. Plattform, verktøy, grensesnitt og gateway
#   ### 5. Wi-Fi-kilder (Linux, macOS, Termux) og normalisering
#   ### 6. Ping
#   ### 7. Roam-, gap- og sticky-logikk
#   ### 8. Oppsummering (konsoll + Markdown) og trap
#   ### 9. Hovedløkke
# ============================================================================

set -u
# Ikke «set -e»: en feilet måling skal aldri stoppe loggingen.
export LC_NUMERIC=C

### 1. Standardverdier og globale variabler
VERSJON="1.0"
SEKSJON="11 Roaming"

INTERVALL=1            # sekunder mellom prøver
VARIGHET=600           # sekunder totalt (0 = til Ctrl-C)
GATEWAY=""
GATEWAY_KILDE=""
GRENSESNITT=""
GRENSESNITT_KILDE=""
RAPPORTMAPPE="."
FARGER=1

OS="linux"             # linux | macos | termux
OS_TEKST=""
VERT="ukjent"
STEMPEL=""
CSV_FIL=""
MD_FIL=""
START_TID=""
START_MS=0
INTERVALL_MS=1000
INTERVALL_EFF_MS=1000
WIFI_MS_SIST=0
INTERVALL_MELDT=0

PING_BIN=""
PING_N=""
PING_INSTALL=""
TIMEOUT_BIN=""
PERL_BIN=""
PY_BIN=""
JQ_BIN=""
MS_KILDE="sek"

WIFI_KILDE="ingen"
WIFI_KILDE_TEKST="ingen Wi-Fi-kilde funnet"
WIFI_INSTALL=""
HEURISTIKK=0           # 1 = BSSID utilgjengelig → kanal-/RSSI-heuristikk
AIRPORT_BIN="/System/Library/PrivateFrameworks/Apple80211.framework/Versions/Current/Resources/airport"
TERMUX_POS_MELDT=0
NMCLI_MELDT=0
HEURISTIKK_MELDT=0

# Gjeldende prøve
W_SSID=ukjent; W_BSSID=ukjent; W_KANAL=ukjent; W_BAAND=ukjent
W_RSSI=ukjent; W_STOY=ukjent; W_SNR=ukjent; W_RATE=ukjent; W_PHY=ukjent
W_MERKNAD=""
# Forrige prøve og sist kjente verdier
HAR_FORRIGE=0
F_RSSI=ukjent
SIST_BSSID=ukjent; SIST_KANAL=ukjent; SIST_BAAND=ukjent; SIST_RSSI=ukjent

# Tellere og lister (nylinje-/mellomromseparerte strenger — bash 3.2-vennlig)
ANTALL_PROVER=0
ANTALL_ROAM=0
ANTALL_MULIG_ROAM=0
ANTALL_STICKY=0
FEIL_STREAK=0
ROAM_GAPS=""
ROAM_TABELL=""
ROAM_KONSOLL=""
STICKY_TABELL=""
STICKY_START_MS=0
STICKY_START_TID=""
STICKY_START_RSSI=""
STICKY_MIN_RSSI=""
STICKY_MELDT=0

# Ventende roam (gap måles til første vellykkede gateway-ping)
ROAM_VENTER=0
ROAM_NR=0
ROAM_TID=""; ROAM_MS=0
ROAM_FRA_BSSID=""; ROAM_TIL_BSSID=""
ROAM_FRA_KB=""; ROAM_TIL_KB=""
ROAM_FRA_RSSI=""; ROAM_TIL_RSSI=""
ROAM_TYPE=""; ROAM_TYPE_AKTIV=""
ROAM_FEIL_FOER=0; ROAM_FEIL_ETTER=0

STATUS_LINJER=""
T_PASS=0; T_WARN=0; T_FAIL=0; T_INFO=0; T_SKIP=0
AVSLUTTET=0

C_ROD=""; C_GRONN=""; C_GUL=""; C_CYAN=""; C_MAG=""; C_DIM=""; C_NULL=""

### 2. Hjelpefunksjoner: farger, statuslinjer, tall, timeout, klokke
sett_farger() {
  if [ "$FARGER" -eq 1 ] && [ -t 1 ] && [ "${TERM:-dumb}" != "dumb" ]; then
    C_ROD=$(printf '\033[31m'); C_GRONN=$(printf '\033[32m'); C_GUL=$(printf '\033[33m')
    C_CYAN=$(printf '\033[36m'); C_MAG=$(printf '\033[35m'); C_DIM=$(printf '\033[2m')
    C_NULL=$(printf '\033[0m')
  else
    FARGER=0
  fi
}

farge_status() {
  case "$1" in
    PASS) printf '%s' "$C_GRONN" ;;
    WARN) printf '%s' "$C_GUL" ;;
    FAIL) printf '%s' "$C_ROD" ;;
    INFO) printf '%s' "$C_CYAN" ;;
    *)    printf '%s' "$C_DIM" ;;
  esac
}

# status STATUS SJEKK VERDI [TERSKEL] — skriver konsollinje og lagrer til rapporten
status() {
  local st="$1" sjekk="$2" verdi="$3" terskel="${4:-}" linje
  linje="[$st] $SEKSJON: $sjekk — $verdi"
  [ -n "$terskel" ] && linje="$linje (terskel $terskel)"
  printf '%s%s%s\n' "$(farge_status "$st")" "$linje" "$C_NULL"
  STATUS_LINJER="${STATUS_LINJER}${linje}
"
  case "$st" in
    PASS) T_PASS=$((T_PASS + 1)) ;;
    WARN) T_WARN=$((T_WARN + 1)) ;;
    FAIL) T_FAIL=$((T_FAIL + 1)) ;;
    INFO) T_INFO=$((T_INFO + 1)) ;;
    SKIP) T_SKIP=$((T_SKIP + 1)) ;;
  esac
}

melding() { printf '%s%s%s\n' "$C_DIM" "$1" "$C_NULL"; }
feil()    { printf '%sFEIL: %s%s\n' "$C_ROD" "$1" "$C_NULL" >&2; }

er_heltall() {
  case "${1:-}" in
    '' | - ) return 1 ;;
    -*) case "${1#-}" in *[!0-9]* | '') return 1 ;; esac ;;
    *)  case "$1" in *[!0-9]*) return 1 ;; esac ;;
  esac
  return 0
}

er_tall() {  # heltall eller desimaltall, evt. negativt
  case "${1:-}" in
    '' | - | . | -. ) return 1 ;;
    *[!0-9.-]*) return 1 ;;
  esac
  case "${1#-}" in *-*) return 1 ;; *.*.*) return 1 ;; esac
  return 0
}

er_ipv4() {
  local ip="${1:-}" a b c d rest
  case "$ip" in '' | *[!0-9.]*) return 1 ;; esac
  IFS=. read -r a b c d rest <<EOF
$ip
EOF
  [ -n "$a" ] && [ -n "$b" ] && [ -n "$c" ] && [ -n "$d" ] && [ -z "$rest" ] || return 1
  [ "$a" -le 255 ] && [ "$b" -le 255 ] && [ "$c" -le 255 ] && [ "$d" -le 255 ] || return 1
  return 0
}

er_bssid() {
  case "${1:-}" in
    [0-9a-f][0-9a-f]:[0-9a-f][0-9a-f]:[0-9a-f][0-9a-f]:[0-9a-f][0-9a-f]:[0-9a-f][0-9a-f]:[0-9a-f][0-9a-f]) ;;
    *) return 1 ;;
  esac
  case "$1" in 00:00:00:00:00:00 | 02:00:00:00:00:00 | ff:ff:ff:ff:ff:ff) return 1 ;; esac
  return 0
}

# Normaliserer BSSID: små bokstaver, nullutfylte oktetter (macOS ipconfig gir "0:11:22:...")
normaliser_bssid() {
  printf '%s\n' "${1:-}" | tr 'A-F' 'a-f' | awk -F: '
    NF == 6 { for (i = 1; i <= 6; i++) if (length($i) == 1) $i = "0" $i
              print $1 ":" $2 ":" $3 ":" $4 ":" $5 ":" $6; next }
    { print }'
}

# Kjør en kommando med tidsgrense (sekunder). Aldri heng.
kjor_timeout() {
  local sek="$1" pid vakt rc
  shift
  if [ -n "$TIMEOUT_BIN" ]; then
    "$TIMEOUT_BIN" "$sek" "$@"
    return $?
  fi
  if [ -n "$PERL_BIN" ]; then
    "$PERL_BIN" -e 'alarm shift; exec @ARGV' "$sek" "$@"
    return $?
  fi
  "$@" &
  pid=$!
  ( sleep "$sek"; kill "$pid" 2>/dev/null ) 2>/dev/null &
  vakt=$!
  wait "$pid" 2>/dev/null
  rc=$?
  kill "$vakt" 2>/dev/null
  wait "$vakt" 2>/dev/null
  return "$rc"
}

# Millisekundklokke (best mulig kilde per plattform)
finn_ms_kilde() {
  local t
  t=$(date +%s%3N 2>/dev/null || true)
  case "$t" in
    *[!0-9]* | '') ;;
    *) if [ "${#t}" -ge 13 ]; then MS_KILDE="date"; return; fi ;;
  esac
  if [ -n "$PERL_BIN" ] && "$PERL_BIN" -MTime::HiRes -e 1 2>/dev/null; then
    MS_KILDE="perl"; return
  fi
  if [ -n "$PY_BIN" ]; then MS_KILDE="python"; return; fi
  MS_KILDE="sek"
}

naa_ms() {
  case "$MS_KILDE" in
    date)   date +%s%3N ;;
    perl)   "$PERL_BIN" -MTime::HiRes -e 'printf "%d\n", Time::HiRes::time() * 1000' ;;
    python) "$PY_BIN" -c 'import time; print(int(time.time() * 1000))' ;;
    *)      echo $(( $(date +%s) * 1000 )) ;;
  esac
}

naa_iso() { date +%Y-%m-%dT%H:%M:%S%z; }
naa_kl()  { date +%H:%M:%S; }

sov_ms() {
  local ms="${1:-0}"
  er_heltall "$ms" || return 0
  [ "$ms" -gt 0 ] || return 0
  sleep "$(awk -v m="$ms" 'BEGIN { printf "%.3f", m / 1000 }')"
}

# Sammenligning av desimaltall via awk: flt_lt A B → sann hvis A < B
flt_lt() { awk -v a="$1" -v b="$2" 'BEGIN { exit !(a + 0 < b + 0) }'; }
flt_ge() { awk -v a="$1" -v b="$2" 'BEGIN { exit !(a + 0 >= b + 0) }'; }

# CSV-felt: dobbeltfnutter rundt, interne fnutter dobles
csv_felt() {
  local s="${1:-}"
  s=${s//\"/\"\"}
  printf '"%s"' "$s"
}

freq_til_kanal() {
  local f="${1:-}"
  f=${f%%.*}
  er_heltall "$f" || { echo ukjent; return; }
  if   [ "$f" -eq 2484 ]; then echo 14
  elif [ "$f" -ge 2412 ] && [ "$f" -le 2472 ]; then echo $(( (f - 2407) / 5 ))
  elif [ "$f" -eq 5935 ]; then echo 2
  elif [ "$f" -ge 5955 ] && [ "$f" -le 7115 ]; then echo $(( (f - 5950) / 5 ))
  elif [ "$f" -ge 5000 ] && [ "$f" -le 5925 ]; then echo $(( (f - 5000) / 5 ))
  elif [ "$f" -ge 4900 ] && [ "$f" -lt 5000 ]; then echo $(( (f - 4000) / 5 ))
  else echo ukjent; fi
}

freq_til_baand() {
  local f="${1:-}"
  f=${f%%.*}
  er_heltall "$f" || { echo ukjent; return; }
  if   [ "$f" -ge 2400 ] && [ "$f" -lt 2500 ]; then echo "2.4 GHz"
  elif [ "$f" -ge 5925 ] && [ "$f" -le 7125 ]; then echo "6 GHz"
  elif [ "$f" -ge 4900 ] && [ "$f" -lt 5925 ]; then echo "5 GHz"
  else echo ukjent; fi
}

# Når bare kanalnummer er kjent (6 GHz-kanaler overlapper 5 GHz-numre → antar 5 GHz)
kanal_til_baand() {
  local k="${1:-}"
  er_heltall "$k" || { echo ukjent; return; }
  if [ "$k" -ge 1 ] && [ "$k" -le 14 ]; then echo "2.4 GHz"; else echo "5 GHz"; fi
}

### 3. Parameterhåndtering og hjelpetekst
vis_hjelp() {
  cat <<'HJELP'
roaming-logg.sh — nettsjekk: roaming-logg for Wi-Fi (versjon 1.0)

Bruk: bash roaming-logg.sh [valg]

Logger Wi-Fi-tilkoblingen (SSID, BSSID, kanal, bånd, RSSI, støy, tx-rate) og
gateway-ping hvert sekund mens du går rundt på området. Oppdager roam-hendelser,
måler gap (avbrudd) rundt hver roam, finner «sticky client»-episoder og skriver
  roaming-logg-<vert>-<YYYYMMDD-HHMMSS>.csv   (alle prøver)
  roaming-logg-<vert>-<YYYYMMDD-HHMMSS>.md    (oppsummering — lim inn i chatten)

Valg:
  --intervall N        Sekunder mellom hver prøve (heltall 1–60, standard 1)
  --varighet N         Total varighet i sekunder (standard 600, 0 = til Ctrl-C)
  --gateway IP         Gateway som pinges (standard: finnes automatisk)
  --grensesnitt IF     Wi-Fi-grensesnitt, f.eks. wlan0 / en0 (standard: automatisk)
  --rapportmappe DIR   Mappe for CSV og Markdown (standard: gjeldende mappe)
  --ingen-farger       Ingen ANSI-farger i utskriften
  --hjelp              Denne hjelpen

Ctrl-C avslutter når som helst; oppsummeringen skrives uansett.
Skriptet endrer ingenting — kun lesing og målinger. Krever ikke sudo/root.

Terskler i oppsummeringen:
  Roam-gap        PASS ≤100 ms, WARN ≤500 ms, FAIL >500 ms
  Pakketap (gw)   PASS <1 %,   WARN <3 %,    FAIL ≥3 %
  Sticky client   RSSI < -75 dBm i >10 s uten roam → WARN
  2,4 GHz         andel prøver på 2,4 GHz > 0 % → WARN (Adm-nett bør bruke 5/6 GHz)
HJELP
}

krev_verdi() {
  if [ -z "${2:-}" ]; then
    feil "Parameteren $1 trenger en verdi."
    vis_hjelp
    exit 2
  fi
}

les_parametre() {
  while [ $# -gt 0 ]; do
    case "$1" in
      --intervall)      krev_verdi "$1" "${2:-}"; INTERVALL="$2"; shift 2 ;;
      --intervall=*)    INTERVALL="${1#*=}"; shift ;;
      --varighet)       krev_verdi "$1" "${2:-}"; VARIGHET="$2"; shift 2 ;;
      --varighet=*)     VARIGHET="${1#*=}"; shift ;;
      --gateway)        krev_verdi "$1" "${2:-}"; GATEWAY="$2"; shift 2 ;;
      --gateway=*)      GATEWAY="${1#*=}"; shift ;;
      --grensesnitt)    krev_verdi "$1" "${2:-}"; GRENSESNITT="$2"; shift 2 ;;
      --grensesnitt=*)  GRENSESNITT="${1#*=}"; shift ;;
      --rapportmappe)   krev_verdi "$1" "${2:-}"; RAPPORTMAPPE="$2"; shift 2 ;;
      --rapportmappe=*) RAPPORTMAPPE="${1#*=}"; shift ;;
      --ingen-farger)   FARGER=0; shift ;;
      --hjelp | -h | --help) vis_hjelp; exit 0 ;;
      *) feil "Ukjent parameter: $1"; echo; vis_hjelp; exit 2 ;;
    esac
  done

  if ! er_heltall "$INTERVALL" || [ "$INTERVALL" -lt 1 ] || [ "$INTERVALL" -gt 60 ]; then
    feil "--intervall må være et heltall mellom 1 og 60 (fikk «$INTERVALL»)."; exit 2
  fi
  if ! er_heltall "$VARIGHET" || [ "$VARIGHET" -lt 0 ] || [ "$VARIGHET" -gt 86400 ]; then
    feil "--varighet må være et heltall mellom 0 og 86400 sekunder (fikk «$VARIGHET»)."; exit 2
  fi
  if [ -n "$GATEWAY" ] && ! er_ipv4 "$GATEWAY"; then
    feil "--gateway må være en IPv4-adresse (fikk «$GATEWAY»)."; exit 2
  fi
  if [ -n "$GRENSESNITT" ]; then
    case "$GRENSESNITT" in
      *[!A-Za-z0-9._-]*) feil "--grensesnitt inneholder ugyldige tegn (fikk «$GRENSESNITT»)."; exit 2 ;;
    esac
  fi
  if [ ! -d "$RAPPORTMAPPE" ]; then
    mkdir -p "$RAPPORTMAPPE" 2>/dev/null || { feil "Kan ikke opprette rapportmappen «$RAPPORTMAPPE»."; exit 2; }
  fi
  if [ ! -w "$RAPPORTMAPPE" ]; then
    feil "Rapportmappen «$RAPPORTMAPPE» er ikke skrivbar."; exit 2
  fi
  INTERVALL_MS=$((INTERVALL * 1000))
  INTERVALL_EFF_MS=$INTERVALL_MS
}

### 4. Plattform, verktøy, grensesnitt og gateway
finn_os() {
  local k
  k=$(uname -s 2>/dev/null || echo ukjent)
  if [ -n "${TERMUX_VERSION:-}" ] || [ -d /data/data/com.termux/files/usr ]; then
    OS="termux"; OS_TEKST="Android Termux ($(uname -r 2>/dev/null || echo ukjent))"
  elif [ "$k" = "Darwin" ]; then
    OS="macos"; OS_TEKST="macOS $(sw_vers -productVersion 2>/dev/null || echo ukjent)"
  else
    OS="linux"
    if [ -r /etc/os-release ]; then
      OS_TEKST=$(sed -n 's/^PRETTY_NAME="\{0,1\}\([^"]*\)"\{0,1\}$/\1/p' /etc/os-release | head -n 1)
    fi
    [ -n "$OS_TEKST" ] || OS_TEKST="Linux $(uname -r 2>/dev/null || echo ukjent)"
  fi
}

finn_verktoy() {
  local ut
  command -v timeout  >/dev/null 2>&1 && TIMEOUT_BIN=timeout
  [ -z "$TIMEOUT_BIN" ] && command -v gtimeout >/dev/null 2>&1 && TIMEOUT_BIN=gtimeout
  command -v perl     >/dev/null 2>&1 && PERL_BIN=perl
  command -v python3  >/dev/null 2>&1 && PY_BIN=python3
  command -v jq       >/dev/null 2>&1 && JQ_BIN=jq
  finn_ms_kilde

  if command -v ping >/dev/null 2>&1; then
    PING_BIN=ping
    # Sjekk om ping tolererer -n (ikke toybox-ping på Android). Loopback = ingen nettverkstrafikk.
    case "$OS" in
      macos) ut=$(kjor_timeout 3 ping -n -c 1 -W 500 -t 1 127.0.0.1 2>&1) ;;
      *)     ut=$(kjor_timeout 3 ping -n -c 1 -W 1 127.0.0.1 2>&1) ;;
    esac
    case "$ut" in
      *time[=\<]*) PING_N="-n" ;;
      *) PING_N="" ;;
    esac
  else
    case "$OS" in
      termux) PING_INSTALL="pkg install iputils" ;;
      macos)  PING_INSTALL="ping er innebygd i macOS — sjekk PATH (/sbin/ping)" ;;
      *)      PING_INSTALL="sudo apt install iputils-ping   (Fedora: sudo dnf install iputils)" ;;
    esac
  fi
}

# Grensesnitt: --grensesnitt, ellers standardrute, ellers første trådløse grensesnitt
finn_grensesnitt() {
  local i
  if [ -n "$GRENSESNITT" ]; then GRENSESNITT_KILDE="parameter"; return; fi
  case "$OS" in
    macos)
      GRENSESNITT=$(kjor_timeout 5 route -n get default 2>/dev/null | awk '/interface:/ { print $2; exit }')
      GRENSESNITT_KILDE="route -n get default"
      if command -v networksetup >/dev/null 2>&1; then
        i=$(kjor_timeout 5 networksetup -listallhardwareports 2>/dev/null \
            | awk '/^Hardware Port: Wi-Fi/ { f = 1; next } f && /^Device:/ { print $2; exit }')
        if [ -n "$i" ] && [ "$i" != "$GRENSESNITT" ]; then
          if [ -n "$GRENSESNITT" ]; then
            melding "[INFO] $SEKSJON: standardruten går via $GRENSESNITT, men Wi-Fi-porten er $i — bruker $i for Wi-Fi-data"
          fi
          GRENSESNITT="$i"; GRENSESNITT_KILDE="networksetup -listallhardwareports"
        fi
      fi
      ;;
    *)
      if command -v ip >/dev/null 2>&1; then
        GRENSESNITT=$(kjor_timeout 5 ip -4 route show default 2>/dev/null \
                      | awk '{ for (i = 1; i <= NF; i++) if ($i == "dev") { print $(i + 1); exit } }')
        GRENSESNITT_KILDE="ip route"
        if [ -z "$GRENSESNITT" ] && [ "$OS" = "termux" ]; then
          GRENSESNITT=$(kjor_timeout 5 ip -4 route show table all 2>/dev/null \
                        | awk '/^default/ { for (i = 1; i <= NF; i++) if ($i == "dev") { print $(i + 1); exit } }')
          GRENSESNITT_KILDE="ip route show table all"
        fi
      fi
      if [ -z "$GRENSESNITT" ] && [ -r /proc/net/route ]; then
        GRENSESNITT=$(awk 'NR > 1 && $2 == "00000000" { print $1; exit }' /proc/net/route 2>/dev/null)
        GRENSESNITT_KILDE="/proc/net/route"
      fi
      # Foretrekk et trådløst grensesnitt hvis standardruten går via kabel
      if [ -d /sys/class/net ]; then
        if [ -z "$GRENSESNITT" ] || [ ! -d "/sys/class/net/$GRENSESNITT/wireless" ]; then
          for i in /sys/class/net/*/wireless; do
            [ -d "$i" ] || continue
            i=${i%/wireless}; i=${i##*/}
            if [ -n "$GRENSESNITT" ] && [ "$GRENSESNITT" != "$i" ]; then
              melding "[INFO] $SEKSJON: standardruten går via $GRENSESNITT, men trådløst grensesnitt er $i — bruker $i for Wi-Fi-data"
            fi
            GRENSESNITT="$i"; GRENSESNITT_KILDE="/sys/class/net/*/wireless"
            break
          done
        fi
      fi
      if [ -z "$GRENSESNITT" ] && [ "$OS" = "termux" ]; then
        GRENSESNITT="wlan0"; GRENSESNITT_KILDE="antatt (Android-standard)"
      fi
      ;;
  esac
  [ -n "$GRENSESNITT" ] || { GRENSESNITT="ukjent"; GRENSESNITT_KILDE="ikke funnet — bruk --grensesnitt"; }
}

hex_til_ip() {  # /proc/net/route lagrer gateway som little-endian hex
  local h="${1:-}"
  [ "${#h}" -eq 8 ] || { echo ""; return; }
  printf '%d.%d.%d.%d\n' "0x${h:6:2}" "0x${h:4:2}" "0x${h:2:2}" "0x${h:0:2}" 2>/dev/null
}

finn_gateway() {
  local g="" ip="" a b c d rest
  if [ -n "$GATEWAY" ]; then GATEWAY_KILDE="parameter"; return; fi
  case "$OS" in
    macos)
      g=$(kjor_timeout 5 route -n get default 2>/dev/null | awk '/gateway:/ { print $2; exit }')
      GATEWAY_KILDE="route -n get default"
      ;;
    *)
      if command -v ip >/dev/null 2>&1; then
        g=$(kjor_timeout 5 ip -4 route show default 2>/dev/null \
            | awk '{ for (i = 1; i <= NF; i++) if ($i == "via") { print $(i + 1); exit } }')
        GATEWAY_KILDE="ip route"
        if [ -z "$g" ] && [ "$OS" = "termux" ]; then
          g=$(kjor_timeout 5 ip -4 route show table all 2>/dev/null \
              | awk '/^default/ { for (i = 1; i <= NF; i++) if ($i == "via") { print $(i + 1); exit } }')
          GATEWAY_KILDE="ip route show table all"
        fi
      fi
      if [ -z "$g" ] && [ -r /proc/net/route ]; then
        g=$(hex_til_ip "$(awk 'NR > 1 && $2 == "00000000" { print $3; exit }' /proc/net/route 2>/dev/null)")
        GATEWAY_KILDE="/proc/net/route"
      fi
      if [ -z "$g" ] && [ "$OS" = "termux" ] && command -v getprop >/dev/null 2>&1; then
        g=$(kjor_timeout 5 getprop "dhcp.$GRENSESNITT.gateway" 2>/dev/null)
        GATEWAY_KILDE="getprop dhcp.$GRENSESNITT.gateway"
      fi
      if [ -z "$g" ] && [ "$OS" = "termux" ] && command -v termux-wifi-connectioninfo >/dev/null 2>&1; then
        # Siste utvei på Android: anta .1 i klientens /24 — merkes tydelig som antatt.
        ip=$(kjor_timeout 8 termux-wifi-connectioninfo 2>/dev/null | sed -n 's/.*"ip": *"\([0-9.]*\)".*/\1/p' | head -n 1)
        if er_ipv4 "$ip"; then
          IFS=. read -r a b c d rest <<EOF
$ip
EOF
          g="$a.$b.$c.1"
          GATEWAY_KILDE="ANTATT ($a.$b.$c.1 fra klient-IP $ip) — overstyr med --gateway"
        fi
      fi
      ;;
  esac
  if er_ipv4 "$g"; then
    GATEWAY="$g"
  else
    GATEWAY=""
    GATEWAY_KILDE="ikke funnet — bruk --gateway IP"
  fi
}

### 5. Wi-Fi-kilder (Linux, macOS, Termux) og normalisering
# Alle kildene skriver én linje: ssid|bssid|kanal|freq_mhz|rssi|stoy|rate|phy|baand|merknad

wifi_iw() {
  kjor_timeout 5 iw dev "$GRENSESNITT" link 2>/dev/null | awk '
    /^Connected to/          { bssid = $3 }
    /^[ \t]*SSID:/           { s = $0; sub(/^[ \t]*SSID:[ \t]*/, "", s); ssid = s }
    /^[ \t]*freq:/           { freq = $2; sub(/\..*/, "", freq) }
    /^[ \t]*signal:/         { rssi = $2 }
    /^[ \t]*tx bitrate:/     { rate = $3 }
    END { printf "%s|%s|%s|%s|%s|%s|%s|%s|%s|%s\n", ssid, bssid, "", freq, rssi, "", rate, "", "", "" }'
}

wifi_iw_stoy() {  # støy for kanalen i bruk (iw survey dump)
  kjor_timeout 5 iw dev "$GRENSESNITT" survey dump 2>/dev/null | awk '
    /in use/ { f = 1 } f && /noise:/ { print $2; exit }'
}

wifi_nmcli() {
  # -t escaper kolon i verdier som «\:» — byttes midlertidig ut før splitting
  kjor_timeout 8 nmcli -t -f ACTIVE,BSSID,SSID,CHAN,FREQ,SIGNAL dev wifi 2>/dev/null | awk '
    /^yes:/ {
      l = $0; gsub(/\\:/, "@@", l); n = split(l, f, ":")
      bssid = f[2]; gsub(/@@/, ":", bssid)
      ssid  = f[3]; gsub(/@@/, ":", ssid)
      chan = f[4]; freq = f[5]; sub(/ *MHz.*/, "", freq); sig = f[6]
      rssi = ""; if (sig ~ /^[0-9]+$/) rssi = int(sig / 2 - 100)
      printf "%s|%s|%s|%s|%s|%s|%s|%s|%s|%s\n", ssid, bssid, chan, freq, rssi, "", "", "", "", "RSSI≈" sig "%/2-100 (nmcli gir bare prosent)"
      exit
    }'
}

wifi_iwconfig() {
  kjor_timeout 5 iwconfig "$GRENSESNITT" 2>/dev/null | awk '
    { l = $0
      if (match(l, /ESSID:"[^"]*"/))        { s = substr(l, RSTART + 7, RLENGTH - 8); ssid = s }
      if (match(l, /Access Point: [0-9A-Fa-f:]+/)) { bssid = substr(l, RSTART + 14, RLENGTH - 14) }
      if (match(l, /Frequency:[0-9.]+ GHz/))  { f = substr(l, RSTART + 10, RLENGTH - 14); freq = int(f * 1000 + 0.5) }
      if (match(l, /Bit Rate[=:][0-9.]+/))    { rate = substr(l, RSTART + 9, RLENGTH - 9) }
      if (match(l, /Signal level[=:]-?[0-9]+ dBm/)) { r = substr(l, RSTART + 13, RLENGTH - 17); rssi = r }
      if (match(l, /Noise level[=:]-?[0-9]+ dBm/))  { n = substr(l, RSTART + 12, RLENGTH - 16); stoy = n }
    }
    END { printf "%s|%s|%s|%s|%s|%s|%s|%s|%s|%s\n", ssid, bssid, "", freq, rssi, stoy, rate, "", "", "" }'
}

wifi_procwireless() {  # bare RSSI/støy — SSID/BSSID ukjent → heuristikk
  awk -v i="$GRENSESNITT:" '
    $1 == i { lvl = $4; sub(/\.$/, "", lvl); n = $5; sub(/\.$/, "", n)
              if (n == "-256") n = ""
              printf "%s|%s|%s|%s|%s|%s|%s|%s|%s|%s\n", "", "", "", "", lvl, n, "", "", "", "RSSI fra /proc/net/wireless"
              exit }' /proc/net/wireless 2>/dev/null
}

wifi_wdutil() {
  kjor_timeout 8 sudo -n wdutil info 2>/dev/null | awk '
    /^WIFI/ { f = 1; next }
    /^(BLUETOOTH|AWDL|NETWORK|POWER)/ { if (f) exit }
    f {
      l = $0; sub(/^[ \t]+/, "", l); p = index(l, " : "); if (p == 0) next
      k = substr(l, 1, p - 1); sub(/[ \t]+$/, "", k); v = substr(l, p + 3)
      if (k == "SSID"     && ssid == "")  ssid = v
      if (k == "BSSID"    && bssid == "") bssid = v
      if (k == "RSSI"     && rssi == "")  { rssi = v; sub(/ .*/, "", rssi) }
      if (k == "Noise"    && stoy == "")  { stoy = v; sub(/ .*/, "", stoy) }
      if (k == "Tx Rate"  && rate == "")  { rate = v; sub(/ .*/, "", rate) }
      if (k == "PHY Mode" && phy == "")   phy = v
      if (k == "Channel"  && kanal == "") {
        c = v
        if (c ~ /^2g/) baand = "2.4 GHz"; else if (c ~ /^5g/) baand = "5 GHz"; else if (c ~ /^6g/) baand = "6 GHz"
        sub(/^[0-9]g/, "", c); sub(/\/.*/, "", c); kanal = c
      }
    }
    END { printf "%s|%s|%s|%s|%s|%s|%s|%s|%s|%s\n", ssid, bssid, kanal, "", rssi, stoy, rate, phy, baand, "" }'
}

wifi_airport() {
  kjor_timeout 8 "$AIRPORT_BIN" -I 2>/dev/null | awk '
    { l = $0; sub(/^[ \t]+/, "", l); p = index(l, ": "); if (p == 0) next
      k = substr(l, 1, p - 1); v = substr(l, p + 2)
      if (k == "agrCtlRSSI")  rssi = v
      if (k == "agrCtlNoise") stoy = v
      if (k == "lastTxRate")  rate = v
      if (k == "BSSID")       bssid = v
      if (k == "SSID")        ssid = v
      if (k == "channel")     { kanal = v; sub(/,.*/, "", kanal) }
    }
    END { printf "%s|%s|%s|%s|%s|%s|%s|%s|%s|%s\n", ssid, bssid, kanal, "", rssi, stoy, rate, "", "", "" }'
}

wifi_sysprof() {
  kjor_timeout 20 system_profiler SPAirPortDataType -detailLevel basic 2>/dev/null | awk '
    /Current Network Information:/ { f = 1; next }
    f && /Other Local Wi-Fi Networks:/ { exit }
    f && ssid == "" { s = $0; sub(/^[ \t]+/, "", s); sub(/:$/, "", s); ssid = s; next }
    f {
      l = $0; sub(/^[ \t]+/, "", l); p = index(l, ": "); if (p == 0) next
      k = substr(l, 1, p - 1); v = substr(l, p + 2)
      if (k == "PHY Mode")      phy = v
      if (k == "Transmit Rate") rate = v
      if (k == "Channel") {
        kanal = v; sub(/ .*/, "", kanal)
        if (v ~ /2GHz/) baand = "2.4 GHz"; else if (v ~ /5GHz/) baand = "5 GHz"; else if (v ~ /6GHz/) baand = "6 GHz"
      }
      if (k == "Signal / Noise") { rssi = v; sub(/ .*/, "", rssi); stoy = v; sub(/.*\/ */, "", stoy); sub(/ .*/, "", stoy) }
      if (k == "BSSID") bssid = v
    }
    END { printf "%s|%s|%s|%s|%s|%s|%s|%s|%s|%s\n", ssid, bssid, kanal, "", rssi, stoy, rate, phy, baand, "" }'
}

wifi_ipconfig() {  # macOS 14+: SSID og (noen ganger) BSSID. Skriver: ssid|bssid
  kjor_timeout 5 ipconfig getsummary "$GRENSESNITT" 2>/dev/null | awk '
    { l = $0; sub(/^[ \t]+/, "", l) }
    l ~ /^SSID : /  && ssid == ""  { ssid = substr(l, 8) }
    l ~ /^BSSID : / && bssid == "" { bssid = substr(l, 9) }
    END { printf "%s|%s\n", ssid, bssid }'
}

wifi_termux() {
  local json
  json=$(kjor_timeout 8 termux-wifi-connectioninfo 2>/dev/null)
  [ -n "$json" ] || { echo "|||||||||"; return; }
  if [ -n "$PY_BIN" ]; then
    printf '%s' "$json" | "$PY_BIN" -c '
import json, sys
try:
    d = json.load(sys.stdin)
except Exception:
    d = {}
def g(k):
    v = d.get(k, "")
    return "" if v is None else str(v)
print("|".join([g("ssid"), g("bssid"), "", g("frequency_mhz"), g("rssi"), "", g("link_speed_mbps"), "", "", ""]))' 2>/dev/null
  elif [ -n "$JQ_BIN" ]; then
    printf '%s' "$json" | "$JQ_BIN" -r '[.ssid, .bssid, "", .frequency_mhz, .rssi, "", .link_speed_mbps, "", "", ""] | map(if . == null then "" else tostring end) | join("|")' 2>/dev/null
  else
    printf '%s|%s|%s|%s|%s|%s|%s|%s|%s|%s\n' \
      "$(printf '%s' "$json" | sed -n 's/.*"ssid": *"\([^"]*\)".*/\1/p' | head -n 1)" \
      "$(printf '%s' "$json" | sed -n 's/.*"bssid": *"\([^"]*\)".*/\1/p' | head -n 1)" \
      "" \
      "$(printf '%s' "$json" | sed -n 's/.*"frequency_mhz": *\([0-9]*\).*/\1/p' | head -n 1)" \
      "$(printf '%s' "$json" | sed -n 's/.*"rssi": *\(-\{0,1\}[0-9]*\).*/\1/p' | head -n 1)" \
      "" \
      "$(printf '%s' "$json" | sed -n 's/.*"link_speed_mbps": *\([0-9]*\).*/\1/p' | head -n 1)" \
      "" "" ""
  fi
}

# Velg Wi-Fi-kilde én gang ved oppstart (og mål kalltiden)
finn_wifi_kilde() {
  local t0 t1 rad ms
  t0=$(naa_ms)
  case "$OS" in
    linux)
      if command -v iw >/dev/null 2>&1 && [ "$GRENSESNITT" != "ukjent" ] \
         && kjor_timeout 5 iw dev "$GRENSESNITT" link >/dev/null 2>&1; then
        WIFI_KILDE="iw"
        WIFI_KILDE_TEKST="iw dev $GRENSESNITT link (+ survey dump for støy)"
      elif command -v nmcli >/dev/null 2>&1 && kjor_timeout 8 nmcli -t -f ACTIVE dev wifi >/dev/null 2>&1; then
        WIFI_KILDE="nmcli"
        WIFI_KILDE_TEKST="nmcli dev wifi (RSSI er omregnet fra prosent: dBm ≈ %/2 − 100)"
      elif command -v iwconfig >/dev/null 2>&1 && [ "$GRENSESNITT" != "ukjent" ] \
           && kjor_timeout 5 iwconfig "$GRENSESNITT" >/dev/null 2>&1; then
        WIFI_KILDE="iwconfig"; WIFI_KILDE_TEKST="iwconfig $GRENSESNITT"
      elif [ -r /proc/net/wireless ] && grep -q "^ *$GRENSESNITT:" /proc/net/wireless 2>/dev/null; then
        WIFI_KILDE="procwireless"; WIFI_KILDE_TEKST="/proc/net/wireless (bare RSSI/støy — SSID/BSSID ukjent)"
        HEURISTIKK=1
      else
        WIFI_KILDE="ingen"
        WIFI_INSTALL="sudo apt install iw   (Fedora: sudo dnf install iw; alternativt network-manager for nmcli)"
      fi
      ;;
    macos)
      if kjor_timeout 8 sudo -n wdutil info >/dev/null 2>&1; then
        WIFI_KILDE="wdutil"; WIFI_KILDE_TEKST="sudo -n wdutil info (fungerte uten passord)"
      elif [ -x "$AIRPORT_BIN" ]; then
        WIFI_KILDE="airport"; WIFI_KILDE_TEKST="airport -I (eldre macOS)"
      elif command -v system_profiler >/dev/null 2>&1; then
        WIFI_KILDE="sysprof"
        WIFI_KILDE_TEKST="system_profiler SPAirPortDataType (+ ipconfig getsummary for SSID/BSSID)"
      else
        WIFI_KILDE="ingen"
        WIFI_INSTALL="kjør «sudo wdutil info» én gang manuelt, eller start skriptet med sudo -n-tilgang cachet"
      fi
      ;;
    termux)
      if command -v termux-wifi-connectioninfo >/dev/null 2>&1; then
        WIFI_KILDE="termux"; WIFI_KILDE_TEKST="termux-wifi-connectioninfo (Termux:API)"
      else
        WIFI_KILDE="ingen"
        WIFI_INSTALL="pkg install termux-api  + installer appen Termux:API (F-Droid) og gi den posisjonstilgang"
      fi
      ;;
  esac
  if [ "$WIFI_KILDE" != "ingen" ]; then
    rad=$(hent_wifi_rad)
    t1=$(naa_ms)
    ms=$((t1 - t0))
    WIFI_MS_SIST=$ms
    [ -n "$rad" ] || true
    if [ "$ms" -gt $((INTERVALL_MS / 2)) ]; then
      INTERVALL_EFF_MS=$((ms + 300))
      [ "$INTERVALL_EFF_MS" -lt "$INTERVALL_MS" ] && INTERVALL_EFF_MS=$INTERVALL_MS
      status INFO "Wi-Fi-kildens kalltid" "$ms ms per kall ($WIFI_KILDE) — effektivt intervall blir ca. $(awk -v m="$INTERVALL_EFF_MS" 'BEGIN { printf "%.1f", m / 1000 }') s i stedet for $INTERVALL s"
      INTERVALL_MELDT=1
    fi
  fi
}

hent_wifi_rad() {
  case "$WIFI_KILDE" in
    iw)           wifi_iw ;;
    nmcli)        wifi_nmcli ;;
    iwconfig)     wifi_iwconfig ;;
    procwireless) wifi_procwireless ;;
    wdutil)       wifi_wdutil ;;
    airport)      wifi_airport ;;
    sysprof)      wifi_sysprof ;;
    termux)       wifi_termux ;;
    *)            echo "" ;;
  esac
}

# Henter én prøve og normaliserer til W_*-variablene (ukjent der data mangler)
hent_wifi() {
  local rad ssid bssid kanal freq rssi stoy rate phy baand merknad ekstra s2 b2
  W_SSID=ukjent; W_BSSID=ukjent; W_KANAL=ukjent; W_BAAND=ukjent
  W_RSSI=ukjent; W_STOY=ukjent; W_SNR=ukjent; W_RATE=ukjent; W_PHY=ukjent; W_MERKNAD=""
  [ "$WIFI_KILDE" != "ingen" ] || return 0
  rad=$(hent_wifi_rad)
  [ -n "$rad" ] || return 0
  ssid=""; bssid=""; kanal=""; freq=""; rssi=""; stoy=""; rate=""; phy=""; baand=""; merknad=""
  IFS='|' read -r ssid bssid kanal freq rssi stoy rate phy baand merknad <<EOF
$rad
EOF
  # macOS: system_profiler skjuler BSSID (og noen ganger SSID) → suppler fra ipconfig getsummary
  if [ "$WIFI_KILDE" = "sysprof" ] && command -v ipconfig >/dev/null 2>&1; then
    ekstra=$(wifi_ipconfig)
    s2=""; b2=""
    IFS='|' read -r s2 b2 <<EOF
$ekstra
EOF
    [ -n "$b2" ] && bssid="$b2"
    { [ -z "$ssid" ] || [ "$ssid" = "<redacted>" ]; } && [ -n "$s2" ] && ssid="$s2"
  fi
  if [ "$WIFI_KILDE" = "iw" ] && [ -n "$rssi" ]; then
    stoy=$(wifi_iw_stoy)
  fi

  # SSID
  case "$ssid" in
    '' | '<redacted>' | '<unknown ssid>' | 'None' | 'null') W_SSID=ukjent ;;
    *) W_SSID=$ssid ;;
  esac
  # BSSID
  bssid=$(normaliser_bssid "$bssid")
  if er_bssid "$bssid"; then
    W_BSSID=$bssid
  else
    W_BSSID=ukjent
    if [ "$WIFI_KILDE" = "termux" ] && [ "$TERMUX_POS_MELDT" -eq 0 ] && [ -n "$rssi" ]; then
      TERMUX_POS_MELDT=1
      status INFO "BSSID skjult av Android" "gi Termux:API posisjonstilgang (Innstillinger → Apper → Termux:API → Tillatelser → Posisjon) for å se BSSID — bruker kanal-/RSSI-heuristikk imens"
    fi
    if [ "$HEURISTIKK_MELDT" -eq 0 ] && [ -n "$rssi" ]; then
      HEURISTIKK_MELDT=1; HEURISTIKK=1
      status INFO "Heuristikk-modus" "BSSID utilgjengelig fra $WIFI_KILDE — roam anslås fra kanalskifte / RSSI-hopp ≥12 dB («mulig roam»)"
    fi
  fi
  # Kanal og bånd
  freq=${freq%%.*}
  if er_heltall "$kanal" && [ "$kanal" -gt 0 ]; then W_KANAL=$kanal
  elif er_heltall "$freq"; then W_KANAL=$(freq_til_kanal "$freq"); fi
  if [ -n "$baand" ]; then W_BAAND=$baand
  elif er_heltall "$freq"; then W_BAAND=$(freq_til_baand "$freq")
  elif er_heltall "$W_KANAL"; then W_BAAND=$(kanal_til_baand "$W_KANAL"); fi
  # RSSI, støy, SNR
  rssi=${rssi%%.*}
  if er_heltall "$rssi" && [ "$rssi" -lt 0 ] && [ "$rssi" -gt -120 ]; then W_RSSI=$rssi; fi
  stoy=${stoy%%.*}
  if er_heltall "$stoy" && [ "$stoy" -lt 0 ] && [ "$stoy" -gt -130 ]; then W_STOY=$stoy; fi
  if [ "$W_RSSI" != ukjent ] && [ "$W_STOY" != ukjent ]; then W_SNR=$((W_RSSI - W_STOY)); fi
  # Tx-rate og PHY
  rate=${rate%% *}
  if er_tall "$rate" && flt_ge "$rate" 0; then W_RATE=$rate; fi
  [ -n "$phy" ] && W_PHY=$phy
  W_MERKNAD=$merknad
  if [ "$WIFI_KILDE" = "nmcli" ] && [ "$NMCLI_MELDT" -eq 0 ] && [ "$W_RSSI" != ukjent ]; then
    NMCLI_MELDT=1
    status INFO "RSSI-omregning" "nmcli gir signal i prosent; dBm ≈ prosent/2 − 100 (omtrentlig)"
  fi
  return 0
}

### 6. Ping
# ping_en MÅL → skriver RTT (ms) ved svar. Retur: 0 = svar, 1 = tap, 2 = ping mangler
ping_en() {
  local maal="$1" ut rtt
  [ -n "$PING_BIN" ] || return 2
  case "$OS" in
    macos) ut=$(kjor_timeout 3 "$PING_BIN" $PING_N -c 1 -W 1000 -t 2 "$maal" 2>/dev/null) ;;
    *)     ut=$(kjor_timeout 3 "$PING_BIN" $PING_N -c 1 -W 1 "$maal" 2>/dev/null) ;;
  esac
  rtt=$(printf '%s\n' "$ut" | sed -n 's/.*time[=<]\([0-9.][0-9.]*\) *ms.*/\1/p' | head -n 1)
  if er_tall "$rtt"; then printf '%s\n' "$rtt"; return 0; fi
  return 1
}

### 7. Roam-, gap- og sticky-logikk
kb_tekst() {  # kanal/bånd-tekst
  local k="${1:-ukjent}" b="${2:-ukjent}"
  if [ "$k" = ukjent ] && [ "$b" = ukjent ]; then echo "ukjent"; else echo "k$k/$b"; fi
}

roam_status_for_gap() {
  local gap="$1"
  if   [ "$gap" -le 100 ]; then echo PASS
  elif [ "$gap" -le 500 ]; then echo WARN
  else echo FAIL; fi
}

# Oppdager roam mellom sist kjente verdier og gjeldende prøve. Setter ROAM_TYPE.
oppdag_roam() {
  local d
  ROAM_TYPE=""
  [ "$HAR_FORRIGE" -eq 1 ] || return 1
  if [ "$SIST_BSSID" != ukjent ] && [ "$W_BSSID" != ukjent ]; then
    [ "$SIST_BSSID" != "$W_BSSID" ] && ROAM_TYPE="roam (BSSID-bytte)"
  elif [ "$W_BSSID" = ukjent ] && [ "$SIST_BSSID" = ukjent ]; then
    # BSSID utilgjengelig → heuristikk
    if [ "$SIST_KANAL" != ukjent ] && [ "$W_KANAL" != ukjent ] && [ "$SIST_KANAL" != "$W_KANAL" ]; then
      ROAM_TYPE="mulig roam (kanalskifte)"
    elif er_heltall "$F_RSSI" && er_heltall "$W_RSSI"; then
      d=$((W_RSSI - F_RSSI)); [ "$d" -lt 0 ] && d=$((-d))
      [ "$d" -ge 12 ] && ROAM_TYPE="mulig roam (RSSI-hopp $d dB)"
    fi
  fi
  [ -n "$ROAM_TYPE" ]
}

start_roam() {  # kalles når roam oppdages i gjeldende prøve
  ROAM_VENTER=1
  ROAM_NR=$((ANTALL_ROAM + ANTALL_MULIG_ROAM + 1))
  ROAM_TID=$(naa_kl)
  ROAM_MS=$PROVE_MS
  ROAM_FRA_BSSID=$SIST_BSSID; ROAM_TIL_BSSID=$W_BSSID
  ROAM_FRA_KB=$(kb_tekst "$SIST_KANAL" "$SIST_BAAND"); ROAM_TIL_KB=$(kb_tekst "$W_KANAL" "$W_BAAND")
  ROAM_FRA_RSSI=$SIST_RSSI; ROAM_TIL_RSSI=$W_RSSI
  ROAM_TYPE_AKTIV=$ROAM_TYPE
  ROAM_FEIL_FOER=$FEIL_STREAK
  ROAM_FEIL_ETTER=0
  case "$ROAM_TYPE" in
    mulig*) ANTALL_MULIG_ROAM=$((ANTALL_MULIG_ROAM + 1)) ;;
    *)      ANTALL_ROAM=$((ANTALL_ROAM + 1)) ;;
  esac
  # Roam avslutter en evt. sticky-episode
  avslutt_sticky "roam"
}

# avslutt_roam OK_NAA(1/0) — skriver ROAM-linjen når første ping etter roam lykkes (eller ved slutt)
avslutt_roam() {
  local ok="$1" gap st tid_ok tid_ok_tekst tekst rad ping_bin_tekst
  [ "$ROAM_VENTER" -eq 1 ] || return 0
  ROAM_VENTER=0
  gap=$(( (ROAM_FEIL_FOER + ROAM_FEIL_ETTER) * INTERVALL_EFF_MS ))
  if [ -z "$PING_BIN" ] || [ -z "$GATEWAY" ]; then
    gap=""; st="INFO"; tid_ok="ukjent (ingen gateway-ping)"; tid_ok_tekst="første ping-svar: ukjent (ingen gateway-ping)"
  elif [ "$ok" -eq 1 ]; then
    st=$(roam_status_for_gap "$gap")
    tid_ok="$((PROVE_SLUTT_MS - ROAM_MS)) ms"; tid_ok_tekst="første ping-svar etter $tid_ok"
  else
    st="FAIL"
    tid_ok="ingen før loggen sluttet"; tid_ok_tekst="ingen vellykket gateway-ping etter roam før loggen sluttet"
  fi
  [ -n "$gap" ] && ROAM_GAPS="$ROAM_GAPS $gap"
  ping_bin_tekst="$((ROAM_FEIL_FOER + ROAM_FEIL_ETTER)) feilede gateway-ping × $INTERVALL_EFF_MS ms"
  tekst="ROAM #$ROAM_NR $ROAM_TID  $ROAM_FRA_BSSID → $ROAM_TIL_BSSID  $ROAM_FRA_KB → $ROAM_TIL_KB  RSSI $ROAM_FRA_RSSI → $ROAM_TIL_RSSI dBm  gap ≈ ${gap:-ukjent} ms ($ping_bin_tekst)  $tid_ok_tekst  [$st] $ROAM_TYPE_AKTIV"
  printf '%s%s%s\n' "$C_MAG" "$tekst" "$C_NULL"
  ROAM_KONSOLL="${ROAM_KONSOLL}${tekst}
"
  rad="| $ROAM_NR | $ROAM_TID | $ROAM_FRA_BSSID → $ROAM_TIL_BSSID | $ROAM_FRA_KB → $ROAM_TIL_KB | $ROAM_FRA_RSSI → $ROAM_TIL_RSSI | ${gap:-ukjent} | $tid_ok | $ROAM_TYPE_AKTIV | $st |"
  ROAM_TABELL="${ROAM_TABELL}${rad}
"
}

# Sticky client: RSSI < -75 dBm i mer enn 10 s uten roam
sjekk_sticky() {
  local varighet
  if er_heltall "$W_RSSI" && [ "$W_RSSI" -lt -75 ]; then
    if [ "$STICKY_START_MS" -eq 0 ]; then
      STICKY_START_MS=$PROVE_MS; STICKY_START_TID=$(naa_kl); STICKY_START_RSSI=$W_RSSI; STICKY_MIN_RSSI=$W_RSSI; STICKY_MELDT=0
    else
      [ "$W_RSSI" -lt "$STICKY_MIN_RSSI" ] && STICKY_MIN_RSSI=$W_RSSI
      varighet=$(( (PROVE_MS - STICKY_START_MS) / 1000 ))
      if [ "$STICKY_MELDT" -eq 0 ] && [ "$varighet" -gt 10 ]; then
        STICKY_MELDT=1
        ANTALL_STICKY=$((ANTALL_STICKY + 1))
        status WARN "Sticky client" "RSSI $W_RSSI dBm i $varighet s uten roam (fra $STICKY_START_TID) — sticky client – sjekk min-RSSI / BSS transition (802.11v) på AP-ene" "RSSI < -75 dBm i >10 s"
      fi
    fi
  else
    avslutt_sticky "RSSI bedret"
  fi
}

avslutt_sticky() {  # $1 = årsak til at episoden slutter
  local varighet
  [ "$STICKY_START_MS" -ne 0 ] || return 0
  if [ "$STICKY_MELDT" -eq 1 ]; then
    varighet=$(( (PROVE_MS - STICKY_START_MS) / 1000 ))
    STICKY_TABELL="${STICKY_TABELL}| $STICKY_START_TID | $varighet s | $STICKY_START_RSSI dBm | $STICKY_MIN_RSSI dBm | $1 |
"
  fi
  STICKY_START_MS=0; STICKY_MELDT=0; STICKY_MIN_RSSI=""
}

### 8. Oppsummering (konsoll + Markdown) og trap
median_av_liste() {  # mellomromseparert liste → median (heltallslister)
  tr ' ' '\n' <<EOF | sed '/^$/d' | sort -n | awk '{ a[NR] = $1 } END { if (NR == 0) { print "ukjent"; exit } if (NR % 2) print a[(NR + 1) / 2]; else printf "%d\n", (a[NR / 2] + a[NR / 2 + 1]) / 2 }'
$1
EOF
}

maks_av_liste() {
  tr ' ' '\n' <<EOF | sed '/^$/d' | sort -n | tail -n 1
$1
EOF
}

avslutt() {
  local n gw_sendt gw_tapt b24 bkjent inet_sendt inet_tapt rssi_kjent rssi_med rssi_min
  local tap_pst inet_tap_pst b24_pst p50 p95 med_gap maks_gap st k v slutt_tid varighet_s
  local bssid_tabell csv_hale roam_totalt

  [ "$AVSLUTTET" -eq 0 ] || return 0
  AVSLUTTET=1
  trap '' INT TERM
  # Hvis konsollen er borte (f.eks. «| tee» som døde ved Ctrl-C) skal rapportfilene likevel skrives
  printf '\n' 2>/dev/null || exec >/dev/null 2>&1

  melding "Avslutter — skriver oppsummering …"
  slutt_tid=$(naa_iso)
  PROVE_MS=$(naa_ms); PROVE_SLUTT_MS=$PROVE_MS
  varighet_s=$(( (PROVE_MS - START_MS) / 1000 ))

  # Ventende roam og sticky-episode lukkes
  avslutt_roam 0
  avslutt_sticky "loggen sluttet"

  echo "=== $SEKSJON — oppsummering ==="

  n=0; gw_sendt=0; gw_tapt=0; b24=0; bkjent=0; inet_sendt=0; inet_tapt=0; rssi_kjent=0; rssi_min=ukjent
  if [ -s "$CSV_FIL" ]; then
    while IFS='=' read -r k v; do
      case "$k" in
        n) n=$v ;; gw_sendt) gw_sendt=$v ;; gw_tapt) gw_tapt=$v ;;
        b24) b24=$v ;; bkjent) bkjent=$v ;;
        inet_sendt) inet_sendt=$v ;; inet_tapt) inet_tapt=$v ;;
        rssi_kjent) rssi_kjent=$v ;; rssi_min) rssi_min=$v ;;
      esac
    done <<EOF
$(awk -F, 'NR > 1 {
      n++
      if ($11 == "0" || $11 == "1") { gs++; if ($11 == "1") gt++ }
      if ($5 != "ukjent" && $5 != "") { bk++; if ($5 == "2.4 GHz") b24++ }
      if ($13 == "0" || $13 == "1") { is++; if ($13 == "1") it++ }
      if ($6 ~ /^-?[0-9]+$/) { rk++; if (rmin == "" || $6 + 0 < rmin + 0) rmin = $6 }
    }
    END { printf "n=%d\ngw_sendt=%d\ngw_tapt=%d\nb24=%d\nbkjent=%d\ninet_sendt=%d\ninet_tapt=%d\nrssi_kjent=%d\nrssi_min=%s\n", n, gs, gt, b24, bk, is, it, rk, (rmin == "" ? "ukjent" : rmin) }' "$CSV_FIL")
EOF
  fi

  # Persentiler for gateway-RTT
  p50=ukjent; p95=ukjent
  if [ -s "$CSV_FIL" ] && [ "$gw_sendt" -gt 0 ]; then
    read -r p50 p95 <<EOF
$(awk -F, 'NR > 1 && $10 ~ /^[0-9.]+$/ { print $10 }' "$CSV_FIL" | sort -n | awk '
      { a[NR] = $1 }
      END { if (NR == 0) { print "ukjent ukjent"; exit }
            i50 = int((NR + 1) / 2); i95 = int(NR * 0.95 + 0.999999); if (i95 < 1) i95 = 1; if (i95 > NR) i95 = NR
            printf "%.1f %.1f\n", a[i50], a[i95] }')
EOF
  fi
  rssi_med=ukjent
  if [ -s "$CSV_FIL" ] && [ "$rssi_kjent" -gt 0 ]; then
    rssi_med=$(awk -F, 'NR > 1 && $6 ~ /^-?[0-9]+$/ { print $6 }' "$CSV_FIL" | sort -n | awk '{ a[NR] = $1 } END { if (NR) print a[int((NR + 1) / 2)]; else print "ukjent" }')
  fi

  # Statuslinjer
  status INFO "Prøver" "$n prøver over $varighet_s s (intervall $INTERVALL s, effektivt $(awk -v m="$INTERVALL_EFF_MS" 'BEGIN { printf "%.1f", m / 1000 }') s) — grensesnitt $GRENSESNITT, kilde: $WIFI_KILDE_TEKST"
  if [ "$WIFI_KILDE" = "ingen" ]; then
    status SKIP "Wi-Fi-data" "ingen Wi-Fi-kilde tilgjengelig — installer: $WIFI_INSTALL"
  elif [ "$rssi_kjent" -eq 0 ]; then
    status SKIP "Wi-Fi-data" "kilden ($WIFI_KILDE) ga ingen RSSI — er enheten koblet til Wi-Fi?"
  else
    [ "$HEURISTIKK" -eq 1 ] && status INFO "Heuristikk-modus" "BSSID var utilgjengelig — roam er anslått fra kanalskifte / RSSI-hopp ≥12 dB («mulig roam»)"
  fi

  roam_totalt=$((ANTALL_ROAM + ANTALL_MULIG_ROAM))
  if [ "$rssi_kjent" -gt 0 ] || [ "$roam_totalt" -gt 0 ]; then
    status INFO "Antall roam" "$ANTALL_ROAM sikre (BSSID-bytte) + $ANTALL_MULIG_ROAM mulige"
  fi
  med_gap=$(median_av_liste "$ROAM_GAPS"); maks_gap=$(maks_av_liste "$ROAM_GAPS")
  if [ "$roam_totalt" -eq 0 ]; then
    if [ "$rssi_kjent" -gt 0 ]; then
      status INFO "Roam-gap" "ingen roam registrert — gå lenger / mellom flere AP-er for å teste roaming" "PASS ≤100 ms, WARN ≤500 ms, FAIL >500 ms"
    else
      status SKIP "Roam-gap" "ingen Wi-Fi-data" "PASS ≤100 ms, WARN ≤500 ms, FAIL >500 ms"
    fi
  elif [ -z "$maks_gap" ] || [ "$med_gap" = ukjent ]; then
    status SKIP "Roam-gap" "kunne ikke måles (ingen gateway-ping)" "PASS ≤100 ms, WARN ≤500 ms, FAIL >500 ms"
  else
    status "$(roam_status_for_gap "$med_gap")" "Roam-gap median" "$med_gap ms over $roam_totalt roam" "PASS ≤100 ms, WARN ≤500 ms, FAIL >500 ms"
    status "$(roam_status_for_gap "$maks_gap")" "Roam-gap maks" "$maks_gap ms" "PASS ≤100 ms, WARN ≤500 ms, FAIL >500 ms"
  fi

  if [ "$bkjent" -gt 0 ]; then
    b24_pst=$(awk -v a="$b24" -v b="$bkjent" 'BEGIN { printf "%.1f", 100 * a / b }')
    if [ "$b24" -eq 0 ]; then st=PASS; else st=WARN; fi
    status "$st" "Andel prøver på 2,4 GHz" "$b24_pst % ($b24 av $bkjent)" "0 % — Adm-nett bør bruke 5/6 GHz"
  else
    status SKIP "Andel prøver på 2,4 GHz" "bånd ukjent" "0 %"
  fi

  if [ "$ANTALL_STICKY" -eq 0 ]; then
    if [ "$rssi_kjent" -gt 0 ]; then st=PASS; else st=SKIP; fi
    status "$st" "Sticky client-episoder" "0" "RSSI < -75 dBm i >10 s uten roam"
  else
    status WARN "Sticky client-episoder" "$ANTALL_STICKY — sticky client – sjekk min-RSSI / BSS transition (802.11v) på AP-ene" "RSSI < -75 dBm i >10 s uten roam"
  fi

  if [ "$rssi_kjent" -gt 0 ]; then
    if   [ "$rssi_med" -ge -65 ]; then st=PASS
    elif [ "$rssi_med" -ge -72 ]; then st=WARN
    else st=FAIL; fi
    status "$st" "RSSI median" "$rssi_med dBm (svakeste $rssi_min dBm)" "PASS ≥ -65 dBm, WARN ≥ -72 dBm, FAIL < -72 dBm"
  fi

  if [ -z "$PING_BIN" ]; then
    status SKIP "Pakketap mot gateway" "ping mangler — installer: $PING_INSTALL" "PASS <1 %, WARN <3 %, FAIL ≥3 %"
  elif [ -z "$GATEWAY" ]; then
    status SKIP "Pakketap mot gateway" "gateway ikke funnet ($GATEWAY_KILDE)" "PASS <1 %, WARN <3 %, FAIL ≥3 %"
  elif [ "$gw_sendt" -eq 0 ]; then
    status SKIP "Pakketap mot gateway" "ingen ping sendt" "PASS <1 %, WARN <3 %, FAIL ≥3 %"
  else
    tap_pst=$(awk -v a="$gw_tapt" -v b="$gw_sendt" 'BEGIN { printf "%.1f", 100 * a / b }')
    if flt_lt "$tap_pst" 1; then st=PASS; elif flt_lt "$tap_pst" 3; then st=WARN; else st=FAIL; fi
    status "$st" "Pakketap mot gateway $GATEWAY" "$tap_pst % ($gw_tapt av $gw_sendt)" "PASS <1 %, WARN <3 %, FAIL ≥3 %"
    if [ "$p50" != ukjent ]; then
      if flt_lt "$p50" 10.0001; then st=PASS; elif flt_lt "$p50" 30.0001; then st=WARN; else st=FAIL; fi
      status "$st" "Gateway RTT p50" "$p50 ms" "PASS ≤10 ms, WARN ≤30 ms, FAIL >30 ms"
      status INFO "Gateway RTT p95" "$p95 ms"
    else
      status FAIL "Gateway RTT" "ingen svar fra $GATEWAY i det hele tatt" "PASS ≤10 ms"
    fi
    if [ "$inet_sendt" -gt 0 ]; then
      inet_tap_pst=$(awk -v a="$inet_tapt" -v b="$inet_sendt" 'BEGIN { printf "%.1f", 100 * a / b }')
      status INFO "Pakketap mot 1.1.1.1 (hver 5. prøve)" "$inet_tap_pst % ($inet_tapt av $inet_sendt)"
    fi
  fi
  status INFO "Filer" "CSV: $CSV_FIL — Markdown: $MD_FIL"
  echo "Sammendrag: PASS $T_PASS · WARN $T_WARN · FAIL $T_FAIL · SKIP $T_SKIP · INFO $T_INFO"

  # BSSID-tabell
  bssid_tabell=""
  if [ -s "$CSV_FIL" ]; then
    bssid_tabell=$(awk -F, -v iv="$INTERVALL_EFF_MS" 'NR > 1 {
        b = $3; if (b == "") b = "ukjent"
        s = $17; for (i = 18; i <= NF; i++) s = s "," $i
        gsub(/^"|"$/, "", s); gsub(/""/, "\"", s)
        if (!(b in sett)) { sett[b] = 1; rekke[++nb] = b; kanal[b] = $4; baand[b] = $5; ssid[b] = s }
        ant[b]++
        if ($6 ~ /^-?[0-9]+$/) { rsum[b] += $6; rant[b]++ }
        if (fb != "") { d = iv; if ($2 ~ /^[0-9]+$/ && fms ~ /^[0-9]+$/ && $2 >= fms && $2 - fms < 10 * iv + 60000) d = $2 - fms; tid[fb] += d }
        fb = b; fms = $2
      }
      END {
        if (fb != "") tid[fb] += iv
        for (i = 1; i <= nb; i++) { b = rekke[i]
          r = (rant[b] ? sprintf("%.0f dBm", rsum[b] / rant[b]) : "ukjent")
          printf "| %s | %s | %s | %s | %d | %.0f s | %s |\n", b, ssid[b], kanal[b], baand[b], ant[b], tid[b] / 1000, r }
      }' "$CSV_FIL")
  fi
  csv_hale=""
  [ -s "$CSV_FIL" ] && csv_hale=$(tail -n 41 "$CSV_FIL")

  {
    echo "# nettsjekk roaming-logg — $VERT — $STEMPEL"
    echo
    echo "- Verktøy: roaming-logg.sh versjon $VERSJON (nettsjekk) — endrer ingenting, kun lesing og målinger"
    echo "- Vert: $VERT · OS: $OS_TEKST"
    echo "- Start: $START_TID · Slutt: $slutt_tid · Varighet: $varighet_s s · Prøver: $n"
    echo "- Intervall: $INTERVALL s (effektivt $(awk -v m="$INTERVALL_EFF_MS" 'BEGIN { printf "%.1f", m / 1000 }') s) · Varighet satt: $VARIGHET s (0 = til Ctrl-C)"
    echo "- Grensesnitt: $GRENSESNITT ($GRENSESNITT_KILDE) · Gateway: ${GATEWAY:-ukjent} (${GATEWAY_KILDE:-ukjent})"
    echo "- Wi-Fi-kilde: $WIFI_KILDE_TEKST · Ping: ${PING_BIN:-mangler} · Klokke: $MS_KILDE"
    echo "- CSV: $CSV_FIL"
    echo
    echo "## $SEKSJON — status"
    echo
    echo '```'
    printf '%s' "$STATUS_LINJER"
    echo "Sammendrag: PASS $T_PASS · WARN $T_WARN · FAIL $T_FAIL · SKIP $T_SKIP · INFO $T_INFO"
    echo '```'
    echo
    echo "## Terskler"
    echo
    echo "- Roam-gap: PASS ≤100 ms, WARN ≤500 ms, FAIL >500 ms. Gap = antall feilede gateway-ping rett før og etter roam × effektivt intervall ($INTERVALL_EFF_MS ms). Oppløsningen er altså ett intervall."
    echo "- Pakketap mot gateway: PASS <1 %, WARN <3 %, FAIL ≥3 %"
    echo "- Sticky client: RSSI < -75 dBm i >10 s uten roam → WARN (sjekk min-RSSI / BSS transition 802.11v på AP-ene)"
    echo "- 2,4 GHz: andel prøver på 2,4 GHz > 0 % → WARN (Adm-nett bør bruke 5/6 GHz)"
    echo "- RSSI median: PASS ≥ -65 dBm, WARN ≥ -72 dBm, FAIL < -72 dBm"
    echo "- Gateway RTT p50: PASS ≤10 ms, WARN ≤30 ms, FAIL >30 ms"
    echo "- Roam-deteksjon: BSSID-bytte = sikker roam. Uten BSSID (macOS-skjuling/Android uten posisjonstilgang): kanalskifte eller RSSI-hopp ≥12 dB mellom to prøver = «mulig roam»."
    echo
    echo "## Roam-hendelser ($roam_totalt)"
    echo
    if [ -n "$ROAM_TABELL" ]; then
      echo "| # | Tid | BSSID før → etter | Kanal/bånd før → etter | RSSI før → etter (dBm) | Gap (ms) | Første ping-svar | Type | Status |"
      echo "|---|-----|-------------------|------------------------|------------------------|----------|------------------|------|--------|"
      printf '%s' "$ROAM_TABELL"
      echo
      echo "- Median gap: ${med_gap} ms · Maks gap: ${maks_gap:-ukjent} ms"
    else
      echo "Ingen roam registrert."
    fi
    echo
    echo "## Unike BSSID-er (AP-radioer) i loggen"
    echo
    if [ -n "$bssid_tabell" ]; then
      echo "| BSSID | SSID | Kanal | Bånd | Prøver | Tid | Snitt-RSSI |"
      echo "|-------|------|-------|------|--------|-----|------------|"
      printf '%s\n' "$bssid_tabell"
    else
      echo "Ingen data."
    fi
    echo
    echo "## Sticky client-episoder ($ANTALL_STICKY)"
    echo
    if [ -n "$STICKY_TABELL" ]; then
      echo "| Start | Varighet | RSSI ved start | Svakeste RSSI | Sluttårsak |"
      echo "|-------|----------|----------------|---------------|------------|"
      printf '%s' "$STICKY_TABELL"
    else
      echo "Ingen."
    fi
    echo
    echo "## ROAM-linjer (som på konsollen)"
    echo
    echo '```'
    if [ -n "$ROAM_KONSOLL" ]; then printf '%s' "$ROAM_KONSOLL"; else echo "(ingen)"; fi
    echo '```'
    echo
    echo "## Rådata — siste 40 rader av CSV (hele loggen: $CSV_FIL)"
    echo
    echo '```csv'
    if [ -n "$csv_hale" ]; then printf '%s\n' "$csv_hale"; else echo "(tom)"; fi
    echo '```'
  } > "$MD_FIL" 2>/dev/null || feil "Kunne ikke skrive $MD_FIL"

  echo
  melding "Oppsummering skrevet til: $MD_FIL"
  melding "Rådata (CSV):            $CSV_FIL"
  melding "Lim inn innholdet i .md-filen i chatten for analyse."
}

### 9. Hovedløkke
PROVE_MS=0
PROVE_SLUTT_MS=0

skriv_csv_hode() {
  printf 'tid,ms,bssid,kanal,baand,rssi_dbm,stoy_dbm,snr_db,txrate_mbps,gw_rtt_ms,gw_tap,inet_rtt_ms,inet_tap,hendelse,phy,merknad,ssid\n' > "$CSV_FIL" 2>/dev/null \
    || { feil "Kan ikke skrive CSV-filen $CSV_FIL"; exit 2; }
}

hovedlokke() {
  local t0 t1 t2 gw_rtt gw_tap inet_rtt inet_tap rc hendelse rest ssid_kort rssi_farge linje_gw linje_inet syklus_ms
  local ssid_csv rssi_vis stoy_vis rate_vis
  while :; do
    t0=$(naa_ms)
    if [ "$VARIGHET" -gt 0 ] && [ $(( (t0 - START_MS) / 1000 )) -ge "$VARIGHET" ]; then break; fi
    ANTALL_PROVER=$((ANTALL_PROVER + 1))
    PROVE_MS=$t0
    hendelse=""

    hent_wifi
    t1=$(naa_ms)
    WIFI_MS_SIST=$((t1 - t0))

    # Gateway-ping (1 pakke, 1 s timeout)
    gw_rtt=""; gw_tap=""
    if [ -n "$PING_BIN" ] && [ -n "$GATEWAY" ]; then
      gw_rtt=$(ping_en "$GATEWAY"); rc=$?
      if [ "$rc" -eq 0 ]; then gw_tap=0; else gw_tap=1; gw_rtt=""; fi
    fi
    t2=$(naa_ms)
    PROVE_SLUTT_MS=$t2

    # Internett-ping hver 5. prøve
    inet_rtt=""; inet_tap=""
    if [ -n "$PING_BIN" ] && [ $(( (ANTALL_PROVER - 1) % 5 )) -eq 0 ]; then
      inet_rtt=$(ping_en 1.1.1.1); rc=$?
      if [ "$rc" -eq 0 ]; then inet_tap=0; else inet_tap=1; inet_rtt=""; fi
    fi

    # Roam-deteksjon (mot sist kjente verdier) — før streaken oppdateres med denne prøven
    if oppdag_roam; then
      [ "$ROAM_VENTER" -eq 1 ] && avslutt_roam 0
      start_roam
      hendelse=$ROAM_TYPE
    fi
    if [ "$gw_tap" = "1" ]; then
      FEIL_STREAK=$((FEIL_STREAK + 1))
      [ "$ROAM_VENTER" -eq 1 ] && ROAM_FEIL_ETTER=$((ROAM_FEIL_ETTER + 1))
    elif [ "$gw_tap" = "0" ]; then
      FEIL_STREAK=0
    fi
    if [ -z "$hendelse" ] && [ "$HAR_FORRIGE" -eq 1 ] && [ "$W_RSSI" = ukjent ] && [ "$F_RSSI" != ukjent ]; then
      hendelse="ingen Wi-Fi-data"
    fi

    # CSV-rad
    ssid_csv=$(csv_felt "$W_SSID")
    printf '%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s\n' \
      "$(naa_iso)" "$t0" "$W_BSSID" "$W_KANAL" "$W_BAAND" "$W_RSSI" "$W_STOY" "$W_SNR" "$W_RATE" \
      "$gw_rtt" "$gw_tap" "$inet_rtt" "$inet_tap" "$hendelse" "$W_PHY" "${W_MERKNAD//,/ }" "$ssid_csv" >> "$CSV_FIL" 2>/dev/null

    # Kompakt live-linje
    ssid_kort=$W_SSID; [ "${#ssid_kort}" -gt 16 ] && ssid_kort="${ssid_kort:0:15}…"
    rssi_farge=""
    if er_heltall "$W_RSSI"; then
      if [ "$W_RSSI" -ge -65 ]; then rssi_farge=$C_GRONN; elif [ "$W_RSSI" -ge -72 ]; then rssi_farge=$C_GUL; else rssi_farge=$C_ROD; fi
    fi
    if [ -z "$PING_BIN" ] || [ -z "$GATEWAY" ]; then linje_gw="gw —"
    elif [ "$gw_tap" = "0" ]; then linje_gw="gw ${gw_rtt} ms"
    else linje_gw="${C_ROD}gw TAP${C_NULL}"; fi
    linje_inet=""
    if [ -n "$inet_tap" ]; then
      if [ "$inet_tap" = "0" ]; then linje_inet="  inet ${inet_rtt} ms"; else linje_inet="  ${C_ROD}inet TAP${C_NULL}"; fi
    fi
    rssi_vis="ukjent"; stoy_vis="n—"; rate_vis="—"
    er_heltall "$W_RSSI" && rssi_vis="$W_RSSI dBm"
    er_heltall "$W_STOY" && stoy_vis="n$W_STOY"
    er_tall "$W_RATE" && rate_vis="$W_RATE Mb/s"
    printf '%s  %-16s %-17s %-13s %s%-8s%s %-5s %-11s %s%s' \
      "$(naa_kl)" "$ssid_kort" "$W_BSSID" "$(kb_tekst "$W_KANAL" "$W_BAAND")" \
      "$rssi_farge" "$rssi_vis" "$C_NULL" "$stoy_vis" "$rate_vis" "$linje_gw" "$linje_inet"
    [ -n "$hendelse" ] && printf '  %s<< %s>>%s' "$C_MAG" "$hendelse " "$C_NULL"
    printf '\n'

    # Roam ferdigmålt når første gateway-ping lykkes
    [ "$ROAM_VENTER" -eq 1 ] && [ "$gw_tap" = "0" ] && avslutt_roam 1
    if [ "$ROAM_VENTER" -eq 1 ] && [ -z "$PING_BIN$GATEWAY" ]; then avslutt_roam 0; fi

    sjekk_sticky

    # Husk verdier til neste prøve
    HAR_FORRIGE=1
    F_RSSI=$W_RSSI
    [ "$W_BSSID" != ukjent ] && SIST_BSSID=$W_BSSID
    [ "$W_KANAL" != ukjent ] && SIST_KANAL=$W_KANAL
    [ "$W_BAAND" != ukjent ] && SIST_BAAND=$W_BAAND
    [ "$W_RSSI"  != ukjent ] && SIST_RSSI=$W_RSSI

    # Sov resten av intervallet; juster effektivt intervall hvis kildene er trege
    syklus_ms=$(( $(naa_ms) - t0 ))
    if [ "$syklus_ms" -gt "$INTERVALL_EFF_MS" ]; then
      INTERVALL_EFF_MS=$syklus_ms
      if [ "$INTERVALL_MELDT" -eq 0 ] && [ "$syklus_ms" -gt $((INTERVALL_MS + INTERVALL_MS / 2)) ]; then
        INTERVALL_MELDT=1
        status INFO "Effektivt intervall" "én prøve tar $syklus_ms ms (Wi-Fi-kilde $WIFI_MS_SIST ms + ping) — effektivt intervall blir ca. $(awk -v m="$syklus_ms" 'BEGIN { printf "%.1f", m / 1000 }') s i stedet for $INTERVALL s"
      fi
    fi
    rest=$((INTERVALL_MS - syklus_ms))
    [ "$rest" -gt 0 ] && sov_ms "$rest"
  done
}

# ---- Oppstart ----
les_parametre "$@"
sett_farger
finn_os
VERT=$(uname -n 2>/dev/null || hostname 2>/dev/null || echo ukjent)
VERT=${VERT%%.*}
[ -n "$VERT" ] || VERT=ukjent
STEMPEL=$(date +%Y%m%d-%H%M%S)
CSV_FIL="${RAPPORTMAPPE%/}/roaming-logg-$VERT-$STEMPEL.csv"
MD_FIL="${RAPPORTMAPPE%/}/roaming-logg-$VERT-$STEMPEL.md"
START_TID=$(naa_iso)

trap 'avslutt; exit 0' INT TERM
trap 'avslutt' EXIT
trap '' PIPE   # brutt rør skal ikke drepe skriptet før oppsummeringen er skrevet

echo "nettsjekk roaming-logg.sh versjon $VERSJON — $OS_TEKST — vert $VERT"
echo "Gå rundt på området med enheten. Hold gjerne en videosamtale/strøm gående. Ctrl-C avslutter og skriver oppsummering."
echo

finn_verktoy
finn_grensesnitt
finn_gateway
skriv_csv_hode
START_MS=$(naa_ms)
finn_wifi_kilde

status INFO "Oppsett" "grensesnitt $GRENSESNITT ($GRENSESNITT_KILDE) · gateway ${GATEWAY:-ukjent} (${GATEWAY_KILDE:-ukjent}) · intervall $INTERVALL s · varighet $( [ "$VARIGHET" -eq 0 ] && echo 'til Ctrl-C' || echo "$VARIGHET s" )"
if [ "$WIFI_KILDE" = "ingen" ]; then
  status SKIP "Wi-Fi-kilde" "ingen funnet på $OS — installer: $WIFI_INSTALL (loggen fortsetter med «ukjent»)"
else
  status INFO "Wi-Fi-kilde" "$WIFI_KILDE_TEKST"
  [ "$HEURISTIKK" -eq 1 ] && status INFO "Heuristikk-modus" "BSSID utilgjengelig — roam anslås fra kanalskifte / RSSI-hopp ≥12 dB"
fi
if [ -z "$PING_BIN" ]; then
  status SKIP "Gateway-ping" "ping mangler — installer: $PING_INSTALL"
elif [ -z "$GATEWAY" ]; then
  status SKIP "Gateway-ping" "gateway ikke funnet ($GATEWAY_KILDE) — gap og pakketap kan ikke måles"
else
  case "$GATEWAY_KILDE" in ANTATT*) status WARN "Gateway" "$GATEWAY_KILDE" ;; esac
fi
melding "Logger til $CSV_FIL"
echo
printf '%-8s  %-16s %-17s %-13s %-9s %-6s %-11s %s\n' "tid" "ssid" "bssid" "kanal/bånd" "rssi" "støy" "tx-rate" "gateway-ping (inet hver 5.)"

hovedlokke
exit 0
