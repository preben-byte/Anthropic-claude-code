#!/usr/bin/env bash
# ============================================================================
# sjekk-klient.sh — nettsjekk: ende-til-ende klientsjekk
#   fiber – brannmur – switch – AP – klient (Marivold Camping / Adm-nett)
#
# Formål : Måler og dokumenterer hele kjeden fra klienten og ut på internett:
#          lenke/Wi-Fi, IP/TCP-IP, DHCP, DNS, gateway/brannmur, fiber/WAN,
#          TCP-ytelse, hastighet, bufferbloat, video, roaming og hygiene.
#          Resultatet skrives som Markdown (til å lime inn i chatten) og JSON.
# Kjøring: bash sjekk-klient.sh
#          bash sjekk-klient.sh --hurtig --rapportmappe ~/nettsjekk
#          bash sjekk-klient.sh --forventet-ned 300 --forventet-opp 300 \
#               --iperf-server 192.168.10.5 --interne-navn nas.lan,skriver.lan
# Krav   : bash 3.2+ (macOS), bash 4/5 (Linux, Android Termux), curl.
#          Valgfritt: ping traceroute dig iperf3 nmap arping iw nmcli jq
#          python3 perl timeout. Manglende verktøy gir [SKIP] med
#          installasjonskommando — skriptet stopper aldri av den grunn.
# Versjon 1.0 — 2026-09-09
# Endrer ingenting — kun lesing og målinger.
# ----------------------------------------------------------------------------
# Innhold (søk etter "### N." for å hoppe dit):
#   ### 1.  Konstanter, standardverdier og globale variabler
#   ### 2.  Hjelpefunksjoner: farger, logging, resultater, timeout, tallregning
#   ### 3.  Hjelpefunksjoner: nettverk (ping, traceroute, DNS, TCP, curl)
#   ### 4.  Parameterhåndtering og hjelpetekst
#   ### 5.  Plattformdeteksjon, verktøy og hjelpeskript
#   ### 6.  Seksjon 0  System og verktøy
#   ### 7.  Seksjon 1  Lenke og Wi-Fi
#   ### 8.  Seksjon 2  IP og TCP/IP
#   ### 9.  Seksjon 3  DHCP
#   ### 10. Seksjon 4  DNS
#   ### 11. Seksjon 5  Gateway og brannmur
#   ### 12. Seksjon 6  Fiber og WAN
#   ### 13. Seksjon 7  TCP-ytelse
#   ### 14. Seksjon 8  Hastighet
#   ### 15. Seksjon 9  Bufferbloat og jitter under last
#   ### 16. Seksjon 10 Video og strømming
#   ### 17. Seksjon 11 Roaming
#   ### 18. Seksjon 12 Hygiene
#   ### 19. Rapportskriving (Markdown og JSON)
#   ### 20. Seksjon 13 Oppsummering og main
# ============================================================================

set -u

# ### 1. Konstanter, standardverdier og globale variabler ---------------------

VERSJON="1.0"
VERKTOY="nettsjekk"
SKRIPTNAVN="sjekk-klient.sh"

TAB=$'\t'
NL=$'\n'
CR=$'\r'
US=$'\x1f'

# Parametre (samme navn og betydning som i PowerShell-varianten)
RAPPORTMAPPE="."
HURTIG=0
FORVENTET_NED=100
FORVENTET_OPP=50
IPERF_SERVER=""
INTERNE_NAVN=""
GATEWAY_PARAM=""
GRENSESNITT_PARAM=""
INGEN_FARGER=0

# Målverter
MAAL_DNS="1.1.1.1 8.8.8.8 9.9.9.9"
MAAL_NORSKE="nrk.no vg.no telenor.no"
MAAL_TCP="www.nrk.no www.vg.no www.google.com www.cloudflare.com www.microsoft.com"
MAAL_VIDEO="www.youtube.com www.netflix.com tv.nrk.no www.twitch.tv"
MAAL_XIQ="redirector.aerohive.com extremecloudiq.com"
DNS_NAVN="nrk.no vg.no cloudflare.com extremecloudiq.com redirector.aerohive.com"
URL_NED="https://speed.cloudflare.com/__down?bytes=100000000"
URL_OPP="https://speed.cloudflare.com/__up"
URL_HLS1="https://test-streams.mux.dev/x36xhzz/x36xhzz.m3u8"
URL_HLS2="https://devstreaming-cdn.apple.com/videos/streaming/examples/img_bipbop_adv_example_hevc/master.m3u8"
URL_TRACE="https://1.1.1.1/cdn-cgi/trace"
URL_TRACE2="https://www.cloudflare.com/cdn-cgi/trace"
URL_IPIFY="https://api.ipify.org"
URL_PORTAL1="http://connectivitycheck.gstatic.com/generate_204"
URL_PORTAL2="http://captive.apple.com/hotspot-detect.html"
URL_DOH="https://cloudflare-dns.com/dns-query?name=nrk.no&type=A"

SEC_NAMES=("0 System og verktøy" "1 Lenke og Wi-Fi" "2 IP og TCP/IP" "3 DHCP" "4 DNS" \
  "5 Gateway og brannmur" "6 Fiber og WAN" "7 TCP-ytelse" "8 Hastighet" \
  "9 Bufferbloat og jitter under last" "10 Video og strømming" "11 Roaming" \
  "12 Hygiene" "13 Oppsummering")

# Tilstand
PLATFORM=""
OS_BESKRIVELSE=""
HOSTNAVN=""
TIDSSTEMPEL=""
STARTTID=0
TMPD=""
TIMEOUT_BIN=""
HAVE_PERL=0
BG_PIDS=""
CLEANED=0
RESULTS=()
CUR_SEC=""
RAWFILE=""
OUT=""
RC=0
N_PASS=0; N_WARN=0; N_FAIL=0; N_SKIP=0; N_INFO=0
RAPPORT_MD=""
RAPPORT_JSON=""
PROXY_AKTIV=0

# Nettverkstilstand (fylles i seksjon 0–3)
IFACE=""; GATEWAY=""; IPV4=""; PREFIX=""; NETMASK=""; MTU=""; MAC=""
N_DEFAULT_ROUTES=0; IPV6_GLOBAL=""; IPV6_DEFAULT=""; IS_WIFI=0
WIRED_SPEED=""
SSID=""; BSSID=""; FREQ=""; BAND=""; CHANNEL=""; WIDTH=""; PHY=""; RSSI=""; NOISE=""
SNR=""; TXRATE=""; RXRATE=""; SECURITY=""; MAC_RANDOM=""
DHCP_SERVER=""; DHCP_LEASE=""; DHCP_DNS=""; DHCP_DOMAIN=""; DHCP_NTP=""; DHCP_ROUTER=""
RESOLVERS=""; SEARCH_DOMAIN=""; RESOLVER_KILDE=""
PUBLIC_IP=""; PMTU_GW=""; PMTU_INET=""
TCP_SENT_FOR=""; TCP_RETRANS_FOR=""
NABOER=""           # fil: bssid<TAB>ssid<TAB>kanal<TAB>rssi<TAB>bånd<TAB>sikkerhet
TRACEFIL_1=""; TRACEFIL_2=""
PING_TX=0; PING_RX=0; PING_LOSS=100; PING_MIN="-"; PING_AVG="-"; PING_MAX="-"; PING_MDEV="-"; PING_TIMES=""
DNSQ_MS=""; DNSQ_STATUS=""; DNSQ_ANS=""
RES_IPS=""; RES_MS=""; RES_STATUS=""

C_RESET=""; C_BOLD=""; C_GREEN=""; C_YELLOW=""; C_RED=""; C_BLUE=""; C_GRAY=""

# ### 2. Hjelpefunksjoner: farger, logging, resultater, timeout, tallregning --

have() { command -v "$1" >/dev/null 2>&1; }

init_farger() {
  if [ "$INGEN_FARGER" -eq 0 ] && [ -t 1 ] && [ "${TERM:-dumb}" != "dumb" ]; then
    C_RESET=$'\033[0m'; C_BOLD=$'\033[1m'; C_GREEN=$'\033[32m'; C_YELLOW=$'\033[33m'
    C_RED=$'\033[31m'; C_BLUE=$'\033[36m'; C_GRAY=$'\033[90m'
  fi
}

# Fjerner kontrolltegn (tab/linjeskift) slik at resultatlinjer alltid er én linje.
san() {
  local s="${1:-}"
  s=${s//[[:cntrl:]]/ }
  printf '%s' "$s"
}

# add_result STATUS SJEKK VERDI TERSKEL DETALJER
add_result() {
  local status="$1" sjekk verdi terskel detaljer farge line
  sjekk=$(san "${2:-}"); verdi=$(san "${3:-}"); terskel=$(san "${4:-}"); detaljer=$(san "${5:-}")
  case "$status" in
    PASS) farge="$C_GREEN"; N_PASS=$((N_PASS + 1)) ;;
    WARN) farge="$C_YELLOW"; N_WARN=$((N_WARN + 1)) ;;
    FAIL) farge="$C_RED"; N_FAIL=$((N_FAIL + 1)) ;;
    SKIP) farge="$C_GRAY"; N_SKIP=$((N_SKIP + 1)) ;;
    *) status="INFO"; farge="$C_BLUE"; N_INFO=$((N_INFO + 1)) ;;
  esac
  line="[$status] $CUR_SEC: $sjekk"
  [ -n "$verdi" ] && line="$line — $verdi"
  [ -n "$terskel" ] && line="$line (terskel $terskel)"
  printf '%s%s%s\n' "$farge" "$line" "$C_RESET"
  RESULTS+=("${status}${TAB}${CUR_SEC}${TAB}${sjekk}${TAB}${verdi}${TAB}${terskel}${TAB}${detaljer}")
}

# Deler en resultatlinje i feltene R_STATUS R_SEK R_SJEKK R_VERDI R_TERSKEL R_DET
split_result() {
  local l="$1"
  R_STATUS=${l%%"$TAB"*}; l=${l#*"$TAB"}
  R_SEK=${l%%"$TAB"*};    l=${l#*"$TAB"}
  R_SJEKK=${l%%"$TAB"*};  l=${l#*"$TAB"}
  R_VERDI=${l%%"$TAB"*};  l=${l#*"$TAB"}
  R_TERSKEL=${l%%"$TAB"*}; l=${l#*"$TAB"}
  R_DET=$l
}

start_sec() {
  CUR_SEC="${SEC_NAMES[$1]}"
  RAWFILE="$TMPD/raw-$1.txt"
  : > "$RAWFILE"
  printf '\n%s== %s ==%s\n' "$C_BOLD" "$CUR_SEC" "$C_RESET"
}

raw_add() {   # raw_add OVERSKRIFT UTDATA
  { printf '$ %s\n%s\n\n' "$1" "${2:-}"; } >> "$RAWFILE"
}
raw_note() {  # fritekst i råutdata
  printf '# %s\n\n' "$1" >> "$RAWFILE"
}

# Portabel timeout: GNU timeout / gtimeout, ellers perl alarm, ellers direkte.
run_timeout() {
  local secs="$1"; shift
  if [ -n "$TIMEOUT_BIN" ]; then
    "$TIMEOUT_BIN" "$secs" "$@"
  elif [ "$HAVE_PERL" -eq 1 ]; then
    perl -e 'alarm shift @ARGV; exec @ARGV or exit 127' "$secs" "$@"
  else
    "$@"
  fi
}

# cap SEKUNDER KOMMANDO... : kjører med timeout, fanger stdout+stderr i OUT,
# returkode i RC, og legger alt i råutdata for gjeldende seksjon.
cap() {
  local t="$1" vis; shift
  OUT=$(run_timeout "$t" "$@" 2>&1 </dev/null)
  RC=$?
  vis="$*"; vis=${vis//$NL/ }
  if [ "$RC" -eq 124 ] || [ "$RC" -eq 142 ]; then
    raw_add "$vis (rc=$RC tidsavbrudd etter ${t}s)" "$OUT"
  else
    raw_add "$vis (rc=$RC)" "$OUT"
  fi
  return "$RC"
}

# Første meningsfulle linje i OUT (feilmelding), uten NETT-måleraden
feil_tekst() {
  printf '%s\n' "$OUT" | grep -v '^NETT ' | grep -v '^$' | head -n 1 | cut -c1-90
}

# Installasjonshint per plattform
inst_hint() {
  local t="$1" p
  case "$PLATFORM" in
    termux)
      case "$t" in
        termux-wifi-connectioninfo|termux-wifi-scaninfo)
          printf 'pkg install termux-api iputils traceroute dnsutils og installer appen Termux:API' ;;
        *) printf 'pkg install termux-api iputils traceroute dnsutils' ;;
      esac ;;
    darwin)
      case "$t" in
        timeout) printf 'brew install coreutils' ;;
        python3) printf 'brew install python' ;;
        *) printf 'brew install %s' "$t" ;;
      esac ;;
    *)
      case "$t" in
        ping) p=iputils-ping ;; tracepath) p=iputils-tracepath ;;
        dig|nslookup) p=dnsutils ;; arping) p=iputils-arping ;;
        nmcli) p=network-manager ;; ip|nstat) p=iproute2 ;; mtr) p=mtr-tiny ;;
        avahi-browse) p=avahi-utils ;; *) p="$t" ;;
      esac
      printf 'sudo apt install %s (Debian/Ubuntu; ellers dnf/pacman)' "$p" ;;
  esac
}

# Pakkenavn (uten kommando) for en liste verktøy -> samlet installasjonskommando
inst_samlet() {
  local t p liste=""
  for t in "$@"; do
    case "$PLATFORM" in
      darwin) case "$t" in timeout) p=coreutils ;; python3) p=python ;; ping|traceroute|dig|nslookup|ip|nmcli|iw|ethtool|tracepath|nstat) p="" ;; *) p="$t" ;; esac ;;
      *) case "$t" in ping) p=iputils-ping ;; tracepath) p=iputils-tracepath ;; dig|nslookup) p=dnsutils ;; arping) p=iputils-arping ;;
           nmcli) p=network-manager ;; ip|nstat) p=iproute2 ;; mtr) p=mtr-tiny ;; speedtest) p="" ;; *) p="$t" ;; esac ;;
    esac
    [ -n "$p" ] && case " $liste " in *" $p "*) ;; *) liste="$liste $p" ;; esac
  done
  case "$PLATFORM" in
    termux) printf 'pkg install termux-api iputils traceroute dnsutils' ;;
    darwin) printf 'brew install%s (ping/traceroute/dig er innebygd i macOS)' "$liste" ;;
    *) printf 'sudo apt install%s (Debian/Ubuntu; ellers dnf/pacman)' "$liste" ;;
  esac
}

# skip_tool SJEKK VERKTØY [DETALJER]
skip_tool() {
  add_result SKIP "$1" "mangler '$2' — installer: $(inst_hint "$2")" "" "${3:-}"
}

# Tallregning via awk (flyttall). Alle tar mellomromsseparerte lister.
tall_liste() { printf '%s' "${1:-}" | tr ' ,' '\n\n' | grep -E '^-?[0-9]+(\.[0-9]+)?$'; }
median() {
  tall_liste "${1:-}" | sort -n | awk '{a[NR]=$1} END{ if (NR==0) print "-"; else if (NR%2) printf "%.1f\n", a[(NR+1)/2]; else printf "%.1f\n", (a[NR/2]+a[NR/2+1])/2 }'
}
mean() { tall_liste "${1:-}" | awk '{s+=$1; n++} END{ if (n==0) print "-"; else printf "%.1f\n", s/n }'; }
maks() { tall_liste "${1:-}" | sort -n | tail -n 1 | awk '{ if (NF) printf "%.1f\n", $1; else print "-" }'; }
minst() { tall_liste "${1:-}" | sort -n | head -n 1 | awk '{ if (NF) printf "%.1f\n", $1; else print "-" }'; }
antall() { tall_liste "${1:-}" | awk 'END{print NR}'; }
er_tall() { printf '%s' "${1:-}" | grep -qE '^-?[0-9]+(\.[0-9]+)?$'; }
fmt1() { awk -v v="${1:-0}" 'BEGIN{printf "%.1f", v}'; }
fmt0() { awk -v v="${1:-0}" 'BEGIN{printf "%.0f", v}'; }
# gradering: verdi mot terskler. grade_le: v<=p PASS, v<=w WARN, ellers FAIL
grade_le() { awk -v v="$1" -v p="$2" -v w="$3" 'BEGIN{ if (v<=p) print "PASS"; else if (v<=w) print "WARN"; else print "FAIL" }'; }
grade_lt() { awk -v v="$1" -v p="$2" -v w="$3" 'BEGIN{ if (v<p) print "PASS"; else if (v<w) print "WARN"; else print "FAIL" }'; }
grade_ge() { awk -v v="$1" -v p="$2" -v w="$3" 'BEGIN{ if (v>=p) print "PASS"; else if (v>=w) print "WARN"; else print "FAIL" }'; }
# sammenligninger: returnerer 0 (sant) / 1 (usant)
lt() { awk -v a="$1" -v b="$2" 'BEGIN{exit !(a<b)}'; }
gt() { awk -v a="$1" -v b="$2" 'BEGIN{exit !(a>b)}'; }
ge() { awk -v a="$1" -v b="$2" 'BEGIN{exit !(a>=b)}'; }

freq_to_chan() {
  awk -v f="${1:-0}" 'BEGIN{ if (f==2484) c=14; else if (f>=2412 && f<=2472) c=(f-2407)/5; else if (f==5935) c=2; else if (f>=5955 && f<=7115) c=(f-5950)/5; else if (f>=5000 && f<=5900) c=(f-5000)/5; else c="?"; print c }'
}
freq_to_band() {
  awk -v f="${1:-0}" 'BEGIN{ if (f>=2400 && f<2500) b="2.4 GHz"; else if (f>=5925 && f<=7125) b="6 GHz"; else if (f>=5000 && f<5925) b="5 GHz"; else b="ukjent"; print b }'
}
chan_to_band() {
  awk -v c="${1:-0}" 'BEGIN{ if (c>=1 && c<=14) print "2.4 GHz"; else if (c>=32 && c<=177) print "5 GHz"; else print "ukjent" }'
}
er_cgnat() { # 100.64.0.0/10
  awk -v ip="${1:-}" 'BEGIN{ n=split(ip,o,"."); if (n==4 && o[1]==100 && o[2]>=64 && o[2]<=127) exit 0; exit 1 }'
}
er_privat() {
  awk -v ip="${1:-}" 'BEGIN{ n=split(ip,o,"."); if (n!=4) exit 1; if (o[1]==10) exit 0; if (o[1]==192 && o[2]==168) exit 0; if (o[1]==172 && o[2]>=16 && o[2]<=31) exit 0; exit 1 }'
}
mask_to_prefix() { # 255.255.255.0 eller 0xffffff00 -> 24
  local m="${1:-}" n bits=0
  case "$m" in
    0x*) n=$((m)) ;;
    *.*.*.*) n=$(awk -v m="$m" 'BEGIN{ split(m,o,"."); print o[1]*16777216+o[2]*65536+o[3]*256+o[4] }') ;;
    *) printf ''; return ;;
  esac
  while [ "$n" -gt 0 ]; do bits=$((bits + (n & 1))); n=$((n >> 1)); done
  printf '%s' "$bits"
}
hex_to_ip() { # 010200C0 (little endian) -> 192.0.2.1
  local h="$1"
  [ ${#h} -eq 8 ] || { printf ''; return; }
  printf '%d.%d.%d.%d' "0x${h:6:2}" "0x${h:4:2}" "0x${h:2:2}" "0x${h:0:2}"
}
hexmask_to_prefix() { # 00FFFFFF -> 24
  local h="$1" n bits=0
  n=$((0x$h)); while [ "$n" -gt 0 ]; do bits=$((bits + (n & 1))); n=$((n >> 1)); done
  printf '%s' "$bits"
}
# Flat JSON: henter verdien til en nøkkel (tekst eller tall), best effort uten jq.
jget() {
  printf '%s' "${1:-}" | tr -d "$NL$CR" | sed -n 's/.*"'"$2"'": *"\{0,1\}\([^,"}]*\)"\{0,1\}.*/\1/p' | head -n 1
}
gyldig_navn() { printf '%s' "${1:-}" | grep -qE '^[A-Za-z0-9.:_-]+$'; }

# ### 3. Hjelpefunksjoner: nettverk (ping, traceroute, DNS, TCP, curl) --------

# Tolker ping-utdata i OUT (macOS/Linux/Termux) -> PING_*-variabler
parse_ping() {
  local stats
  stats=$(printf '%s\n' "$OUT" | awk '
    /packets transmitted/ { tx=$1; rx=$4; for (i=1;i<=NF;i++) if ($i ~ /%/) { loss=$i; gsub(/[%,]/,"",loss) } }
    /min\/avg\/max/ { n=split($0,p,"= "); split(p[n],q," "); split(q[1],r,"/"); mn=r[1]; av=r[2]; mx=r[3]; md=r[4] }
    END { if (tx=="") tx=0; if (rx=="") rx=0; if (loss=="" || tx==0) loss=100;
          printf "%s %s %s %s %s %s %s\n", tx, rx, loss, (mn==""?"-":mn), (av==""?"-":av), (mx==""?"-":mx), (md==""?"-":md) }')
  read -r PING_TX PING_RX PING_LOSS PING_MIN PING_AVG PING_MAX PING_MDEV <<< "$stats"
  er_tall "$PING_TX" || PING_TX=0
  er_tall "$PING_RX" || PING_RX=0
  er_tall "$PING_LOSS" || PING_LOSS=100
  PING_TIMES=$(printf '%s\n' "$OUT" | awk '/time=/ { s=$0; sub(/.*time=/,"",s); sub(/ .*/,"",s); printf "%s ", s }')
}

# do_ping VERT ANTALL INTERVALL [DF-STØRRELSE] -> 0 hvis minst ett svar
do_ping() {
  local host="$1" cnt="$2" intv="${3:-}" df="${4:-}" dl t
  local -a a
  have ping || { OUT="ping mangler"; RC=127; PING_TX=0; PING_RX=0; PING_LOSS=100; PING_TIMES=""; PING_AVG="-"; PING_MDEV="-"; return 1; }
  dl=$(awk -v c="$cnt" -v i="${intv:-1}" 'BEGIN{ printf "%d", c*i+4 }')
  t=$((dl + 6))
  a=(ping -n -c "$cnt")
  case "$PLATFORM" in
    darwin) a+=(-W 1000 -t "$dl"); [ -n "$df" ] && a+=(-D -s "$df") ;;
    *)      a+=(-W 1 -w "$dl");    [ -n "$df" ] && a+=(-M "do" -s "$df") ;;
  esac
  [ -n "$intv" ] && a+=(-i "$intv")
  a+=("$host")
  cap "$t" "${a[@]}"
  if [ "$RC" -ne 0 ] && [ -n "$intv" ] && printf '%s' "$OUT" | grep -qiE 'not permitted|minimal interval|too short|interval'; then
    raw_note "ping avviste -i $intv for vanlig bruker — prøver standardintervall"
    dl=$((cnt + 4)); t=$((dl + 6))
    a=(ping -n -c "$cnt")
    case "$PLATFORM" in
      darwin) a+=(-W 1000 -t "$dl"); [ -n "$df" ] && a+=(-D -s "$df") ;;
      *)      a+=(-W 1 -w "$dl");    [ -n "$df" ] && a+=(-M "do" -s "$df") ;;
    esac
    a+=("$host")
    cap "$t" "${a[@]}"
  fi
  parse_ping
  [ "$PING_RX" -gt 0 ]
}

# Bakgrunns-ping (for samtidige målinger): do_ping_bg VERT ANTALL INTERVALL FIL -> PID i BG_LAST_PID
BG_LAST_PID=""
do_ping_bg() {
  local host="$1" cnt="$2" intv="$3" fil="$4" dl
  local -a a
  dl=$(awk -v c="$cnt" -v i="$intv" 'BEGIN{ printf "%d", c*i+4 }')
  a=(ping -n -c "$cnt" -i "$intv")
  case "$PLATFORM" in
    darwin) a+=(-W 1000 -t "$dl") ;;
    *)      a+=(-W 1 -w "$dl") ;;
  esac
  a+=("$host")
  run_timeout $((dl + 6)) "${a[@]}" > "$fil" 2>&1 </dev/null &
  BG_LAST_PID=$!
  BG_PIDS="$BG_PIDS $BG_LAST_PID"
}

# Tolker traceroute/tracepath-utdata i OUT -> linjer "hopp ip rtt" i fil $1
parse_trace() {
  printf '%s\n' "$OUT" | awk '
    /^ *[0-9]+:? / {
      hop=$1; sub(/:$/,"",hop); ip="*"; rtt="*"
      for (i=2;i<=NF;i++) {
        if ($i ~ /^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$/ && ip=="*") ip=$i
        else if ($i ~ /^[0-9]+(\.[0-9]+)?ms$/ && rtt=="*") { rtt=$i; sub(/ms$/,"",rtt) }
        else if ($i ~ /^[0-9]+(\.[0-9]+)?$/ && $(i+1)=="ms" && rtt=="*") rtt=$i
      }
      print hop, ip, rtt
    }' > "$1"
}

# do_trace MÅL FIL : traceroute (ellers tracepath) med per-hopp-RTT
do_trace() {
  local maal="$1" fil="$2"
  : > "$fil"
  if have traceroute; then
    cap 60 traceroute -n -m 15 -w 2 -q 1 "$maal"
  elif have tracepath; then
    cap 60 tracepath -n -m 15 "$maal"
  else
    return 2
  fi
  parse_trace "$fil"
  [ -s "$fil" ]
}
trace_hop() { # trace_hop FIL HOPP -> "ip rtt"
  awk -v h="$2" '$1==h { print $2, $3; exit }' "$1"
}

# DNS-oppslag. dns_lookup RESOLVER NAVN [TYPE] -> DNSQ_MS DNSQ_STATUS DNSQ_ANS
# dig når det finnes (kan spørre en bestemt resolver), ellers python3 (systemresolver).
dns_lookup() {
  local res="${1:-}" navn="$2" type="${3:-A}" linje
  DNSQ_MS=""; DNSQ_STATUS="SKIP"; DNSQ_ANS=""
  if have dig; then
    if [ -n "$res" ]; then
      cap 8 dig "@$res" "$navn" "$type" +time=2 +tries=1
    else
      cap 8 dig "$navn" "$type" +time=2 +tries=1
    fi
    DNSQ_MS=$(printf '%s\n' "$OUT" | awk '/Query time:/ { print $4; exit }')
    DNSQ_STATUS=$(printf '%s\n' "$OUT" | awk '/->>HEADER<<-/ { s=$0; sub(/.*status: /,"",s); sub(/,.*/,"",s); print s; exit }')
    DNSQ_ANS=$(printf '%s\n' "$OUT" | awk -v t="$type" '$0 !~ /^;/ && $3=="IN" && $4==t { printf "%s ", $5 }')
    if [ -z "$DNSQ_STATUS" ]; then
      if printf '%s' "$OUT" | grep -qi 'timed out\|no servers could be reached'; then DNSQ_STATUS="TIMEOUT"; else DNSQ_STATUS="FEIL"; fi
    fi
    return 0
  fi
  if have python3; then
    cap 15 python3 "$TMPD/dns.py" "$navn"
    linje=$(printf '%s\n' "$OUT" | grep "^${navn}${TAB}" | head -n 1)
    if [ -n "$linje" ]; then
      linje=${linje#*"$TAB"}; DNSQ_MS=${linje%%"$TAB"*}; linje=${linje#*"$TAB"}
      DNSQ_STATUS=${linje%%"$TAB"*}; DNSQ_ANS=${linje#*"$TAB"}
      [ "$DNSQ_ANS" = "-" ] && DNSQ_ANS=""
    else
      DNSQ_STATUS="TIMEOUT"
    fi
    return 0
  fi
  return 2
}

# resolve_name NAVN -> RES_IPS RES_MS RES_STATUS (systemresolver; curl som siste utvei)
resolve_name() {
  local navn="$1"
  RES_IPS=""; RES_MS=""; RES_STATUS="SKIP"
  if dns_lookup "" "$navn" A; then
    RES_IPS="$DNSQ_ANS"; RES_MS="$DNSQ_MS"; RES_STATUS="$DNSQ_STATUS"
    return 0
  fi
  if have getent; then
    cap 8 getent ahostsv4 "$navn"
    RES_IPS=$(printf '%s\n' "$OUT" | awk '{print $1}' | sort -u | tr "$NL" ' ')
    if [ -n "$RES_IPS" ]; then RES_STATUS="NOERROR"; else RES_STATUS="NXDOMAIN"; fi
    return 0
  fi
  cap 10 curl -sS -o /dev/null --max-time 8 -w '%{remote_ip}' "https://$navn/"
  RES_IPS=$(printf '%s\n' "$OUT" | tail -n 1)
  if printf '%s' "$RES_IPS" | grep -qE '^[0-9a-fA-F.:]+$'; then RES_STATUS="NOERROR"; else RES_IPS=""; RES_STATUS="FEIL"; fi
  return 0
}

# tcp_port_open VERT PORT -> 0 åpen, 1 lukket/filtrert
tcp_port_open() {
  local host="$1" port="$2"
  if have nc; then
    cap 6 nc -z -w 2 "$host" "$port"
    [ "$RC" -eq 0 ] && return 0
    printf '%s' "$OUT" | grep -qiE 'usage|invalid option|unrecognized|unknown option' || return 1
  fi
  cap 6 bash -c 'exec 3<>"/dev/tcp/$0/$1"; exec 3>&-' "$host" "$port"
  [ "$RC" -eq 0 ]
}

# curl_tid URL -> CURL_CODE CURL_CONNECT_MS CURL_TLS_MS (TLS = appconnect - connect)
CURL_CODE=""; CURL_CONNECT_MS=""; CURL_TLS_MS=""
curl_tid() {
  local url="$1" l
  cap 15 curl -sS -o /dev/null --max-time 10 -w "${NL}NETT %{http_code} %{time_connect} %{time_appconnect}" "$url"
  l=$(printf '%s\n' "$OUT" | awk '$1=="NETT" { print $2, $3, $4 }' | tail -n 1)
  CURL_CODE=""; CURL_CONNECT_MS=""; CURL_TLS_MS=""
  if [ -n "$l" ]; then
    CURL_CODE=${l%% *}
    CURL_CONNECT_MS=$(awk -v l="$l" 'BEGIN{ split(l,a," "); printf "%.0f", a[2]*1000 }')
    CURL_TLS_MS=$(awk -v l="$l" 'BEGIN{ split(l,a," "); if (a[3]>0) printf "%.0f", (a[3]-a[2])*1000; else print "-" }')
  fi
  [ -n "$CURL_CODE" ] && [ "$CURL_CODE" != "000" ]
}

# HTTP Date-header -> epoch (GNU date på Linux/Termux, date -j på macOS)
http_date_to_epoch() {
  local s="$1"
  s=${s% GMT}; s=${s% UTC}
  if [ "$PLATFORM" = "darwin" ]; then
    TZ=UTC0 LC_ALL=C date -j -f '%a, %d %b %Y %H:%M:%S' "$s" +%s 2>/dev/null
  else
    LC_ALL=C date -u -d "$s" +%s 2>/dev/null
  fi
}

# ### 4. Parameterhåndtering og hjelpetekst -----------------------------------

hjelp() {
  cat <<HJELP
$SKRIPTNAVN v$VERSJON — nettsjekk: ende-til-ende klientsjekk (fiber – brannmur – switch – AP – klient)
Endrer ingenting — kun lesing og målinger. Krever aldri sudo/admin.

Bruk: bash $SKRIPTNAVN [valg]

Valg:
  --rapportmappe DIR     Mappe for rapportfiler (standard: gjeldende mappe)
  --hurtig               Hopper over seksjon 8 (hastighet), 9 (bufferbloat) og 10 (video)
  --forventet-ned N      Forventet nedlasting i Mbit/s (standard 100)
  --forventet-opp N      Forventet opplasting i Mbit/s (standard 50)
  --iperf-server IP      iperf3-server på LAN for lokal hastighetsmåling (valgfritt)
  --interne-navn a,b,c   Interne DNS-navn som skal kunne slås opp (kommaseparert)
  --gateway IP           Overstyr gateway-adresse (ellers hentes den fra rutetabellen)
  --grensesnitt IF       Overstyr nettverksgrensesnitt (f.eks. en0, wlan0)
  --ingen-farger         Ingen farger på konsollen
  --hjelp                Denne hjelpeteksten

Seksjoner: 0 System og verktøy | 1 Lenke og Wi-Fi | 2 IP og TCP/IP | 3 DHCP | 4 DNS |
  5 Gateway og brannmur | 6 Fiber og WAN | 7 TCP-ytelse | 8 Hastighet |
  9 Bufferbloat og jitter under last | 10 Video og strømming | 11 Roaming | 12 Hygiene | 13 Oppsummering

Rapport: nettsjekk-rapport-<host>-<YYYYMMDD-HHMMSS>.md og .json i rapportmappen.
Lim inn innholdet i .md-filen i chatten for analyse.
HJELP
}

bruksfeil() {
  printf 'Feil: %s\n\n' "$1" >&2
  printf 'Kjør «bash %s --hjelp» for hjelp.\n' "$SKRIPTNAVN" >&2
  exit 2
}

parse_args() {
  local navn
  while [ $# -gt 0 ]; do
    case "$1" in
      --rapportmappe) [ $# -ge 2 ] || bruksfeil "--rapportmappe trenger en verdi"; RAPPORTMAPPE="$2"; shift 2 ;;
      --hurtig) HURTIG=1; shift ;;
      --forventet-ned) [ $# -ge 2 ] || bruksfeil "--forventet-ned trenger en verdi"; FORVENTET_NED="$2"; shift 2 ;;
      --forventet-opp) [ $# -ge 2 ] || bruksfeil "--forventet-opp trenger en verdi"; FORVENTET_OPP="$2"; shift 2 ;;
      --iperf-server) [ $# -ge 2 ] || bruksfeil "--iperf-server trenger en verdi"; IPERF_SERVER="$2"; shift 2 ;;
      --interne-navn) [ $# -ge 2 ] || bruksfeil "--interne-navn trenger en verdi"; INTERNE_NAVN="$2"; shift 2 ;;
      --gateway) [ $# -ge 2 ] || bruksfeil "--gateway trenger en verdi"; GATEWAY_PARAM="$2"; shift 2 ;;
      --grensesnitt) [ $# -ge 2 ] || bruksfeil "--grensesnitt trenger en verdi"; GRENSESNITT_PARAM="$2"; shift 2 ;;
      --ingen-farger) INGEN_FARGER=1; shift ;;
      --hjelp|-h|--help) hjelp; exit 0 ;;
      *) bruksfeil "ukjent valg: $1" ;;
    esac
  done
  printf '%s' "$FORVENTET_NED" | grep -qE '^[0-9]+(\.[0-9]+)?$' && gt "$FORVENTET_NED" 0 || bruksfeil "--forventet-ned må være et positivt tall (Mbit/s)"
  printf '%s' "$FORVENTET_OPP" | grep -qE '^[0-9]+(\.[0-9]+)?$' && gt "$FORVENTET_OPP" 0 || bruksfeil "--forventet-opp må være et positivt tall (Mbit/s)"
  [ -z "$IPERF_SERVER" ] || gyldig_navn "$IPERF_SERVER" || bruksfeil "--iperf-server inneholder ugyldige tegn (tillatt: A-Z a-z 0-9 . : _ -)"
  [ -z "$GATEWAY_PARAM" ] || gyldig_navn "$GATEWAY_PARAM" || bruksfeil "--gateway inneholder ugyldige tegn"
  [ -z "$GRENSESNITT_PARAM" ] || printf '%s' "$GRENSESNITT_PARAM" | grep -qE '^[A-Za-z0-9._-]+$' || bruksfeil "--grensesnitt inneholder ugyldige tegn"
  if [ -n "$INTERNE_NAVN" ]; then
    for navn in $(printf '%s' "$INTERNE_NAVN" | tr ',' ' '); do
      gyldig_navn "$navn" || bruksfeil "--interne-navn: «$navn» inneholder ugyldige tegn"
    done
  fi
  if [ ! -d "$RAPPORTMAPPE" ]; then
    mkdir -p "$RAPPORTMAPPE" 2>/dev/null || bruksfeil "kan ikke opprette rapportmappen «$RAPPORTMAPPE»"
  fi
  [ -w "$RAPPORTMAPPE" ] || bruksfeil "rapportmappen «$RAPPORTMAPPE» er ikke skrivbar"
}

# ### 5. Plattformdeteksjon, verktøy og hjelpeskript --------------------------

cleanup() {
  [ "$CLEANED" -eq 1 ] && return 0
  CLEANED=1
  local p
  for p in $BG_PIDS; do
    kill "$p" 2>/dev/null
  done
  [ -n "$TMPD" ] && [ -d "$TMPD" ] && rm -rf "$TMPD"
  return 0
}

detect_platform() {
  local u
  u=$(uname -s 2>/dev/null || printf 'ukjent')
  case "${PREFIX:-}" in *com.termux*) PLATFORM="termux" ;; esac
  [ -z "$PLATFORM" ] && have termux-wifi-connectioninfo && PLATFORM="termux"
  if [ -z "$PLATFORM" ]; then
    case "$u" in
      Darwin) PLATFORM="darwin" ;;
      Linux) PLATFORM="linux" ;;
      *) PLATFORM="linux" ;;
    esac
  fi
  case "$PLATFORM" in
    darwin) OS_BESKRIVELSE="macOS $(sw_vers -productVersion 2>/dev/null || printf '?') ($(uname -m 2>/dev/null))" ;;
    termux) OS_BESKRIVELSE="Android $(getprop ro.build.version.release 2>/dev/null || printf '?') / Termux ($(uname -m 2>/dev/null), kjerne $(uname -r 2>/dev/null))" ;;
    *)
      if [ -r /etc/os-release ]; then
        OS_BESKRIVELSE="$(sed -n 's/^PRETTY_NAME="\{0,1\}\([^"]*\)"\{0,1\}/\1/p' /etc/os-release | head -n 1) (kjerne $(uname -r 2>/dev/null), $(uname -m 2>/dev/null))"
      else
        OS_BESKRIVELSE="Linux $(uname -r 2>/dev/null) ($(uname -m 2>/dev/null))"
      fi ;;
  esac
}

init() {
  local base
  STARTTID=$(date +%s)
  init_farger
  detect_platform
  if have timeout; then TIMEOUT_BIN="timeout"; elif have gtimeout; then TIMEOUT_BIN="gtimeout"; fi
  have perl && HAVE_PERL=1
  base="${TMPDIR:-/tmp}"
  TMPD=$(mktemp -d 2>/dev/null) || TMPD="$base/nettsjekk.$$"
  mkdir -p "$TMPD" || { printf 'Feil: kan ikke opprette midlertidig mappe\n' >&2; exit 2; }
  NABOER="$TMPD/naboer.tsv"; : > "$NABOER"
  TRACEFIL_1="$TMPD/trace-1.txt"; TRACEFIL_2="$TMPD/trace-2.txt"
  HOSTNAVN=$(uname -n 2>/dev/null || hostname 2>/dev/null || printf 'ukjent')
  HOSTNAVN=${HOSTNAVN%%.*}
  HOSTNAVN=$(printf '%s' "$HOSTNAVN" | tr -c 'A-Za-z0-9._-' '_')
  [ -n "$HOSTNAVN" ] || HOSTNAVN="ukjent"
  TIDSSTEMPEL=$(date +%Y%m%d-%H%M%S)
  RAPPORT_MD="$RAPPORTMAPPE/nettsjekk-rapport-$HOSTNAVN-$TIDSSTEMPEL.md"
  RAPPORT_JSON="$RAPPORTMAPPE/nettsjekk-rapport-$HOSTNAVN-$TIDSSTEMPEL.json"
  [ -n "${http_proxy:-}${https_proxy:-}${HTTP_PROXY:-}${HTTPS_PROXY:-}${ALL_PROXY:-}${all_proxy:-}" ] && PROXY_AKTIV=1
  skriv_hjelpeskript
  printf '%s%s v%s — %s — %s%s\n' "$C_BOLD" "$SKRIPTNAVN" "$VERSJON" "$HOSTNAVN" "$(date '+%Y-%m-%d %H:%M:%S')" "$C_RESET"
  printf 'Endrer ingenting — kun lesing og målinger. Plattform: %s. Hurtigmodus: %s\n' "$PLATFORM" "$([ "$HURTIG" -eq 1 ] && printf 'ja' || printf 'nei')"
}

# Små hjelpeskript (python3) skrives til tmp-mappen ved oppstart.
skriv_hjelpeskript() {
  cat > "$TMPD/dns.py" <<'PY'
import socket, sys, time
for navn in sys.argv[1:]:
    t0 = time.time()
    try:
        r = socket.getaddrinfo(navn, None, socket.AF_INET, socket.SOCK_STREAM)
        ms = (time.time() - t0) * 1000
        ips = sorted(set(x[4][0] for x in r))
        print("%s\t%.0f\tNOERROR\t%s" % (navn, ms, " ".join(ips)), flush=True)
    except socket.gaierror as e:
        ms = (time.time() - t0) * 1000
        if e.errno == socket.EAI_NONAME or e.errno == getattr(socket, "EAI_NODATA", -5):
            st = "NXDOMAIN"
        elif e.errno == socket.EAI_AGAIN:
            st = "TIMEOUT"
        else:
            st = "FEIL"
        print("%s\t%.0f\t%s\t-" % (navn, ms, st), flush=True)
    except Exception:
        print("%s\t0\tFEIL\t-" % navn, flush=True)
PY
  cat > "$TMPD/json.py" <<'PY'
import json, sys
tsv, meta_tsv, ut = sys.argv[1], sys.argv[2], sys.argv[3]
meta = {"verktoy": "nettsjekk", "versjon": "1.0", "host": "", "os": "", "tid": "", "parametre": {}}
for line in open(meta_tsv, encoding="utf-8", errors="replace"):
    line = line.rstrip("\n")
    if "\t" not in line:
        continue
    k, v = line.split("\t", 1)
    if k.startswith("param."):
        meta["parametre"][k[6:]] = v
    else:
        meta[k] = v
res = []
tell = {"pass": 0, "warn": 0, "fail": 0, "skip": 0, "info": 0}
for line in open(tsv, encoding="utf-8", errors="replace"):
    f = line.rstrip("\n").split("\t")
    while len(f) < 6:
        f.append("")
    res.append({"seksjon": f[1], "sjekk": f[2], "status": f[0], "verdi": f[3], "terskel": f[4], "detaljer": f[5]})
    n = f[0].lower()
    tell[n] = tell.get(n, 0) + 1
with open(ut, "w", encoding="utf-8") as fh:
    json.dump({"meta": meta, "resultater": res, "oppsummering": tell}, fh, ensure_ascii=False, indent=1)
    fh.write("\n")
PY
  cat > "$TMPD/iperf.py" <<'PY'
import json, sys
try:
    d = json.load(sys.stdin)
    e = d.get("end", {})
    s = e.get("sum_received") or e.get("sum") or {}
    m = e.get("sum_sent") or {}
    print("%s %s" % (s.get("bits_per_second", ""), m.get("bits_per_second", "")))
except Exception as ex:
    print("FEIL %s" % ex)
PY
}

# ### 6. Seksjon 0  System og verktøy -----------------------------------------

# Finner grensesnitt, gateway, IPv4, prefiks, MTU, MAC per plattform.
finn_nett() {
  local l gwhex iface_r maskhex
  N_DEFAULT_ROUTES=0
  case "$PLATFORM" in
    darwin)
      cap 10 route -n get default
      [ -z "$IFACE" ] && IFACE=$(printf '%s\n' "$OUT" | awk '$1=="interface:" {print $2; exit}')
      [ -z "$GATEWAY" ] && GATEWAY=$(printf '%s\n' "$OUT" | awk '$1=="gateway:" {print $2; exit}')
      cap 10 netstat -rn -f inet
      N_DEFAULT_ROUTES=$(printf '%s\n' "$OUT" | awk '$1=="default" {n++} END{print n+0}')
      if [ -n "$IFACE" ]; then
        cap 10 ifconfig "$IFACE"
        [ -z "$IPV4" ] && IPV4=$(printf '%s\n' "$OUT" | awk '$1=="inet" {print $2; exit}')
        NETMASK=$(printf '%s\n' "$OUT" | awk '$1=="inet" { for(i=1;i<=NF;i++) if ($i=="netmask") print $(i+1); exit }')
        [ -n "$NETMASK" ] && PREFIX=$(mask_to_prefix "$NETMASK")
        MTU=$(printf '%s\n' "$OUT" | awk '{ for(i=1;i<=NF;i++) if ($i=="mtu") { print $(i+1); exit } }')
        MAC=$(printf '%s\n' "$OUT" | awk '$1=="ether" {print $2; exit}')
        IPV6_GLOBAL=$(printf '%s\n' "$OUT" | awk '$1=="inet6" && $2 !~ /^fe80/ { printf "%s ", $2 }')
        WIRED_SPEED=$(printf '%s\n' "$OUT" | awk '$1=="media:" { $1=""; sub(/^ /,""); print; exit }')
      fi
      cap 10 route -n get -inet6 default
      [ "$RC" -eq 0 ] && IPV6_DEFAULT=$(printf '%s\n' "$OUT" | awk '$1=="gateway:" {print $2; exit}')
      ;;
    *)
      if have ip; then
        cap 10 ip route show default
        N_DEFAULT_ROUTES=$(printf '%s\n' "$OUT" | grep -c '^default')
        l=$(printf '%s\n' "$OUT" | grep '^default' | head -n 1)
        if [ -z "$l" ]; then
          cap 10 ip route get 1.1.1.1
          l=$(printf '%s\n' "$OUT" | head -n 1)
          if printf '%s' "$l" | grep -q ' via '; then N_DEFAULT_ROUTES=1; fi
        fi
        [ -z "$GATEWAY" ] && GATEWAY=$(printf '%s\n' "$l" | awk '{ for(i=1;i<=NF;i++) if ($i=="via") { print $(i+1); exit } }')
        [ -z "$IFACE" ] && IFACE=$(printf '%s\n' "$l" | awk '{ for(i=1;i<=NF;i++) if ($i=="dev") { print $(i+1); exit } }')
        if [ -n "$IFACE" ]; then
          cap 10 ip -o -4 addr show dev "$IFACE"
          l=$(printf '%s\n' "$OUT" | awk '$3=="inet" {print $4; exit}')
          [ -z "$IPV4" ] && IPV4=${l%%/*}
          case "$l" in */*) PREFIX=${l##*/} ;; esac
          cap 10 ip -o link show dev "$IFACE"
          MTU=$(printf '%s\n' "$OUT" | awk '{ for(i=1;i<=NF;i++) if ($i=="mtu") { print $(i+1); exit } }')
          MAC=$(printf '%s\n' "$OUT" | awk '{ for(i=1;i<=NF;i++) if ($i=="link/ether") { print $(i+1); exit } }')
          cap 10 ip -6 addr show dev "$IFACE" scope global
          IPV6_GLOBAL=$(printf '%s\n' "$OUT" | awk '$1=="inet6" { printf "%s ", $2 }')
        fi
        cap 10 ip -6 route show default
        IPV6_DEFAULT=$(printf '%s\n' "$OUT" | awk '$1=="default" { for(i=1;i<=NF;i++) if ($i=="via") { print $(i+1); exit } }')
      elif [ -r /proc/net/route ]; then
        raw_note "ip mangler — leser /proc/net/route"
        cap 5 cat /proc/net/route
        N_DEFAULT_ROUTES=$(printf '%s\n' "$OUT" | awk '$2=="00000000" {n++} END{print n+0}')
        l=$(printf '%s\n' "$OUT" | awk '$2=="00000000" {print $1, $3; exit}')
        iface_r=${l%% *}; gwhex=${l##* }
        [ -z "$IFACE" ] && IFACE="$iface_r"
        [ -z "$GATEWAY" ] && [ -n "$gwhex" ] && GATEWAY=$(hex_to_ip "$gwhex")
        maskhex=$(printf '%s\n' "$OUT" | awk -v i="$IFACE" '$1==i && $3=="00000000" && $2!="00000000" {print $8; exit}')
        [ -n "$maskhex" ] && PREFIX=$(hexmask_to_prefix "$maskhex")
      fi
      if [ -z "$IPV4" ] && have ifconfig && [ -n "$IFACE" ]; then
        cap 10 ifconfig "$IFACE"
        IPV4=$(printf '%s\n' "$OUT" | awk '$1=="inet" { s=$2; sub(/^addr:/,"",s); print s; exit }')
        NETMASK=$(printf '%s\n' "$OUT" | awk '$1=="inet" { for(i=1;i<=NF;i++) if ($i=="netmask" || $i ~ /^Mask:/) { s=$(i+1); if ($i ~ /^Mask:/) { s=$i; sub(/^Mask:/,"",s) } print s; exit } }')
        [ -n "$NETMASK" ] && [ -z "$PREFIX" ] && PREFIX=$(mask_to_prefix "$NETMASK")
      fi
      if [ -z "$IPV4" ] && have hostname; then
        cap 5 hostname -I
        IPV4=$(printf '%s\n' "$OUT" | awk '{ for(i=1;i<=NF;i++) if ($i ~ /^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$/) { print $i; exit } }')
      fi
      if [ -n "$IFACE" ]; then
        [ -z "$MTU" ] && [ -r "/sys/class/net/$IFACE/mtu" ] && MTU=$(cat "/sys/class/net/$IFACE/mtu" 2>/dev/null)
        [ -z "$MAC" ] && [ -r "/sys/class/net/$IFACE/address" ] && MAC=$(cat "/sys/class/net/$IFACE/address" 2>/dev/null)
      fi
      ;;
  esac
  [ -n "$MTU" ] || MTU="ukjent"
  [ -n "$MAC" ] || MAC="ukjent"
}

# Kablet eller Wi-Fi?
finn_lenketype() {
  local wifi_if
  IS_WIFI=0
  [ -n "$IFACE" ] || return 0
  case "$PLATFORM" in
    darwin)
      cap 10 networksetup -listallhardwareports
      wifi_if=$(printf '%s\n' "$OUT" | awk '/^Hardware Port: (Wi-Fi|AirPort)/ {w=1; next} w && /^Device:/ {print $2; w=0}')
      case " $wifi_if " in *" $IFACE "*) IS_WIFI=1 ;; esac
      [ "$IS_WIFI" -eq 0 ] && [ -z "$wifi_if" ] && case "$IFACE" in en0) IS_WIFI=1 ;; esac
      ;;
    termux)
      case "$IFACE" in wlan*|wifi*) IS_WIFI=1 ;; esac
      [ "$IS_WIFI" -eq 0 ] && have termux-wifi-connectioninfo && { cap 15 termux-wifi-connectioninfo; [ "$(jget "$OUT" ip)" = "$IPV4" ] && [ -n "$IPV4" ] && IS_WIFI=1; }
      ;;
    *)
      if [ -d "/sys/class/net/$IFACE/wireless" ]; then IS_WIFI=1
      elif have iw && run_timeout 5 iw dev "$IFACE" info >/dev/null 2>&1; then IS_WIFI=1
      else case "$IFACE" in wl*) IS_WIFI=1 ;; esac
      fi
      ;;
  esac
}

sek0_system() {
  local verkt tilstede="" mangler="" t lenke
  start_sec 0
  add_result INFO "Operativsystem" "$OS_BESKRIVELSE ($PLATFORM)"
  add_result INFO "Vert og bruker" "$HOSTNAVN / ${USER:-${LOGNAME:-$(id -un 2>/dev/null || printf 'ukjent')}}"
  add_result INFO "Tidspunkt" "$(date '+%Y-%m-%d %H:%M:%S %z')"
  add_result INFO "bash-versjon" "${BASH_VERSION:-ukjent}"
  add_result INFO "Skriptversjon" "$SKRIPTNAVN v$VERSJON — parametre: hurtig=$HURTIG ned=$FORVENTET_NED opp=$FORVENTET_OPP iperf=${IPERF_SERVER:-ingen} interne=${INTERNE_NAVN:-ingen}"
  cap 5 uname -a
  verkt="ping traceroute tracepath dig nslookup iperf3 speedtest speedtest-cli mtr nmap arping iw nmcli jq python3 perl timeout curl nc ip ethtool"
  for t in $verkt; do
    if have "$t"; then tilstede="$tilstede $t"; else mangler="$mangler $t"; fi
  done
  add_result INFO "Verktøy tilgjengelig" "${tilstede# }"
  if [ -n "$mangler" ]; then
    # shellcheck disable=SC2086  # bevisst ordsplitting av verktøylisten
    add_result INFO "Verktøy mangler (valgfrie)" "${mangler# }" "" "Installasjon: $(inst_samlet $mangler)"
  fi
  if [ "$PLATFORM" = "termux" ]; then
    if have termux-wifi-connectioninfo; then add_result INFO "Termux:API" "termux-wifi-connectioninfo funnet"
    else add_result SKIP "Termux:API" "mangler — pkg install termux-api iputils traceroute dnsutils og installer appen Termux:API"; fi
  fi
  if [ -n "$TIMEOUT_BIN" ]; then add_result INFO "Tidsavbrudd-mekanisme" "$TIMEOUT_BIN"
  elif [ "$HAVE_PERL" -eq 1 ]; then add_result INFO "Tidsavbrudd-mekanisme" "perl alarm (timeout mangler: $(inst_hint timeout))"
  else add_result WARN "Tidsavbrudd-mekanisme" "verken timeout eller perl finnes — stoler på verktøyenes egne tidsgrenser"; fi
  have curl || add_result FAIL "curl" "mangler — de fleste WAN-/video-/hastighetstester hopper over. Installer: $(inst_hint curl)"
  [ "$PROXY_AKTIV" -eq 1 ] && add_result WARN "Proxy-miljøvariabler" "satt (${https_proxy:-${HTTPS_PROXY:-${http_proxy:-${HTTP_PROXY:-${ALL_PROXY:-?}}}}}) — HTTP-målinger går via proxy"

  IFACE="$GRENSESNITT_PARAM"; GATEWAY="$GATEWAY_PARAM"
  finn_nett
  finn_lenketype
  if [ "$IS_WIFI" -eq 1 ]; then lenke="Wi-Fi"; else lenke="kablet/ukjent"; fi
  if [ -n "$IFACE" ]; then
    add_result INFO "Grensesnitt" "$IFACE ($lenke), IPv4 ${IPV4:-ukjent}/${PREFIX:-?}, MTU $MTU, MAC $MAC"
  else
    add_result WARN "Grensesnitt" "fant ikke aktivt grensesnitt — bruk --grensesnitt IF"
  fi
  if [ -n "$GATEWAY" ]; then
    add_result INFO "Gateway" "$GATEWAY$([ -n "$GATEWAY_PARAM" ] && printf ' (fra --gateway)')"
  else
    add_result WARN "Gateway" "ingen default-rute funnet — gateway-tester hopper over (bruk --gateway IP)"
  fi
  [ "$N_DEFAULT_ROUTES" -gt 1 ] && add_result INFO "Default-ruter" "$N_DEFAULT_ROUTES (vurderes i seksjon 2)"
  return 0
}

# ### 7. Seksjon 1  Lenke og Wi-Fi ---------------------------------------------

# macOS: tolker system_profiler SPAirPortDataType -> TSV "MODUS<TAB>SSID<TAB>NØKKEL<TAB>VERDI"
parse_sp_airport() {
  awk '
    function indent(s,  m) { m = match(s, /[^ ]/); return (m ? m - 1 : 0) }
    {
      ind = indent($0); t = $0; sub(/^ +/, "", t); sub(/ +$/, "", t)
      if (t == "Current Network Information:") { mode = "CUR"; base = ind; ssid = ""; next }
      if (t == "Other Local Wi-Fi Networks:") { mode = "OTH"; base = ind; ssid = ""; next }
      if (mode != "" && ind <= base) { mode = ""; next }
      if (mode == "") next
      if (ind == base + 2 && t ~ /:$/) { ssid = substr(t, 1, length(t) - 1); printf "%s\t%s\tSSID\t%s\n", mode, ssid, ssid; next }
      if (ind >= base + 4) { p = index(t, ": "); if (p > 0) printf "%s\t%s\t%s\t%s\n", mode, ssid, substr(t, 1, p - 1), substr(t, p + 2) }
    }'
}

# Legger en nabo i NABOER-fila: nabo_add BSSID SSID KANAL RSSI BÅND SIKKERHET
nabo_add() {
  printf '%s\t%s\t%s\t%s\t%s\t%s\n' "${1:-?}" "${2:-}" "${3:-?}" "${4:-?}" "${5:-?}" "${6:-?}" >> "$NABOER"
}

wifi_darwin() {
  local tsv l mode ssid key val chan_s o_ssid="" o_bssid="" o_chan="" o_rssi="" o_band="" o_sec="" airport
  cap 40 system_profiler SPAirPortDataType
  tsv=$(printf '%s\n' "$OUT" | parse_sp_airport)
  while IFS= read -r l; do
    [ -n "$l" ] || continue
    mode=${l%%"$TAB"*}; l=${l#*"$TAB"}; ssid=${l%%"$TAB"*}; l=${l#*"$TAB"}; key=${l%%"$TAB"*}; val=${l#*"$TAB"}
    if [ "$mode" = "CUR" ]; then
      case "$key" in
        SSID) [ -z "$SSID" ] && SSID="$val" ;;
        "PHY Mode") [ -z "$PHY" ] && PHY="$val" ;;
        BSSID) [ -z "$BSSID" ] && BSSID="$val" ;;
        Channel) if [ -z "$CHANNEL" ]; then
                   CHANNEL=${val%% *}
                   case "$val" in *2GHz*) BAND="2.4 GHz" ;; *5GHz*) BAND="5 GHz" ;; *6GHz*) BAND="6 GHz" ;; esac
                   chan_s=$(printf '%s' "$val" | sed -n 's/.*[,(] *\([0-9]*MHz\).*/\1/p'); [ -n "$chan_s" ] && WIDTH="${chan_s%MHz} MHz"
                 fi ;;
        Security) [ -z "$SECURITY" ] && SECURITY="$val" ;;
        "Signal / Noise") if [ -z "$RSSI" ]; then RSSI=$(printf '%s' "$val" | awk '{print $1}'); NOISE=$(printf '%s' "$val" | awk -F'/' '{ split($2,a," "); print a[1] }'); fi ;;
        "Transmit Rate") [ -z "$TXRATE" ] && TXRATE="$val Mbit/s" ;;
        "MCS Index") [ -n "$TXRATE" ] && TXRATE="$TXRATE (MCS $val)" ;;
      esac
    else
      case "$key" in
        SSID) [ -n "$o_ssid" ] && nabo_add "$o_bssid" "$o_ssid" "$o_chan" "$o_rssi" "$o_band" "$o_sec"
              o_ssid="$ssid"; o_bssid=""; o_chan=""; o_rssi=""; o_band=""; o_sec="" ;;
        BSSID) o_bssid="$val" ;;
        Channel) o_chan=${val%% *}; case "$val" in *2GHz*) o_band="2.4 GHz" ;; *5GHz*) o_band="5 GHz" ;; *6GHz*) o_band="6 GHz" ;; esac ;;
        "Signal / Noise") o_rssi=$(printf '%s' "$val" | awk '{print $1}') ;;
        Security) o_sec="$val" ;;
      esac
    fi
  done <<< "$tsv"
  [ -n "$o_ssid" ] && nabo_add "$o_bssid" "$o_ssid" "$o_chan" "$o_rssi" "$o_band" "$o_sec"
  [ -z "$CHANNEL" ] || [ -n "$BAND" ] || BAND=$(chan_to_band "$CHANNEL")
  # Reserveløsninger: ipconfig getsummary (macOS 14+), networksetup, wdutil (bare uten passord), gammel airport
  cap 10 ipconfig getsummary "$IFACE"
  [ -z "$SSID" ] && SSID=$(printf '%s\n' "$OUT" | awk -F' : ' '$1 ~ /SSID$/ && $1 !~ /BSSID/ {print $2; exit}')
  [ -z "$BSSID" ] && BSSID=$(printf '%s\n' "$OUT" | awk -F' : ' '$1 ~ /BSSID$/ {print $2; exit}')
  [ -z "$SECURITY" ] && SECURITY=$(printf '%s\n' "$OUT" | awk -F' : ' '$1 ~ /Security$/ {print $2; exit}')
  cap 10 networksetup -getairportnetwork "$IFACE"
  [ -z "$SSID" ] && SSID=$(printf '%s\n' "$OUT" | sed -n 's/^Current Wi-Fi Network: //p' | head -n 1)
  if have sudo && run_timeout 5 sudo -n true >/dev/null 2>&1 && have wdutil; then
    cap 20 sudo -n wdutil info
    [ -z "$RSSI" ] && RSSI=$(printf '%s\n' "$OUT" | awk -F' : ' '$1 ~ /RSSI/ {print $2; exit}' | awk '{print $1}')
    [ -z "$NOISE" ] && NOISE=$(printf '%s\n' "$OUT" | awk -F' : ' '$1 ~ /Noise/ {print $2; exit}' | awk '{print $1}')
    [ -z "$TXRATE" ] && TXRATE=$(printf '%s\n' "$OUT" | awk -F' : ' '$1 ~ /Tx Rate/ {print $2; exit}')
    [ -z "$PHY" ] && PHY=$(printf '%s\n' "$OUT" | awk -F' : ' '$1 ~ /PHY Mode/ {print $2; exit}')
  else
    raw_note "sudo -n wdutil info hoppet over (krever passord — skriptet spør aldri)"
  fi
  airport="/System/Library/PrivateFrameworks/Apple80211.framework/Versions/Current/Resources/airport"
  if [ -x "$airport" ]; then
    cap 15 "$airport" -I
    [ -z "$RSSI" ] && RSSI=$(printf '%s\n' "$OUT" | awk -F': ' '$1 ~ /agrCtlRSSI/ {print $2; exit}')
    [ -z "$NOISE" ] && NOISE=$(printf '%s\n' "$OUT" | awk -F': ' '$1 ~ /agrCtlNoise/ {print $2; exit}')
    [ -z "$SSID" ] && SSID=$(printf '%s\n' "$OUT" | awk -F': ' '$1 ~ / SSID$/ {print $2; exit}')
  fi
  MAC_RANDOM="ukjent (macOS viser privat Wi-Fi-adresse per nettverk i Systeminnstillinger → Wi-Fi → Detaljer)"
}

wifi_linux() {
  local con l rate
  if have iw; then
    cap 10 iw dev "$IFACE" link
    SSID=$(printf '%s\n' "$OUT" | awk '$1=="SSID:" { print substr($0, index($0,"SSID:")+6) }' | head -n 1)
    BSSID=$(printf '%s\n' "$OUT" | awk '$1=="Connected" {print $3; exit}')
    FREQ=$(printf '%s\n' "$OUT" | awk '$1=="freq:" {print $2; exit}')
    FREQ=${FREQ%%.*}
    RSSI=$(printf '%s\n' "$OUT" | awk '$1=="signal:" {print $2; exit}')
    TXRATE=$(printf '%s\n' "$OUT" | awk '$1=="tx" && $2=="bitrate:" { $1=""; $2=""; sub(/^ +/,""); print; exit }')
    RXRATE=$(printf '%s\n' "$OUT" | awk '$1=="rx" && $2=="bitrate:" { $1=""; $2=""; sub(/^ +/,""); print; exit }')
    rate="$TXRATE $RXRATE"
    case "$rate" in *EHT*) PHY="802.11be" ;; *HE-MCS*) PHY="802.11ax" ;; *VHT-MCS*) PHY="802.11ac" ;; *MCS*) PHY="802.11n" ;; esac
    cap 10 iw dev "$IFACE" info
    CHANNEL=$(printf '%s\n' "$OUT" | awk '$1=="channel" {print $2; exit}')
    WIDTH=$(printf '%s\n' "$OUT" | awk '$1=="channel" { for(i=1;i<=NF;i++) if ($i=="width:") { print $(i+1), $(i+2); exit } }')
    WIDTH=${WIDTH%,}
    cap 10 iw dev "$IFACE" station dump
    [ -z "$RSSI" ] && RSSI=$(printf '%s\n' "$OUT" | awk '$1=="signal" && $2=="avg:" {print $3; exit}')
    if [ -n "$FREQ" ]; then BAND=$(freq_to_band "$FREQ"); [ -z "$CHANNEL" ] && CHANNEL=$(freq_to_chan "$FREQ"); fi
    # Naboer via scan dump (ingen ny skanning utløses)
    cap 15 iw dev "$IFACE" scan dump
    printf '%s\n' "$OUT" | awk -v tab="$TAB" '
      function flush() { if (b != "") print b tab s tab f tab sig tab sec }
      $1=="BSS" { flush(); b=$2; sub(/\(.*/,"",b); s=""; f=""; sig=""; sec="åpen" }
      $1=="freq:" { f=$2; sub(/\..*/,"",f) }
      $1=="signal:" { sig=$2 }
      $1=="SSID:" { s=substr($0, index($0,"SSID:")+6) }
      $1=="RSN:" { sec="WPA2" }
      $1=="WPA:" { if (sec=="åpen") sec="WPA" }
      /Authentication suites:/ && /SAE/ { sec="WPA3" }
      END { flush() }' | while IFS="$TAB" read -r b s f sig sec; do
        [ -n "$f" ] || continue
        nabo_add "$b" "$s" "$(freq_to_chan "$f")" "${sig%%.*}" "$(freq_to_band "$f")" "$sec"
      done
    [ -z "$SECURITY" ] && [ -n "$BSSID" ] && SECURITY=$(awk -F"$TAB" -v b="$BSSID" 'tolower($1)==tolower(b) {print $6; exit}' "$NABOER")
  fi
  if have nmcli; then
    cap 15 nmcli -t -f ACTIVE,SSID,BSSID,CHAN,FREQ,SIGNAL,SECURITY dev wifi
    printf '%s\n' "$OUT" | while IFS= read -r l; do
      l=${l//\\:/$US}
      IFS=: read -r akt s b c f sig sec <<< "$l"
      b=${b//$US/:}; s=${s//$US/:}
      [ -n "$b" ] || continue
      f=${f%% *}
      if [ "$akt" = "yes" ]; then printf 'AKTIV\t%s\t%s\t%s\t%s\t%s\t%s\n' "$s" "$b" "$c" "$f" "$sig" "$sec" >> "$TMPD/nmcli-aktiv.txt"; fi
      if ! grep -qi "^$b$TAB" "$NABOER" 2>/dev/null; then
        nabo_add "$b" "$s" "$c" "$(awk -v p="$sig" 'BEGIN{printf "%d", p/2-100}')" "$(freq_to_band "$f")" "${sec:-åpen}"
      fi
    done
    if [ -s "$TMPD/nmcli-aktiv.txt" ]; then
      IFS="$TAB" read -r _ s b c f sig sec < "$TMPD/nmcli-aktiv.txt"
      [ -z "$SSID" ] && SSID="$s"; [ -z "$BSSID" ] && BSSID="$b"; [ -z "$CHANNEL" ] && CHANNEL="$c"
      [ -z "$FREQ" ] && FREQ="$f"; [ -z "$BAND" ] && BAND=$(freq_to_band "$f"); [ -z "$SECURITY" ] && SECURITY="${sec:-åpen}"
      [ -z "$RSSI" ] && RSSI="$(awk -v p="$sig" 'BEGIN{printf "%d", p/2-100}') (omregnet fra $sig %)"
    fi
    cap 10 nmcli -t -f NAME,DEVICE con show --active
    con=$(printf '%s\n' "$OUT" | awk -F: -v d="$IFACE" '$2==d {print $1; exit}')
    if [ -n "$con" ]; then
      cap 10 nmcli -g 802-11-wireless.cloned-mac-address con show "$con"
      case "$OUT" in
        random|stable) MAC_RANDOM="ja ($OUT, NetworkManager)" ;;
        permanent) MAC_RANDOM="nei (permanent)" ;;
        "") MAC_RANDOM="nei (standard, ikke satt)" ;;
        *) MAC_RANDOM="$OUT" ;;
      esac
    fi
  fi
  if [ -z "$MAC_RANDOM" ] && have ethtool; then
    cap 5 ethtool -P "$IFACE"
    l=$(printf '%s\n' "$OUT" | awk '{print $NF; exit}')
    if [ -n "$l" ] && [ "$l" != "00:00:00:00:00:00" ]; then
      if [ "$l" = "$MAC" ]; then MAC_RANDOM="nei (permanent $l)"; else MAC_RANDOM="ja (permanent $l, i bruk $MAC)"; fi
    fi
  fi
  [ -n "$MAC_RANDOM" ] || MAC_RANDOM="ukjent"
}

wifi_termux() {
  local ci l
  if ! have termux-wifi-connectioninfo; then
    return 1
  fi
  cap 20 termux-wifi-connectioninfo
  ci="$OUT"
  SSID=$(jget "$ci" ssid); SSID=${SSID#\"}; SSID=${SSID%\"}
  BSSID=$(jget "$ci" bssid)
  RSSI=$(jget "$ci" rssi)
  FREQ=$(jget "$ci" frequency_mhz)
  TXRATE="$(jget "$ci" link_speed_mbps) Mbit/s (link speed)"
  l=$(jget "$ci" mac_address)
  if [ "$l" = "02:00:00:00:00:00" ] || [ -z "$l" ]; then MAC_RANDOM="skjult av Android (02:00:00:00:00:00); Android bruker tilfeldig MAC per SSID som standard"; else MAC_RANDOM="ukjent (MAC $l)"; fi
  [ "$MAC" = "ukjent" ] && [ -n "$l" ] && MAC="$l"
  if [ -n "$FREQ" ]; then BAND=$(freq_to_band "$FREQ"); CHANNEL=$(freq_to_chan "$FREQ"); fi
  if have termux-wifi-scaninfo; then
    cap 25 termux-wifi-scaninfo
    printf '%s' "$OUT" | tr -d "$NL$CR" | sed 's/},/}\
/g' | while IFS= read -r l; do
      b=$(jget "$l" bssid); [ -n "$b" ] || continue
      f=$(jget "$l" frequency_mhz)
      sec=$(jget "$l" capabilities)
      case "$sec" in *SAE*) sec="WPA3" ;; *WPA2*|*RSN*) sec="WPA2" ;; *WPA*) sec="WPA" ;; "") sec="?" ;; *) sec="åpen" ;; esac
      nabo_add "$b" "$(jget "$l" ssid)" "$(freq_to_chan "$f")" "$(jget "$l" rssi)" "$(freq_to_band "$f")" "$sec"
    done
    [ -z "$SECURITY" ] && [ -n "$BSSID" ] && SECURITY=$(awk -F"$TAB" -v b="$BSSID" 'tolower($1)==tolower(b) {print $6; exit}' "$NABOER")
  fi
  return 0
}

sek1_lenke() {
  local st n_same n_co l ekstra
  start_sec 1
  if [ -z "$IFACE" ]; then
    add_result SKIP "Lenke" "ingen grensesnitt funnet"
    return 0
  fi
  if [ "$IS_WIFI" -eq 0 ]; then
    case "$PLATFORM" in
      darwin) [ -n "$WIRED_SPEED" ] && add_result INFO "Kablet lenke (media)" "$WIRED_SPEED" || add_result INFO "Kablet lenke" "hastighet/dupleks ikke rapportert av ifconfig" ;;
      *)
        if have ethtool; then
          cap 10 ethtool "$IFACE"
          WIRED_SPEED=$(printf '%s\n' "$OUT" | awk -F': ' '$1 ~ /Speed/ {s=$2} $1 ~ /Duplex/ {d=$2} END{ if (s!="") print s " " d }')
        fi
        if [ -z "$WIRED_SPEED" ] && [ -r "/sys/class/net/$IFACE/speed" ]; then
          l=$(cat "/sys/class/net/$IFACE/speed" 2>/dev/null)
          if er_tall "$l" && [ "$l" -gt 0 ]; then WIRED_SPEED="$l Mb/s $(cat "/sys/class/net/$IFACE/duplex" 2>/dev/null)"
          else WIRED_SPEED="ukjent (virtuelt grensesnitt eller driver uten rapportering)"; fi
        fi
        if [ -n "$WIRED_SPEED" ]; then add_result INFO "Kablet lenke (hastighet/dupleks)" "$WIRED_SPEED"
        else add_result INFO "Kablet lenke" "hastighet/dupleks ikke tilgjengelig ($(inst_hint ethtool))"; fi ;;
    esac
    add_result INFO "Wi-Fi" "ikke aktuelt — $IFACE er kablet eller ukjent lenketype"
    return 0
  fi
  case "$PLATFORM" in
    darwin) wifi_darwin ;;
    termux)
      if ! wifi_termux; then
        add_result SKIP "Wi-Fi-detaljer" "mangler 'termux-wifi-connectioninfo' — pkg install termux-api iputils traceroute dnsutils og installer appen Termux:API"
        return 0
      fi ;;
    *)
      if have iw || have nmcli; then wifi_linux
      else
        add_result SKIP "Wi-Fi-detaljer" "mangler 'iw' og 'nmcli' — installer: $(inst_hint iw) / $(inst_hint nmcli)"
        return 0
      fi ;;
  esac
  add_result INFO "SSID / BSSID" "${SSID:-ukjent} / ${BSSID:-ukjent}"
  if [ -z "$SSID" ] && [ "$PLATFORM" = "darwin" ]; then
    add_result INFO "Merknad macOS" "SSID/BSSID kan være skjult uten stedstillatelse for Terminal (Systeminnstillinger → Personvern → Stedstjenester)"
  fi
  add_result INFO "Bånd / kanal / bredde" "${BAND:-ukjent} / ${CHANNEL:-ukjent} / ${WIDTH:-ukjent}"
  case "$BAND" in
    "2.4 GHz") add_result WARN "Bånd 2,4 GHz" "tilkoblet på 2,4 GHz — Adm-nett bør bruke 5/6 GHz" "5/6 GHz" ;;
    "5 GHz"|"6 GHz") add_result PASS "Bånd" "$BAND" "5/6 GHz" ;;
    *) add_result INFO "Bånd" "ukjent" ;;
  esac
  add_result INFO "PHY-modus" "${PHY:-ukjent}"
  if er_tall "${RSSI%% *}"; then
    st=$(grade_ge "${RSSI%% *}" -65 -72)
    add_result "$st" "RSSI" "$RSSI dBm" "PASS ≥ -65 dBm, WARN ≥ -72 dBm, FAIL < -72 dBm"
  else
    add_result SKIP "RSSI" "ikke tilgjengelig"
  fi
  if er_tall "${NOISE%% *}" && er_tall "${RSSI%% *}"; then
    SNR=$(( ${RSSI%% *} - ${NOISE%% *} ))
    st=$(grade_ge "$SNR" 25 15)
    add_result "$st" "Støy / SNR" "$NOISE dBm / $SNR dB" "SNR PASS ≥25 dB, WARN ≥15 dB, FAIL <15 dB"
  else
    add_result INFO "Støy / SNR" "støynivå ikke tilgjengelig på denne plattformen"
  fi
  add_result INFO "Tx-/Rx-rate" "tx ${TXRATE:-ukjent}; rx ${RXRATE:-ukjent}"
  case "$SECURITY" in
    *WPA3*|*SAE*) add_result INFO "Sikkerhet" "$SECURITY" ;;
    *WPA2*|*RSN*|*PSK*|*Enterprise*|*Personal*) add_result INFO "Sikkerhet" "$SECURITY" ;;
    ""|"?") add_result INFO "Sikkerhet" "ukjent" ;;
    *) add_result WARN "Sikkerhet" "$SECURITY — forventet WPA2/WPA3" ;;
  esac
  add_result INFO "MAC / tilfeldig MAC" "$MAC / ${MAC_RANDOM:-ukjent}"
  if [ -s "$NABOER" ] && [ -n "$SSID" ]; then
    n_same=$(awk -F"$TAB" -v s="$SSID" -v b="$BSSID" '$2==s && tolower($1)!=tolower(b) {n++} END{print n+0}' "$NABOER")
    ekstra=$(awk -F"$TAB" -v s="$SSID" -v b="$BSSID" '$2==s && tolower($1)!=tolower(b) { printf "%s (kanal %s, %s dBm, %s); ", $1, $3, $4, $5 }' "$NABOER")
    add_result INFO "Andre BSSID-er på samme SSID" "$n_same — ${ekstra:-ingen sett}"
    n_co=$(awk -F"$TAB" -v c="$CHANNEL" -v b="$BSSID" '$3==c && tolower($1)!=tolower(b) {n++} END{print n+0}' "$NABOER")
    add_result INFO "Andre nett på samme kanal (co-channel)" "$n_co på kanal ${CHANNEL:-?}"
    add_result INFO "Naboer totalt i skann" "$(awk 'END{print NR}' "$NABOER") BSSID-er (full liste i råutdata)"
    raw_add "naboliste (bssid, ssid, kanal, rssi, bånd, sikkerhet)" "$(sort -t "$TAB" -k4 -nr "$NABOER")"
  else
    l="skanneliste ikke tilgjengelig"
    case "$PLATFORM" in
      termux) have termux-wifi-scaninfo || l="mangler 'termux-wifi-scaninfo' — pkg install termux-api iputils traceroute dnsutils og installer appen Termux:API" ;;
      linux) have iw || have nmcli || l="mangler 'iw'/'nmcli' — $(inst_hint iw)" ;;
    esac
    add_result SKIP "Naboer / co-channel" "$l"
  fi
  return 0
}

# ### 8. Seksjon 2  IP og TCP/IP -----------------------------------------------

sek2_ip() {
  local arp_mac="" l
  start_sec 2
  if [ -z "$IPV4" ]; then
    add_result FAIL "IPv4-adresse" "ingen IPv4-adresse funnet på ${IFACE:-ukjent grensesnitt}"
  else
    case "$IPV4" in
      169.254.*) add_result FAIL "IPv4-adresse" "$IPV4 er link-lokal (169.254.x.x) — DHCP feilet" "ikke 169.254/16" ;;
      *) add_result PASS "IPv4-adresse" "$IPV4/${PREFIX:-?}${NETMASK:+ (maske $NETMASK)}" "gyldig, ikke 169.254/16" ;;
    esac
  fi
  if [ -n "$GATEWAY" ]; then add_result INFO "Gateway" "$GATEWAY"; else add_result FAIL "Gateway" "ingen default-rute"; fi
  if er_tall "$MTU"; then
    if [ "$MTU" -eq 1500 ]; then add_result PASS "MTU på grensesnitt" "$MTU" "1500"
    elif [ "$MTU" -gt 1500 ]; then add_result INFO "MTU på grensesnitt" "$MTU (jumbo/større enn 1500)" "1500"
    else add_result WARN "MTU på grensesnitt" "$MTU (lavere enn 1500)" "1500"; fi
  else
    add_result INFO "MTU på grensesnitt" "ukjent"
  fi
  if [ "$N_DEFAULT_ROUTES" -gt 1 ]; then
    add_result WARN "Default-ruter" "$N_DEFAULT_ROUTES default-ruter (VPN/dobbel tilkobling?)" "1"
  elif [ "$N_DEFAULT_ROUTES" -eq 1 ]; then
    add_result PASS "Default-ruter" "1" "1"
  else
    add_result WARN "Default-ruter" "ingen default-rute funnet" "1"
  fi
  add_result INFO "IPv6-adresser (global)" "${IPV6_GLOBAL:-ingen}"
  add_result INFO "IPv6 default-rute" "${IPV6_DEFAULT:-ingen}"
  # ARP for gateway
  if [ -n "$GATEWAY" ]; then
    if have arp; then
      cap 10 arp -an
      arp_mac=$(printf '%s\n' "$OUT" | awk -v g="($GATEWAY)" '$2==g { print $4; exit }')
      [ -z "$arp_mac" ] && arp_mac=$(printf '%s\n' "$OUT" | awk -v g="$GATEWAY" '$1==g { print $3; exit }')
    fi
    if [ -z "$arp_mac" ] && have ip; then
      cap 10 ip neigh show "$GATEWAY"
      arp_mac=$(printf '%s\n' "$OUT" | awk '{ for(i=1;i<=NF;i++) if ($i=="lladdr") { print $(i+1); exit } }')
    fi
    if [ -z "$arp_mac" ] && [ -r /proc/net/arp ]; then
      cap 5 cat /proc/net/arp
      arp_mac=$(printf '%s\n' "$OUT" | awk -v g="$GATEWAY" '$1==g { print $4; exit }')
    fi
    case "$arp_mac" in
      ""|"(incomplete)"|"00:00:00:00:00:00") add_result INFO "ARP-oppføring for gateway" "ikke i ARP-tabellen ennå (kan fylles av ping i seksjon 5)" ;;
      *) add_result INFO "ARP-oppføring for gateway" "$GATEWAY er $arp_mac" ;;
    esac
  fi
  # Duplikat-IP (arping -D) hvis mulig
  if [ -n "$IPV4" ] && [ -n "$IFACE" ]; then
    if have arping; then
      cap 15 arping -c 3 -D -I "$IFACE" "$IPV4"
      if [ "$RC" -eq 0 ]; then add_result PASS "Duplikat-IP (arping -D)" "ingen andre svarer for $IPV4" "0 svar"
      elif printf '%s' "$OUT" | grep -qiE 'permitted|permission|must be root|socket'; then add_result SKIP "Duplikat-IP (arping -D)" "arping krever root — hoppet over (kjør manuelt: sudo arping -c 3 -D -I $IFACE $IPV4)"
      elif printf '%s' "$OUT" | grep -qiE 'invalid|usage|unknown'; then add_result SKIP "Duplikat-IP (arping -D)" "denne arping-varianten støtter ikke -D"
      else add_result FAIL "Duplikat-IP (arping -D)" "en annen enhet svarte for $IPV4" "0 svar"; fi
    else
      skip_tool "Duplikat-IP (arping -D)" arping
    fi
  fi
  # Full rutetabell i råutdata
  case "$PLATFORM" in
    darwin) cap 10 netstat -rn ;;
    *) if have ip; then cap 10 ip route show; cap 10 ip -o -4 addr; elif have netstat; then cap 10 netstat -rn; fi ;;
  esac
  return 0
}

# ### 9. Seksjon 3  DHCP ---------------------------------------------------------

# Henter DHCP-info uten å fornye lease.
dhcp_darwin() {
  local pk
  cap 10 ipconfig getpacket "$IFACE"
  pk="$OUT"
  DHCP_SERVER=$(printf '%s\n' "$pk" | sed -n 's/^server_identifier ([a-z0-9_]*): //p' | head -n 1)
  DHCP_LEASE=$(printf '%s\n' "$pk" | sed -n 's/^lease_time ([a-z0-9_]*): //p' | head -n 1)
  case "$DHCP_LEASE" in 0x*) DHCP_LEASE=$((DHCP_LEASE)) ;; esac
  DHCP_ROUTER=$(printf '%s\n' "$pk" | sed -n 's/^router ([a-z0-9_]*): //p' | head -n 1 | tr -d '{}')
  DHCP_DNS=$(printf '%s\n' "$pk" | sed -n 's/^domain_name_server ([a-z0-9_]*): //p' | head -n 1 | tr -d '{}' | tr ',' ' ')
  DHCP_DOMAIN=$(printf '%s\n' "$pk" | sed -n 's/^domain_name ([a-z0-9_]*): //p' | head -n 1)
  DHCP_NTP=$(printf '%s\n' "$pk" | sed -n 's/^network_time_protocol_servers ([a-z0-9_]*): //p' | head -n 1 | tr -d '{}')
  DHCP_WINS=$(printf '%s\n' "$pk" | sed -n 's/^nb_over_tcpip_name_server ([a-z0-9_]*): //p' | head -n 1 | tr -d '{}')
  DHCP_MASK=$(printf '%s\n' "$pk" | sed -n 's/^subnet_mask ([a-z0-9_]*): //p' | head -n 1)
  cap 10 ipconfig getsummary "$IFACE"
  DHCP_START=$(printf '%s\n' "$OUT" | awk -F' : ' '$1 ~ /LeaseStartTime/ {print $2; exit}')
  DHCP_EXPIRE=$(printf '%s\n' "$OUT" | awk -F' : ' '$1 ~ /LeaseExpirationTime/ {print $2; exit}')
}

dhcp_linux() {
  local con f l
  if have nmcli; then
    cap 10 nmcli -t -f NAME,DEVICE con show --active
    con=$(printf '%s\n' "$OUT" | awk -F: -v d="$IFACE" '$2==d {print $1; exit}')
    if [ -n "$con" ]; then
      cap 10 nmcli -t -f DHCP4.OPTION con show "$con"
      l=$(printf '%s\n' "$OUT" | sed -n 's/^DHCP4\.OPTION\[[0-9]*\]:\(.*\) = \(.*\)$/\1=\2/p')
      DHCP_SERVER=$(printf '%s\n' "$l" | sed -n 's/^dhcp_server_identifier=//p' | head -n 1)
      DHCP_LEASE=$(printf '%s\n' "$l" | sed -n 's/^dhcp_lease_time=//p' | head -n 1)
      DHCP_EXPIRE=$(printf '%s\n' "$l" | sed -n 's/^expiry=//p' | head -n 1)
      if er_tall "$DHCP_EXPIRE"; then DHCP_EXPIRE="$(date -d "@$DHCP_EXPIRE" '+%Y-%m-%d %H:%M:%S' 2>/dev/null || printf '%s' "$DHCP_EXPIRE") (epoch $DHCP_EXPIRE)"; fi
      DHCP_ROUTER=$(printf '%s\n' "$l" | sed -n 's/^routers=//p' | head -n 1)
      DHCP_DNS=$(printf '%s\n' "$l" | sed -n 's/^domain_name_servers=//p' | head -n 1)
      DHCP_DOMAIN=$(printf '%s\n' "$l" | sed -n 's/^domain_name=//p' | head -n 1)
      DHCP_NTP=$(printf '%s\n' "$l" | sed -n 's/^ntp_servers=//p' | head -n 1)
      DHCP_WINS=$(printf '%s\n' "$l" | sed -n 's/^netbios_name_servers=//p' | head -n 1)
      DHCP_MASK=$(printf '%s\n' "$l" | sed -n 's/^subnet_mask=//p' | head -n 1)
    fi
  fi
  if [ -z "$DHCP_SERVER" ]; then
    for f in /var/lib/dhcp/dhclient*.leases /var/lib/dhcp/*.leases /var/lib/NetworkManager/*.lease /run/systemd/netif/leases/*; do
      [ -r "$f" ] || continue
      cap 5 cat "$f"
      [ -z "$DHCP_SERVER" ] && DHCP_SERVER=$(printf '%s\n' "$OUT" | sed -n 's/.*option dhcp-server-identifier \([0-9.]*\);.*/\1/p; s/^SERVER_ADDRESS=//p' | tail -n 1)
      [ -z "$DHCP_LEASE" ] && DHCP_LEASE=$(printf '%s\n' "$OUT" | sed -n 's/.*option dhcp-lease-time \([0-9]*\);.*/\1/p; s/^LIFETIME=//p' | tail -n 1)
      [ -z "$DHCP_DNS" ] && DHCP_DNS=$(printf '%s\n' "$OUT" | sed -n 's/.*option domain-name-servers \([0-9., ]*\);.*/\1/p; s/^DNS=//p' | tail -n 1 | tr ',' ' ')
      [ -z "$DHCP_ROUTER" ] && DHCP_ROUTER=$(printf '%s\n' "$OUT" | sed -n 's/.*option routers \([0-9.]*\);.*/\1/p; s/^ROUTER=//p' | tail -n 1)
      [ -z "$DHCP_DOMAIN" ] && DHCP_DOMAIN=$(printf '%s\n' "$OUT" | sed -n 's/.*option domain-name "\([^"]*\)";.*/\1/p; s/^DOMAINNAME=//p' | tail -n 1)
      [ -z "$DHCP_EXPIRE" ] && DHCP_EXPIRE=$(printf '%s\n' "$OUT" | sed -n 's/.*expire [0-9] \(.*\);.*/\1/p' | tail -n 1)
      [ -z "$DHCP_NTP" ] && DHCP_NTP=$(printf '%s\n' "$OUT" | sed -n 's/^NTP=//p' | tail -n 1)
    done
  fi
}

dhcp_termux() {
  OUT=$(run_timeout 10 getprop 2>&1 </dev/null); RC=$?
  raw_add "getprop | grep -i dhcp (rc=$RC, kun dhcp-nøkler vist)" "$(printf '%s\n' "$OUT" | grep -i 'dhcp\.')"
  DHCP_SERVER=$(printf '%s\n' "$OUT" | sed -n 's/^\[dhcp\.'"$IFACE"'\.server\]: \[\(.*\)\]/\1/p' | head -n 1)
  DHCP_LEASE=$(printf '%s\n' "$OUT" | sed -n 's/^\[dhcp\.'"$IFACE"'\.leasetime\]: \[\(.*\)\]/\1/p' | head -n 1)
  DHCP_DNS=$(printf '%s\n' "$OUT" | sed -n 's/^\[dhcp\.'"$IFACE"'\.dns[0-9]\]: \[\(.*\)\]/\1/p' | tr "$NL" ' ')
  DHCP_ROUTER=$(printf '%s\n' "$OUT" | sed -n 's/^\[dhcp\.'"$IFACE"'\.gateway\]: \[\(.*\)\]/\1/p' | head -n 1)
  DHCP_DOMAIN=$(printf '%s\n' "$OUT" | sed -n 's/^\[dhcp\.'"$IFACE"'\.domain\]: \[\(.*\)\]/\1/p' | head -n 1)
}

DHCP_WINS=""; DHCP_MASK=""; DHCP_START=""; DHCP_EXPIRE=""
sek3_dhcp() {
  local n srv
  start_sec 3
  if [ -z "$IFACE" ]; then add_result SKIP "DHCP" "ingen grensesnitt"; return 0; fi
  case "$PLATFORM" in
    darwin) dhcp_darwin ;;
    termux) dhcp_termux ;;
    *) dhcp_linux ;;
  esac
  if [ -z "$DHCP_SERVER" ] && [ -z "$DHCP_LEASE" ]; then
    case "$PLATFORM" in
      termux) add_result SKIP "DHCP-server" "DHCP-informasjon er ikke lesbar for apper på Android 8+ (getprop dhcp.* tom) — se Innstillinger → Wi-Fi → nettverksdetaljer" ;;
      darwin) add_result SKIP "DHCP-server" "ipconfig getpacket ga ingen DHCP-pakke (statisk IP eller ingen lease)" ;;
      *) add_result SKIP "DHCP-server" "fant ingen DHCP-lease (nmcli/lease-filer). Statisk IP, eller mangler 'nmcli': $(inst_hint nmcli)" ;;
    esac
    [ -n "$DHCP_DNS" ] && add_result INFO "DNS fra DHCP" "$DHCP_DNS"
    return 0
  fi
  add_result INFO "DHCP-server" "${DHCP_SERVER:-ukjent}"
  if er_tall "$DHCP_LEASE"; then
    if [ "$DHCP_LEASE" -lt 600 ]; then add_result WARN "Lease-tid" "$DHCP_LEASE s ($(awk -v s="$DHCP_LEASE" 'BEGIN{printf "%.1f", s/60}') min) — svært kort" "≥10 min"
    else add_result PASS "Lease-tid" "$DHCP_LEASE s ($(awk -v s="$DHCP_LEASE" 'BEGIN{printf "%.1f", s/3600}') t)" "≥10 min"; fi
  else
    add_result INFO "Lease-tid" "${DHCP_LEASE:-ukjent}"
  fi
  add_result INFO "Lease start / utløp" "${DHCP_START:-ukjent} / ${DHCP_EXPIRE:-ukjent} (fornyes aldri av dette skriptet)"
  add_result INFO "DHCP-opsjoner" "router=${DHCP_ROUTER:-?} dns=${DHCP_DNS:-?} maske=${DHCP_MASK:-?} domene=${DHCP_DOMAIN:-?} ntp=${DHCP_NTP:-?} wins=${DHCP_WINS:-?}"
  if [ -n "$DHCP_SERVER" ] && [ -n "$GATEWAY" ]; then
    if [ "$DHCP_SERVER" = "$GATEWAY" ]; then add_result INFO "DHCP-server vs gateway" "samme enhet ($GATEWAY)"
    else add_result INFO "DHCP-server vs gateway" "DHCP-server $DHCP_SERVER ≠ gateway $GATEWAY (egen DHCP-server/relay — normalt hvis planlagt)"; fi
  fi
  if [ -n "$DHCP_ROUTER" ] && [ -n "$GATEWAY" ] && [ "$DHCP_ROUTER" != "$GATEWAY" ]; then
    add_result WARN "DHCP-router vs aktiv gateway" "DHCP ga router $DHCP_ROUTER, men default-rute går via $GATEWAY"
  fi
  # Rogue-DHCP-skann kun med nmap og passordfri sudo
  if have nmap && have sudo && run_timeout 5 sudo -n true >/dev/null 2>&1; then
    cap 40 sudo -n nmap --script broadcast-dhcp-discover -e "$IFACE"
    n=$(printf '%s\n' "$OUT" | grep -c 'Server Identifier')
    srv=$(printf '%s\n' "$OUT" | awk '/Server Identifier/ { printf "%s ", $NF }')
    if [ "$n" -gt 1 ]; then add_result WARN "Rogue-DHCP-skann (nmap)" "$n DHCP-servere svarte: $srv" "1"
    elif [ "$n" -eq 1 ]; then add_result PASS "Rogue-DHCP-skann (nmap)" "1 server svarte: $srv" "1"
    else add_result INFO "Rogue-DHCP-skann (nmap)" "ingen DHCP-svar innen tidsfristen"; fi
  else
    add_result SKIP "Rogue-DHCP-skann" "krever nmap og passordfri sudo — kjør manuelt: sudo nmap --script broadcast-dhcp-discover -e ${IFACE}$(have nmap || printf ' (installer: %s)' "$(inst_hint nmap)")"
  fi
  return 0
}

# ### 10. Seksjon 4  DNS ---------------------------------------------------------

finn_resolvere() {
  local l
  RESOLVERS=""; SEARCH_DOMAIN=""; RESOLVER_KILDE=""
  case "$PLATFORM" in
    darwin)
      cap 10 scutil --dns
      RESOLVERS=$(printf '%s\n' "$OUT" | awk '/^resolver #1$/ {r=1; next} /^resolver #/ {r=0} r && $1 ~ /^nameserver\[/ { printf "%s ", $3 }')
      SEARCH_DOMAIN=$(printf '%s\n' "$OUT" | awk '/^resolver #1$/ {r=1; next} /^resolver #/ {r=0} r && $1=="search" && $2 ~ /^domain\[/ { printf "%s ", $4 }')
      RESOLVER_KILDE="scutil --dns"
      ;;
    termux)
      cap 10 getprop net.dns1; l="$OUT"
      cap 10 getprop net.dns2; l="$l $OUT"
      RESOLVERS=$(printf '%s' "$l" | tr ' ' "$NL" | grep -E '^[0-9a-fA-F.:]+$' | tr "$NL" ' ')
      RESOLVER_KILDE="getprop net.dns1/2 (best effort — ikke lesbar på Android 8+)"
      if [ -z "$RESOLVERS" ] && [ -n "$DHCP_DNS" ]; then RESOLVERS="$DHCP_DNS"; RESOLVER_KILDE="DHCP-opsjon"; fi
      ;;
    *)
      if have resolvectl; then
        cap 10 resolvectl status
        RESOLVERS=$(printf '%s\n' "$OUT" | awk -F': ' '/DNS Servers:/ { print $2 } /Current DNS Server:/ { print $2 }' | tr ' ' "$NL" | grep -E '^[0-9a-fA-F.:%]+' | awk '!s[$0]++' | tr "$NL" ' ')
        SEARCH_DOMAIN=$(printf '%s\n' "$OUT" | awk -F': ' '/DNS Domain:/ { print $2 }' | tr "$NL" ' ')
        RESOLVER_KILDE="resolvectl status"
      fi
      if [ -r /etc/resolv.conf ]; then
        cap 5 cat /etc/resolv.conf
        l=$(printf '%s\n' "$OUT" | awk '$1=="nameserver" { printf "%s ", $2 }')
        if [ -z "$SEARCH_DOMAIN" ]; then SEARCH_DOMAIN=$(printf '%s\n' "$OUT" | awk '$1=="search" || $1=="domain" { $1=""; sub(/^ /,""); printf "%s ", $0 }'); fi
        case " $l " in
          *" 127.0.0.53 "*|*" 127.0.0.54 "*)
            [ -n "$RESOLVERS" ] && RESOLVER_KILDE="systemd-resolved stub 127.0.0.53 → oppstrøms: $RESOLVER_KILDE" || { RESOLVERS="$l"; RESOLVER_KILDE="/etc/resolv.conf (stub 127.0.0.53, oppstrøms ukjent)"; } ;;
          *) [ -z "$RESOLVERS" ] && { RESOLVERS="$l"; RESOLVER_KILDE="/etc/resolv.conf"; } ;;
        esac
      fi
      ;;
  esac
  RESOLVERS=$(printf '%s' "$RESOLVERS" | tr ' ' "$NL" | grep -E '^[0-9a-fA-F.:%]+$' | awk '!s[$0]++' | tr "$NL" ' ')
  RESOLVERS=${RESOLVERS% }
  SEARCH_DOMAIN=${SEARCH_DOMAIN% }
}

sek4_dns() {
  local r n ms_liste st med feil svar_nrk="" svar_liste="" nx1 nx2 antall_res=0 verkt navn rev
  start_sec 4
  finn_resolvere
  if have dig; then verkt="dig"; elif have python3; then verkt="python3 (systemresolver, socket.getaddrinfo)"; else verkt=""; fi
  if [ -z "$verkt" ]; then
    add_result SKIP "DNS-oppslag" "mangler 'dig' og 'python3' — installer: $(inst_hint dig)"
    add_result INFO "Konfigurerte resolvere" "${RESOLVERS:-ukjent} (kilde: ${RESOLVER_KILDE:-ukjent})"
    return 0
  fi
  if [ -z "$RESOLVERS" ]; then
    if [ "$PLATFORM" = "termux" ]; then
      add_result INFO "Konfigurerte resolvere" "ikke lesbare på Android 8+ (getprop net.dns1 tom). Merk: dig i Termux bruker \$PREFIX/etc/resolv.conf (8.8.8.8), ikke Android sin DNS"
      if [ -n "$GATEWAY" ] && [ "$verkt" = "dig" ]; then RESOLVERS="$GATEWAY"; RESOLVER_KILDE="antatt: gateway (vanlig DNS-forwarder)"; fi
    else
      add_result WARN "Konfigurerte resolvere" "fant ingen resolvere (kilde forsøkt: ${RESOLVER_KILDE:-ingen})"
    fi
  else
    add_result INFO "Konfigurerte resolvere" "$RESOLVERS (kilde: $RESOLVER_KILDE)"
  fi
  add_result INFO "Søkedomene" "${SEARCH_DOMAIN:-ingen}"
  if [ "$verkt" != "dig" ]; then
    add_result INFO "DNS-metode" "$verkt — kan ikke måle per resolver; måler systemresolver. Installer dig: $(inst_hint dig)"
    RESOLVERS="system"
  fi
  for r in $RESOLVERS; do
    antall_res=$((antall_res + 1))
    ms_liste=""; feil=0
    for n in $DNS_NAVN; do
      if [ "$r" = "system" ]; then dns_lookup "" "$n" A; else dns_lookup "$r" "$n" A; fi
      case "$DNSQ_STATUS" in
        NOERROR) er_tall "$DNSQ_MS" && ms_liste="$ms_liste $DNSQ_MS" ;;
        *) feil=$((feil + 1)) ;;
      esac
      [ "$n" = "nrk.no" ] && { svar_nrk=$(printf '%s' "$DNSQ_ANS" | tr ' ' "$NL" | grep -v '^$' | sort | tr "$NL" ' '); svar_nrk=${svar_nrk% }; }
    done
    med=$(median "$ms_liste")
    if [ "$feil" -ge 5 ] || [ "$med" = "-" ]; then
      add_result FAIL "Oppslag via $r" "ingen svar ($feil/5 feilet)" "PASS <50 ms, WARN <150 ms, FAIL ≥150 ms eller feil"
    else
      st=$(grade_lt "$med" 50 150)
      [ "$feil" -gt 0 ] && st="FAIL"
      add_result "$st" "Oppslag via $r" "median $med ms (5 navn, $feil feil)" "PASS <50 ms, WARN <150 ms, FAIL ≥150 ms eller feil" "målinger: ${ms_liste# }"
    fi
    [ -n "$svar_nrk" ] && svar_liste="$svar_liste$r=[${svar_nrk% }] "
    add_result INFO "nrk.no A via $r" "${svar_nrk:-ingen svar}"
    # NXDOMAIN-test per resolver
    nx1="nx$RANDOM$RANDOM.invalid"; nx2="nx$RANDOM$RANDOM.marivold.no"
    for navn in "$nx1" "$nx2"; do
      if [ "$r" = "system" ]; then dns_lookup "" "$navn" A; else dns_lookup "$r" "$navn" A; fi
      case "$DNSQ_STATUS" in
        NXDOMAIN) add_result PASS "NXDOMAIN-test via $r" "$navn → NXDOMAIN" "må feile" ;;
        NOERROR) if [ -n "$DNSQ_ANS" ]; then add_result FAIL "NXDOMAIN-test via $r" "$navn ga svar ${DNSQ_ANS% } — DNS-kapring/portal" "må feile"
                 else add_result WARN "NXDOMAIN-test via $r" "$navn ga NOERROR uten A-svar (uvanlig)" "må feile"; fi ;;
        TIMEOUT) add_result WARN "NXDOMAIN-test via $r" "$navn — tidsavbrudd (resolver svarte ikke)" "må feile" ;;
        *) add_result WARN "NXDOMAIN-test via $r" "$navn — status $DNSQ_STATUS" "må feile" ;;
      esac
    done
  done
  [ "$antall_res" -eq 0 ] && add_result SKIP "Oppslagstid per resolver" "ingen resolvere å teste"
  # Sammenligning av nrk.no mellom resolvere
  if [ "$antall_res" -gt 1 ]; then
    n=$(printf '%s' "$svar_liste" | tr ' ' "$NL" | sed 's/^[^=]*=//' | grep -v '^$' | sort -u | wc -l | tr -d ' ')
    if [ "$n" -gt 1 ]; then add_result WARN "Samme svar for nrk.no fra alle resolvere" "ulike svar: $svar_liste(CDN kan gi ulike IP-er, men avvik kan også være kapring)" "likt svar"
    else add_result PASS "Samme svar for nrk.no fra alle resolvere" "ja: $svar_liste" "likt svar"; fi
  fi
  # DoH
  if have curl; then
    cap 15 curl -sS --max-time 8 -H 'accept: application/dns-json' "$URL_DOH"
    if printf '%s' "$OUT" | grep -q '"Status":0'; then add_result INFO "DoH (cloudflare-dns.com)" "nås — svar: $(printf '%s' "$OUT" | grep -o '"data":"[^"]*"' | sed 's/"data"://; s/"//g' | tr "$NL" ' ')"
    else add_result INFO "DoH (cloudflare-dns.com)" "ikke nådd / blokkert ($(feil_tekst))"; fi
  fi
  # Interne navn
  if [ -n "$INTERNE_NAVN" ]; then
    for navn in $(printf '%s' "$INTERNE_NAVN" | tr ',' ' '); do
      dns_lookup "" "$navn" A
      case "$DNSQ_STATUS" in
        NOERROR) if [ -n "$DNSQ_ANS" ]; then add_result PASS "Internt navn $navn" "${DNSQ_ANS% } (${DNSQ_MS:-?} ms)" "må svare"
                 else add_result FAIL "Internt navn $navn" "NOERROR uten A-post" "må svare"; fi ;;
        SKIP) add_result SKIP "Internt navn $navn" "ingen DNS-verktøy" ;;
        *) add_result FAIL "Internt navn $navn" "status $DNSQ_STATUS" "må svare" ;;
      esac
    done
  else
    add_result INFO "Interne navn" "ingen oppgitt (bruk --interne-navn a,b,c)"
  fi
  # Reversoppslag av gateway
  if [ -n "$GATEWAY" ]; then
    rev=""
    if have dig; then
      cap 8 dig -x "$GATEWAY" +short +time=2 +tries=1
      rev=$(printf '%s\n' "$OUT" | grep -v '^;' | head -n 1)
    elif have python3; then
      cap 8 python3 -c 'import socket,sys
try: print(socket.gethostbyaddr(sys.argv[1])[0])
except Exception as e: print("")' "$GATEWAY"
      rev=$(printf '%s\n' "$OUT" | head -n 1)
    fi
    add_result INFO "Reversoppslag av gateway" "${rev:-ingen PTR for $GATEWAY}"
  fi
  return 0
}

# ### 11. Seksjon 5  Gateway og brannmur ---------------------------------------

# pmtu_test VERT NAVN -> setter PMTU_RESULT ("1500", "1480", "1428", "svart hull", "ikke nådd", "skip")
PMTU_RESULT=""
pmtu_test() {
  local host="$1" s ok=""
  PMTU_RESULT="skip"
  have ping || return 0
  for s in 1472 1452 1400; do
    if do_ping "$host" 2 0.2 "$s"; then ok="$s"; break; fi
    if printf '%s' "$OUT" | grep -qiE 'invalid|usage|unknown option|illegal option'; then PMTU_RESULT="ustøttet"; return 0; fi
  done
  case "$ok" in
    1472) PMTU_RESULT="1500" ;;
    1452) PMTU_RESULT="1480" ;;
    1400) PMTU_RESULT="1428" ;;
    *) if do_ping "$host" 2 0.2; then PMTU_RESULT="svart hull"; else PMTU_RESULT="ikke nådd"; fi ;;
  esac
}
pmtu_rapporter() { # pmtu_rapporter NAVN
  case "$PMTU_RESULT" in
    1500) add_result PASS "PMTU mot $1" "1500 byte ende-til-ende (DF 1472 nyttelast går)" "PASS 1500, WARN ≤1452, FAIL <1400/svart hull" ;;
    1480|1428) add_result WARN "PMTU mot $1" "kun DF ≤$(( PMTU_RESULT - 28 )) byte nyttelast går (MTU $PMTU_RESULT — PPPoE/tunnel)" "PASS 1500, WARN ≤1452, FAIL <1400/svart hull" ;;
    "svart hull") add_result FAIL "PMTU mot $1" "vanlig ping går, men ingen DF-pakker ≥1400 — PMTUD-svart hull" "PASS 1500, WARN ≤1452, FAIL <1400/svart hull" ;;
    "ikke nådd") add_result SKIP "PMTU mot $1" "verten svarer ikke på ping" ;;
    ustøttet) add_result SKIP "PMTU mot $1" "denne ping-varianten støtter ikke DF-flagg (toybox?) — pkg install termux-api iputils traceroute dnsutils" ;;
    *) add_result SKIP "PMTU mot $1" "mangler 'ping' — installer: $(inst_hint ping)" ;;
  esac
}

sek5_gateway() {
  local st hop ip rtt maal fil nhop siste
  start_sec 5
  if [ -z "$GATEWAY" ]; then
    add_result SKIP "Gateway RTT" "ingen gateway kjent (bruk --gateway IP)"
  elif ! have ping; then
    skip_tool "Gateway RTT (20 pakker)" ping
  else
    if do_ping "$GATEWAY" 20 0.2; then
      st=$(grade_le "$PING_AVG" 10 30)
      add_result "$st" "Gateway RTT snitt (20 pakker)" "$PING_AVG ms (min $PING_MIN / maks $PING_MAX)" "PASS ≤10 ms, WARN ≤30 ms, FAIL >30 ms"
      st=$(grade_le "$PING_LOSS" 0 1)
      add_result "$st" "Pakketap mot gateway" "$PING_LOSS % ($PING_RX/$PING_TX svar)" "PASS 0 %, WARN ≤1 %, FAIL >1 %"
      if er_tall "$PING_MDEV"; then
        st=$(grade_lt "$PING_MDEV" 5 20)
        add_result "$st" "Jitter mot gateway (std.avvik)" "$PING_MDEV ms" "PASS <5 ms, WARN <20 ms, FAIL ≥20 ms"
      fi
    else
      add_result FAIL "Gateway RTT (20 pakker)" "gateway $GATEWAY svarer ikke på ICMP ($PING_RX/$PING_TX)" "PASS ≤10 ms"
    fi
  fi
  # Traceroute
  if have traceroute || have tracepath; then
    for maal in 1.1.1.1 nrk.no; do
      if [ "$maal" = "1.1.1.1" ]; then fil="$TRACEFIL_1"; else fil="$TRACEFIL_2"; fi
      if do_trace "$maal" "$fil"; then
        hop=$(trace_hop "$fil" 1); ip=${hop%% *}; rtt=${hop##* }
        add_result INFO "Traceroute $maal hopp 1 (brannmur/gateway)" "${ip:-*} ${rtt:-*} ms"
        hop=$(trace_hop "$fil" 2); ip=${hop%% *}; rtt=${hop##* }
        if er_tall "$rtt"; then
          st=$(grade_lt "$rtt" 10 25)
          add_result "$st" "Traceroute $maal hopp 2 (første hopp utenfor brannmuren, fiber/ISP)" "${ip:-?} $rtt ms" "PASS <10 ms, WARN <25 ms, FAIL ≥25 ms"
        else
          add_result INFO "Traceroute $maal hopp 2 (første hopp utenfor brannmuren)" "svarer ikke (ICMP filtrert hos ISP?)" "PASS <10 ms, WARN <25 ms, FAIL ≥25 ms"
        fi
        nhop=$(awk 'END{print NR}' "$fil")
        siste=$(awk '$2!="*" {ip=$2; rtt=$3; h=$1} END{print h, ip, rtt}' "$fil")
        add_result INFO "Traceroute $maal" "$nhop hopp listet; siste svar: hopp ${siste% * *} ${siste#* } ms — hele sporet i råutdata"
      else
        add_result WARN "Traceroute $maal" "ingen hopp tolket (rc=$RC)"
      fi
    done
  else
    add_result SKIP "Traceroute 1.1.1.1 og nrk.no" "mangler 'traceroute' — installer: $(inst_hint traceroute)"
  fi
  # TCP-porter på gateway (eksponert admin-UI/SSH mot klientnettet?)
  if [ -n "$GATEWAY" ]; then
    if tcp_port_open "$GATEWAY" 443; then add_result INFO "TCP 443 mot gateway (admin-UI?)" "åpen — admin-grensesnitt eksponert mot klientnettet; bør være begrenset til admin-VLAN"
    else add_result INFO "TCP 443 mot gateway (admin-UI?)" "lukket/filtrert"; fi
    if tcp_port_open "$GATEWAY" 22; then add_result INFO "TCP 22 mot gateway (SSH?)" "åpen — bør være begrenset til admin-VLAN"
    else add_result INFO "TCP 22 mot gateway (SSH?)" "lukket/filtrert"; fi
  fi
  # PMTU / DF-tester
  if [ -n "$GATEWAY" ]; then pmtu_test "$GATEWAY"; PMTU_GW="$PMTU_RESULT"; pmtu_rapporter "gateway $GATEWAY"; fi
  pmtu_test 1.1.1.1; PMTU_INET="$PMTU_RESULT"; pmtu_rapporter "1.1.1.1"
  return 0
}

# ### 12. Seksjon 6  Fiber og WAN ---------------------------------------------

sek6_wan() {
  local colo="" ip org="" st maal cg="" navn fil
  start_sec 6
  if ! have curl; then
    add_result SKIP "Offentlig IP / ISP" "mangler 'curl' — installer: $(inst_hint curl)"
  else
    cap 15 curl -sS --max-time 8 "$URL_TRACE"
    PUBLIC_IP=$(printf '%s\n' "$OUT" | sed -n 's/^ip=//p' | head -n 1)
    colo=$(printf '%s\n' "$OUT" | sed -n 's/^colo=//p' | head -n 1)
    if [ -z "$PUBLIC_IP" ]; then
      cap 15 curl -sS --max-time 8 "$URL_TRACE2"
      PUBLIC_IP=$(printf '%s\n' "$OUT" | sed -n 's/^ip=//p' | head -n 1)
      colo=$(printf '%s\n' "$OUT" | sed -n 's/^colo=//p' | head -n 1)
    fi
    if [ -z "$PUBLIC_IP" ]; then
      cap 15 curl -sS --max-time 8 "$URL_IPIFY"
      ip=$(printf '%s\n' "$OUT" | tail -n 1 | tr -d ' ')
      printf '%s' "$ip" | grep -qE '^[0-9a-fA-F.:]+$' && PUBLIC_IP="$ip"
    fi
    if [ -n "$PUBLIC_IP" ]; then
      add_result INFO "Offentlig IP" "$PUBLIC_IP${colo:+ (Cloudflare-node $colo)}"
      cap 15 curl -sS --max-time 8 "https://ipinfo.io/$PUBLIC_IP/json"
      org=$(jget "$OUT" org)
      if [ -n "$org" ]; then
        add_result INFO "ISP / ASN (ipinfo.io)" "$org — $(jget "$OUT" city), $(jget "$OUT" country) — vertsnavn $(jget "$OUT" hostname)"
      else
        add_result INFO "ISP / ASN (ipinfo.io)" "ikke tilgjengelig"
      fi
      if er_cgnat "$PUBLIC_IP"; then add_result WARN "CGNAT" "offentlig IP $PUBLIC_IP er i 100.64.0.0/10 — CGNAT hos ISP (ingen innkommende tilkoblinger, dobbel NAT)" "ingen CGNAT"
      elif er_privat "$PUBLIC_IP"; then add_result WARN "Offentlig IP er privat" "$PUBLIC_IP — trolig proxy/VPN/dobbel NAT" "offentlig adresse"
      else add_result PASS "CGNAT" "offentlig IP er ikke i 100.64.0.0/10" "ingen CGNAT"; fi
    else
      add_result FAIL "Offentlig IP" "kunne ikke hentes fra 1.1.1.1, cloudflare.com eller api.ipify.org — internett nede eller blokkert?"
    fi
  fi
  for fil in "$TRACEFIL_1" "$TRACEFIL_2"; do
    [ -s "$fil" ] || continue
    while read -r _ ip _; do
      [ "$ip" = "*" ] && continue
      er_cgnat "$ip" && cg="$cg $ip"
    done < "$fil"
  done
  if [ -n "$cg" ]; then add_result WARN "CGNAT-hopp i traceroute" "hopp i 100.64.0.0/10:${cg}" "ingen"
  elif [ -s "$TRACEFIL_1" ]; then add_result PASS "CGNAT-hopp i traceroute" "ingen hopp i 100.64.0.0/10" "ingen"; fi
  # Internett-RTT
  if have ping; then
    for maal in $MAAL_DNS; do
      if do_ping "$maal" 10 0.2; then
        if [ "$maal" = "9.9.9.9" ]; then
          add_result INFO "Internett RTT $maal" "snitt $PING_AVG ms, tap $PING_LOSS %"
        else
          st=$(grade_le "$PING_AVG" 25 60)
          add_result "$st" "Internett RTT $maal (10 pakker)" "snitt $PING_AVG ms (min $PING_MIN / maks $PING_MAX), tap $PING_LOSS %" "PASS ≤25 ms, WARN ≤60 ms, FAIL >60 ms"
        fi
      else
        add_result FAIL "Internett RTT $maal" "ingen svar (ICMP blokkert eller ingen internett)" "PASS ≤25 ms"
      fi
    done
    for maal in $MAAL_NORSKE; do
      if do_ping "$maal" 5 0.2; then add_result INFO "RTT $maal" "snitt $PING_AVG ms, tap $PING_LOSS %"
      else add_result INFO "RTT $maal" "ingen ICMP-svar (mange CDN-er svarer ikke på ping)"; fi
    done
  else
    add_result SKIP "Internett RTT (1.1.1.1, 8.8.8.8, 9.9.9.9, nrk.no, vg.no, telenor.no)" "mangler 'ping' — installer: $(inst_hint ping)"
  fi
  # IPv6 ut mot internett
  if have curl; then
    cap 15 curl -6 -sS --max-time 8 "$URL_TRACE2"
    ip=$(printf '%s\n' "$OUT" | sed -n 's/^ip=//p' | head -n 1)
    if [ -n "$ip" ]; then add_result INFO "IPv6 mot internett" "fungerer — offentlig IPv6 $ip"
    else add_result INFO "IPv6 mot internett" "ingen IPv6-forbindelse (${IPV6_GLOBAL:+adresse finnes lokalt: $IPV6_GLOBAL}${IPV6_GLOBAL:-ingen global IPv6-adresse lokalt})"; fi
  fi
  # XIQ-forutsetninger (det AP-ene trenger mot skyen)
  for navn in $MAAL_XIQ; do
    resolve_name "$navn"
    if [ "$RES_STATUS" = "NOERROR" ] && [ -n "$RES_IPS" ]; then
      add_result INFO "XIQ: DNS $navn" "${RES_IPS% }${RES_MS:+ ($RES_MS ms)}"
    elif [ "$RES_STATUS" = "SKIP" ]; then
      add_result SKIP "XIQ: DNS $navn" "ingen DNS-verktøy"
    else
      add_result FAIL "XIQ: DNS $navn" "oppslag feilet ($RES_STATUS) — AP-er mister CAPWAP hvis DNS ikke virker" "må svare"
    fi
    if have curl; then
      if curl_tid "https://$navn/"; then
        add_result INFO "XIQ: TCP 443 $navn" "nås (HTTP $CURL_CODE, connect $CURL_CONNECT_MS ms, TLS $CURL_TLS_MS ms)"
      else
        add_result FAIL "XIQ: TCP 443 $navn" "nås ikke fra dette nettet (curl rc=$RC) — AP-er trenger TCP 443 hit" "må nås"
      fi
    fi
  done
  add_result INFO "XIQ: CAPWAP UDP 12222" "kan ikke testes fra en klient — sjekk at brannmuren tillater UDP 12222 og TCP 443 fra AP-VLAN til internett"
  return 0
}

# ### 13. Seksjon 7  TCP-ytelse -----------------------------------------------

# tcp_tellere -> "sendt retrans" (tom hvis ukjent)
tcp_tellere() {
  case "$PLATFORM" in
    darwin)
      cap 10 netstat -s -p tcp
      printf '%s\n' "$OUT" | awk '/packets sent$/ && s=="" {s=$1} /data packets.*retransmitted$/ && r=="" {r=$1} END{ if (s!="") print s, (r==""?0:r) }' ;;
    *)
      if have nstat; then
        cap 10 nstat -az TcpOutSegs TcpRetransSegs
        printf '%s\n' "$OUT" | awk '$1=="TcpOutSegs"{s=$2} $1=="TcpRetransSegs"{r=$2} END{ if (s!="") print s, (r==""?0:r) }'
      elif [ -r /proc/net/snmp ]; then
        cap 5 cat /proc/net/snmp
        printf '%s\n' "$OUT" | awk '$1=="Tcp:" { if (!h) { for(i=1;i<=NF;i++){ if($i=="OutSegs") oi=i; if($i=="RetransSegs") ri=i }; h=1 } else if (oi && ri) print $oi, $ri }'
      fi ;;
  esac
}

pmtu_tekst() {
  case "${1:-}" in
    ""|skip) printf 'ikke testet' ;;
    ustøttet) printf 'ikke testbart (ping uten DF-støtte)' ;;
    1500|1480|1428) printf '%s byte' "$1" ;;
    *) printf '%s' "$1" ;;
  esac
}

sek7_tcp() {
  local cc="" l host ms_liste="" st med
  start_sec 7
  case "$PLATFORM" in
    darwin) cap 5 sysctl -n net.inet.tcp.cc.algorithm; [ "$RC" -eq 0 ] && cc="$OUT"
            [ -z "$cc" ] && { cap 5 sysctl -n net.inet.tcp.cc_algorithm; [ "$RC" -eq 0 ] && cc="$OUT"; } ;;
    *) cap 5 sysctl -n net.ipv4.tcp_congestion_control; [ "$RC" -eq 0 ] && cc="$OUT"
       [ -z "$cc" ] && [ -r /proc/sys/net/ipv4/tcp_congestion_control ] && cc=$(cat /proc/sys/net/ipv4/tcp_congestion_control 2>/dev/null) ;;
  esac
  add_result INFO "TCP congestion control" "${cc:-ukjent}"
  l=$(tcp_tellere)
  if [ -n "$l" ]; then
    TCP_SENT_FOR=${l%% *}; TCP_RETRANS_FOR=${l##* }
    add_result INFO "TCP-tellere før hastighetstest" "sendt $TCP_SENT_FOR segmenter, $TCP_RETRANS_FOR retransmittert (delta beregnes etter seksjon 8)"
  else
    add_result SKIP "TCP-tellere" "ikke lesbare (netstat -s / nstat / /proc/net/snmp)"
  fi
  if have curl; then
    for host in $MAAL_TCP; do
      if curl_tid "https://$host/"; then
        ms_liste="$ms_liste $CURL_CONNECT_MS"
        add_result INFO "TCP connect + TLS $host" "connect $CURL_CONNECT_MS ms, TLS-handshake $CURL_TLS_MS ms (HTTP $CURL_CODE)"
      else
        add_result WARN "TCP connect + TLS $host" "feilet (curl rc=$RC: $(feil_tekst))"
      fi
    done
    med=$(median "$ms_liste")
    if [ "$med" = "-" ]; then
      add_result FAIL "TCP connect til 443 (median 5 mål)" "ingen vellykkede tilkoblinger" "PASS <40 ms, WARN <100 ms, FAIL ≥100 ms"
    else
      st=$(grade_lt "$med" 40 100)
      add_result "$st" "TCP connect til 443 (median 5 mål)" "$med ms${PROXY_AKTIV:+}$([ "$PROXY_AKTIV" -eq 1 ] && printf ' (målt mot proxy!)')" "PASS <40 ms, WARN <100 ms, FAIL ≥100 ms" "målinger: ${ms_liste# }"
    fi
  else
    add_result SKIP "TCP connect + TLS (5 mål)" "mangler 'curl' — installer: $(inst_hint curl)"
  fi
  add_result INFO "MTU-oppsummering" "grensesnitt MTU $MTU; PMTU gateway $(pmtu_tekst "$PMTU_GW"); PMTU internett $(pmtu_tekst "$PMTU_INET")"
  return 0
}

# Kjøres etter seksjon 8: differanse i TCP-tellere
sek7_etter() {
  local l sendt retr d_s d_r pct st
  CUR_SEC="${SEC_NAMES[7]}"; RAWFILE="$TMPD/raw-7.txt"
  if [ "$HURTIG" -eq 1 ]; then
    add_result SKIP "TCP-retransmisjoner under hastighetstest" "krever hastighetstesten (hoppet over med --hurtig)"
    return 0
  fi
  [ -n "$TCP_SENT_FOR" ] || { add_result SKIP "TCP-retransmisjoner under hastighetstest" "TCP-tellere ikke lesbare"; return 0; }
  l=$(tcp_tellere)
  [ -n "$l" ] || { add_result SKIP "TCP-retransmisjoner under hastighetstest" "TCP-tellere ikke lesbare etter testen"; return 0; }
  sendt=${l%% *}; retr=${l##* }
  d_s=$((sendt - TCP_SENT_FOR)); d_r=$((retr - TCP_RETRANS_FOR))
  if [ "$d_s" -le 0 ]; then add_result SKIP "TCP-retransmisjoner under hastighetstest" "ingen nye segmenter registrert"; return 0; fi
  pct=$(awk -v r="$d_r" -v s="$d_s" 'BEGIN{printf "%.2f", r*100/s}')
  st=$(grade_lt "$pct" 0.5 2)
  add_result "$st" "TCP-retransmisjoner under hastighetstest" "$pct % ($d_r av $d_s segmenter)" "PASS <0,5 %, WARN <2 %, FAIL ≥2 %"
  return 0
}

# ### 14. Seksjon 8  Hastighet ------------------------------------------------

mbit() { awk -v b="${1:-0}" 'BEGIN{printf "%.1f", b*8/1000000}'; }
mbit_bps() { awk -v b="${1:-0}" 'BEGIN{printf "%.1f", b/1000000}'; }

iperf_kjor() { # iperf_kjor RETNING(ned|opp) -> IPERF_MBIT
  local l
  local -a a
  a=(iperf3 -c "$IPERF_SERVER" -t 8 -P 4 -J)
  [ "$1" = "ned" ] && a+=(-R)
  cap 40 "${a[@]}"
  IPERF_MBIT=""
  if [ "$RC" -eq 0 ]; then
    if have jq; then
      l=$(printf '%s\n' "$OUT" | jq -r '(.end.sum_received.bits_per_second // 0|tostring) + " " + (.end.sum_sent.bits_per_second // 0|tostring)' 2>/dev/null)
    elif have python3; then
      l=$(printf '%s\n' "$OUT" | python3 "$TMPD/iperf.py" 2>/dev/null)
    else
      l="$(printf '%s\n' "$OUT" | grep -o '"bits_per_second":[ ]*[0-9.e+]*' | tail -n 2 | sed 's/.*://' | tr "$NL" ' ')"
    fi
    if [ "$1" = "ned" ]; then l=${l%% *}; else l=${l##* }; fi
    er_tall "$l" && IPERF_MBIT=$(mbit_bps "$l")
  fi
}

IPERF_MBIT=""
sek8_hastighet() {
  local st l ned opp fil sz
  start_sec 8
  if [ "$HURTIG" -eq 1 ]; then add_result SKIP "Hele seksjonen" "hoppet over (--hurtig)"; return 0; fi
  if [ -n "$IPERF_SERVER" ]; then
    if have iperf3; then
      iperf_kjor ned
      if [ -n "$IPERF_MBIT" ]; then
        st=$(grade_ge "$IPERF_MBIT" "$(awk -v e="$FORVENTET_NED" 'BEGIN{print e*0.8}')" "$(awk -v e="$FORVENTET_NED" 'BEGIN{print e*0.5}')")
        add_result "$st" "LAN nedlasting iperf3 (-R, 4 strømmer)" "$IPERF_MBIT Mbit/s fra $IPERF_SERVER" "PASS ≥80 % av $FORVENTET_NED, WARN ≥50 %, FAIL <50 %"
      else add_result WARN "LAN nedlasting iperf3" "iperf3 mot $IPERF_SERVER feilet: $(printf '%s' "$OUT" | grep -i error | head -n 1 | cut -c1-80)"; fi
      iperf_kjor opp
      if [ -n "$IPERF_MBIT" ]; then
        st=$(grade_ge "$IPERF_MBIT" "$(awk -v e="$FORVENTET_OPP" 'BEGIN{print e*0.8}')" "$(awk -v e="$FORVENTET_OPP" 'BEGIN{print e*0.5}')")
        add_result "$st" "LAN opplasting iperf3 (4 strømmer)" "$IPERF_MBIT Mbit/s til $IPERF_SERVER" "PASS ≥80 % av $FORVENTET_OPP, WARN ≥50 %, FAIL <50 %"
      else add_result WARN "LAN opplasting iperf3" "iperf3 mot $IPERF_SERVER feilet"; fi
    else
      skip_tool "LAN-hastighet iperf3 mot $IPERF_SERVER" iperf3
    fi
  else
    add_result INFO "LAN-hastighet (iperf3)" "ingen --iperf-server oppgitt — WAN-testen under isolerer ikke Wi-Fi/switch fra fiber"
  fi
  if ! have curl; then
    add_result SKIP "WAN nedlasting/opplasting" "mangler 'curl' — installer: $(inst_hint curl)"
    return 0
  fi
  cap 40 curl -sS -o /dev/null --max-time 25 -w "${NL}NETT %{speed_download} %{size_download} %{http_code}" "$URL_NED"
  l=$(printf '%s\n' "$OUT" | awk '$1=="NETT" {print $2, $3, $4}' | tail -n 1)
  ned=$(mbit "${l%% *}")
  sz=$(printf '%s' "$l" | awk '{print $2}')
  if er_tall "$sz" && [ "$(fmt0 "$sz")" -gt 1000000 ]; then
    st=$(grade_ge "$ned" "$(awk -v e="$FORVENTET_NED" 'BEGIN{print e*0.8}')" "$(awk -v e="$FORVENTET_NED" 'BEGIN{print e*0.5}')")
    add_result "$st" "WAN nedlasting (Cloudflare 100 MB, maks 25 s)" "$ned Mbit/s ($(awk -v b="$sz" 'BEGIN{printf "%.1f", b/1000000}') MB hentet)" "PASS ≥80 % av $FORVENTET_NED Mbit/s, WARN ≥50 %, FAIL <50 %"
  else
    add_result FAIL "WAN nedlasting (Cloudflare 100 MB)" "feilet: HTTP ${l##* }, $(awk -v b="${sz:-0}" 'BEGIN{printf "%.1f", b/1000000}') MB hentet, curl rc=$RC $(feil_tekst)" "PASS ≥80 % av $FORVENTET_NED Mbit/s"
  fi
  fil="$TMPD/opp.bin"
  if head -c 31457280 /dev/urandom > "$fil" 2>/dev/null || head -c 31457280 /dev/zero > "$fil" 2>/dev/null; then
    cap 40 curl -sS -o /dev/null --max-time 25 -X POST --data-binary "@$fil" -w "${NL}NETT %{speed_upload} %{size_upload} %{http_code}" "$URL_OPP"
    l=$(printf '%s\n' "$OUT" | awk '$1=="NETT" {print $2, $3, $4}' | tail -n 1)
    opp=$(mbit "${l%% *}")
    sz=$(printf '%s' "$l" | awk '{print $2}')
    if er_tall "$sz" && [ "$(fmt0 "$sz")" -gt 1000000 ]; then
      st=$(grade_ge "$opp" "$(awk -v e="$FORVENTET_OPP" 'BEGIN{print e*0.8}')" "$(awk -v e="$FORVENTET_OPP" 'BEGIN{print e*0.5}')")
      add_result "$st" "WAN opplasting (Cloudflare 30 MB POST, maks 25 s)" "$opp Mbit/s ($(awk -v b="$sz" 'BEGIN{printf "%.1f", b/1000000}') MB sendt)" "PASS ≥80 % av $FORVENTET_OPP Mbit/s, WARN ≥50 %, FAIL <50 %"
    else
      add_result FAIL "WAN opplasting (Cloudflare 30 MB POST)" "feilet: HTTP ${l##* }, curl rc=$RC $(feil_tekst)" "PASS ≥80 % av $FORVENTET_OPP Mbit/s"
    fi
    rm -f "$fil"
  else
    add_result SKIP "WAN opplasting" "kunne ikke lage 30 MB testfil i $TMPD"
  fi
  if have speedtest-cli; then
    cap 100 speedtest-cli --simple
    add_result INFO "speedtest-cli --simple" "$(printf '%s' "$OUT" | tr "$NL" ';' | cut -c1-160)"
  elif have speedtest; then
    cap 100 speedtest --accept-license --accept-gdpr
    add_result INFO "speedtest (Ookla)" "$(printf '%s\n' "$OUT" | grep -E 'Download|Upload|Latency|Idle' | tr -s ' ' | tr "$NL" ';' | cut -c1-200)"
  else
    add_result INFO "speedtest-cli / speedtest" "ikke installert (valgfritt): $(inst_hint speedtest-cli)"
  fi
  return 0
}

# ### 15. Seksjon 9  Bufferbloat og jitter under last --------------------------

sek9_bufferbloat() {
  local pid_last pid_gw="" pid_inet="" fil_gw fil_inet gw_idle inet_idle gw_last inet_last d st tap
  start_sec 9
  if [ "$HURTIG" -eq 1 ]; then add_result SKIP "Hele seksjonen" "hoppet over (--hurtig)"; return 0; fi
  if ! have ping; then skip_tool "Bufferbloat (ping under last)" ping; return 0; fi
  if ! have curl; then skip_tool "Bufferbloat (nedlasting som last)" curl; return 0; fi
  # Hvile-referanse: 10 pings hver
  gw_idle="-"; inet_idle="-"
  if [ -n "$GATEWAY" ] && do_ping "$GATEWAY" 10 0.2; then gw_idle=$(median "$PING_TIMES"); fi
  if do_ping 1.1.1.1 10 0.2; then inet_idle=$(median "$PING_TIMES"); fi
  if [ "$gw_idle" = "-" ] && [ "$inet_idle" = "-" ]; then
    add_result SKIP "Bufferbloat" "verken gateway eller 1.1.1.1 svarer på ping i ro"
    return 0
  fi
  add_result INFO "RTT i ro (median 10 pakker)" "gateway ${gw_idle} ms, 1.1.1.1 ${inet_idle} ms"
  # Last: samme 100 MB-nedlasting, gjentatt inntil 4 ganger i én curl-prosess, drepes etterpå
  curl -sS -o /dev/null -o /dev/null -o /dev/null -o /dev/null --max-time 30 "$URL_NED" "$URL_NED" "$URL_NED" "$URL_NED" >/dev/null 2>&1 </dev/null &
  pid_last=$!
  BG_PIDS="$BG_PIDS $pid_last"
  raw_note "bakgrunnslast startet: curl 4× $URL_NED (pid $pid_last)"
  sleep 2
  fil_gw="$TMPD/last-gw.txt"; fil_inet="$TMPD/last-inet.txt"
  if [ -n "$GATEWAY" ] && [ "$gw_idle" != "-" ]; then do_ping_bg "$GATEWAY" 15 0.5 "$fil_gw"; pid_gw=$BG_LAST_PID; else : > "$fil_gw"; fi
  if [ "$inet_idle" != "-" ]; then do_ping_bg 1.1.1.1 15 0.5 "$fil_inet"; pid_inet=$BG_LAST_PID; else : > "$fil_inet"; fi
  [ -n "$pid_gw" ] && wait "$pid_gw" 2>/dev/null
  [ -n "$pid_inet" ] && wait "$pid_inet" 2>/dev/null
  sleep 1
  kill "$pid_last" 2>/dev/null
  wait "$pid_last" 2>/dev/null
  BG_PIDS=${BG_PIDS//$pid_last/}
  if [ -s "$fil_gw" ]; then
    OUT=$(cat "$fil_gw"); raw_add "ping gateway under last" "$OUT"; parse_ping
    gw_last=$(median "$PING_TIMES"); tap="$PING_LOSS"
    if [ "$gw_last" != "-" ]; then
      d=$(awk -v a="$gw_last" -v b="$gw_idle" 'BEGIN{printf "%.1f", a-b}')
      st=$(grade_lt "$d" 30 100)
      add_result "$st" "Bufferbloat mot gateway" "+$d ms (median $gw_last ms under last vs $gw_idle ms i ro)" "PASS <30 ms, WARN <100 ms, FAIL ≥100 ms"
      if gt "$tap" 5; then add_result WARN "Pakketap mot gateway under last" "$tap %" ">5 % gir WARN"; else add_result INFO "Pakketap mot gateway under last" "$tap %"; fi
    else
      add_result WARN "Bufferbloat mot gateway" "ingen ping-svar under last (tap 100 %)" "PASS <30 ms"
    fi
  fi
  if [ -s "$fil_inet" ]; then
    OUT=$(cat "$fil_inet"); raw_add "ping 1.1.1.1 under last" "$OUT"; parse_ping
    inet_last=$(median "$PING_TIMES"); tap="$PING_LOSS"
    if [ "$inet_last" != "-" ]; then
      d=$(awk -v a="$inet_last" -v b="$inet_idle" 'BEGIN{printf "%.1f", a-b}')
      st=$(grade_lt "$d" 30 100)
      add_result "$st" "Bufferbloat mot 1.1.1.1" "+$d ms (median $inet_last ms under last vs $inet_idle ms i ro)" "PASS <30 ms, WARN <100 ms, FAIL ≥100 ms"
      if gt "$tap" 5; then add_result WARN "Pakketap mot 1.1.1.1 under last" "$tap %" ">5 % gir WARN"; else add_result INFO "Pakketap mot 1.1.1.1 under last" "$tap %"; fi
    else
      add_result WARN "Bufferbloat mot 1.1.1.1" "ingen ping-svar under last (tap 100 %)" "PASS <30 ms"
    fi
  fi
  return 0
}

# ### 16. Seksjon 10 Video og strømming ----------------------------------------

# url_join BASE-URL RELATIV -> absolutt URL
url_join() {
  local base="$1" rel="$2" scheme_host
  case "$rel" in
    http://*|https://*) printf '%s' "$rel" ;;
    /*) scheme_host=$(printf '%s' "$base" | sed -E 's#^(https?://[^/]+).*#\1#'); printf '%s%s' "$scheme_host" "$rel" ;;
    *) printf '%s/%s' "${base%/*}" "$rel" ;;
  esac
}

# hls_test MASTER-URL -> 0 hvis segmenter ble målt (HLS_* satt)
HLS_MEAN=""; HLS_MIN=""; HLS_RATIO=""; HLS_N=0; HLS_BW=""
hls_test() {
  local master="$1" variant media seg n=0 mbit_liste="" tid_liste="" l sz t mb medt maxt
  cap 15 curl -sS -L --max-time 10 "$master"
  [ "$RC" -eq 0 ] || return 1
  l=$(printf '%s\n' "$OUT" | awk '
    /^#EXT-X-STREAM-INF/ { bw=$0; sub(/.*BANDWIDTH=/,"",bw); sub(/[^0-9].*/,"",bw); want=1; next }
    want && $0 !~ /^#/ && NF { if (bw+0 > best+0) { best=bw; uri=$0 } want=0 }
    END { if (uri != "") print best, uri }')
  [ -n "$l" ] || return 1
  HLS_BW=${l%% *}; variant=${l#* }
  media=$(url_join "$master" "$variant")
  raw_note "valgt variant: BANDWIDTH=$HLS_BW → $media"
  cap 15 curl -sS -L --max-time 10 "$media"
  [ "$RC" -eq 0 ] || return 1
  for seg in $(printf '%s\n' "$OUT" | awk '$0 !~ /^#/ && NF { print; n++ } n>=6 { exit }'); do
    seg=$(url_join "$media" "$seg")
    cap 25 curl -sS -L -o /dev/null --max-time 20 -w "${NL}NETT %{size_download} %{time_total}" "$seg"
    l=$(printf '%s\n' "$OUT" | awk '$1=="NETT" {print $2, $3}' | tail -n 1)
    sz=${l%% *}; t=${l##* }
    if er_tall "$sz" && er_tall "$t" && gt "$sz" 0 && gt "$t" 0; then
      mb=$(awk -v s="$sz" -v t="$t" 'BEGIN{printf "%.1f", s*8/t/1000000}')
      mbit_liste="$mbit_liste $mb"; tid_liste="$tid_liste $t"; n=$((n + 1))
    fi
  done
  HLS_N=$n
  [ "$n" -ge 3 ] || return 1
  HLS_MEAN=$(mean "$mbit_liste"); HLS_MIN=$(minst "$mbit_liste")
  medt=$(median "$tid_liste"); maxt=$(maks "$tid_liste")
  HLS_RATIO=$(awk -v a="$maxt" -v b="$medt" 'BEGIN{ if (b>0) printf "%.1f", a/b; else print "-" }')
  raw_note "segmenter: Mbit/s =${mbit_liste}; sekunder =${tid_liste}"
  return 0
}

sek10_video() {
  local st host kilde=""
  start_sec 10
  if [ "$HURTIG" -eq 1 ]; then add_result SKIP "Hele seksjonen" "hoppet over (--hurtig)"; return 0; fi
  if ! have curl; then skip_tool "HLS-teststrøm" curl; return 0; fi
  if hls_test "$URL_HLS1"; then kilde="mux.dev"; elif hls_test "$URL_HLS2"; then kilde="apple.com (reserve)"; fi
  if [ -n "$kilde" ]; then
    st=$(grade_ge "$HLS_MEAN" 25 8)
    add_result "$st" "HLS segment-gjennomstrømning ($kilde, $HLS_N segmenter, variant $(mbit_bps "$HLS_BW") Mbit/s)" "snitt $HLS_MEAN Mbit/s, laveste $HLS_MIN Mbit/s" "PASS ≥25 Mbit/s (4K), WARN ≥8 Mbit/s (1080p), FAIL <8 Mbit/s"
    if [ "$HLS_RATIO" != "-" ] && gt "$HLS_RATIO" 3; then
      add_result WARN "HLS maks/median hentetid" "$HLS_RATIO — ujevn levering, risiko for stalling" "≤3"
    else
      add_result PASS "HLS maks/median hentetid" "$HLS_RATIO" "≤3"
    fi
  else
    add_result FAIL "HLS-teststrøm" "kunne ikke hente/måle segmenter fra verken mux.dev eller apple.com (curl rc=$RC, $HLS_N segmenter)" "PASS ≥25 Mbit/s"
  fi
  for host in $MAAL_VIDEO; do
    if curl_tid "https://$host/"; then add_result INFO "TCP connect + TLS $host" "connect $CURL_CONNECT_MS ms, TLS $CURL_TLS_MS ms (HTTP $CURL_CODE)"
    else add_result INFO "TCP connect + TLS $host" "nås ikke (curl rc=$RC)"; fi
  done
  if curl --version 2>/dev/null | grep -qi 'HTTP3'; then
    cap 15 curl --http3-only -sS -o /dev/null --max-time 10 -w "${NL}NETT %{http_version} %{http_code}" https://cloudflare-quic.com/
    if [ "$RC" -eq 0 ]; then add_result INFO "QUIC / HTTP/3 (cloudflare-quic.com)" "fungerer: HTTP-versjon $(printf '%s\n' "$OUT" | awk '$1=="NETT"{print $2}' | tail -n 1) — UDP 443 slipper gjennom"
    else add_result INFO "QUIC / HTTP/3 (cloudflare-quic.com)" "feilet (UDP 443 blokkert?) rc=$RC"; fi
  else
    add_result INFO "QUIC / HTTP/3" "ikke testbart uten HTTP/3-klient (curl mangler HTTP3-støtte)"
  fi
  return 0
}

# ### 17. Seksjon 11 Roaming ----------------------------------------------------

sek11_roaming() {
  local kand="" sticky="" l b s c r band sec n=0
  start_sec 11
  if [ "$IS_WIFI" -eq 0 ]; then add_result INFO "Roaming" "ikke aktuelt — kablet/ukjent lenke"; return 0; fi
  add_result INFO "Øyeblikksbilde" "SSID ${SSID:-?}, BSSID ${BSSID:-?}, ${BAND:-?} kanal ${CHANNEL:-?}, RSSI ${RSSI:-?} dBm"
  if [ ! -s "$NABOER" ] || [ -z "$SSID" ]; then
    add_result SKIP "BSSID-er på samme SSID" "ingen skanneliste tilgjengelig (se seksjon 1)"
  else
    while IFS="$TAB" read -r b s c r band sec; do
      [ "$s" = "$SSID" ] || continue
      [ "$(printf '%s' "$b" | tr 'A-F' 'a-f')" = "$(printf '%s' "$BSSID" | tr 'A-F' 'a-f')" ] && continue
      n=$((n + 1))
      add_result INFO "Samme SSID: $b" "kanal $c, $r dBm, $band, $sec"
      if er_tall "$r" && er_tall "${RSSI%% *}" && [ $(( ${RSSI%% *} - r )) -le 6 ] && [ $(( r - ${RSSI%% *} )) -le 6 ]; then kand="$kand $b($r dBm)"; fi
      if [ "$BAND" = "2.4 GHz" ] && [ "$band" != "2.4 GHz" ] && er_tall "$r" && [ "$r" -ge -70 ]; then sticky="$sticky $b($band, $r dBm)"; fi
    done < "$NABOER"
    [ "$n" -eq 0 ] && add_result INFO "BSSID-er på samme SSID" "ingen andre sett i skannet — klienten har bare ett AP å velge"
    [ -n "$kand" ] && add_result INFO "Roaming-kandidat (innen 6 dB)" "$kand — klienten kan bytte AP når som helst"
    if [ -n "$sticky" ]; then add_result WARN "Sticky på 2,4 GHz / band steering" "klienten står på 2,4 GHz mens 5/6 GHz-BSSID på samme SSID er ≥ -70 dBm:$sticky" "5/6 GHz"
    elif [ "$BAND" = "2.4 GHz" ]; then add_result INFO "Band steering" "på 2,4 GHz, men ingen sterk 5/6 GHz-BSSID på samme SSID sett"
    else add_result PASS "Band steering" "klienten er på $BAND" "5/6 GHz"; fi
  fi
  add_result INFO "Gå-test" "for roaming under bevegelse: kjør roaming-logg.sh (logger BSSID/RSSI/kanal fortløpende mens du går mellom AP-ene)"
  return 0
}

# ### 18. Seksjon 12 Hygiene ----------------------------------------------------

sek12_hygiene() {
  local t0 t1 dato srv lokal drift st url ntp="" l vpn="" fw n ll
  start_sec 12
  # Klokke vs HTTP Date
  if have curl; then
    srv=""
    for url in "https://1.1.1.1" "https://www.cloudflare.com" "https://www.google.com"; do
      t0=$(date +%s)
      cap 12 curl -sI --max-time 8 "$url"
      t1=$(date +%s)
      dato=$(printf '%s\n' "$OUT" | tr -d "$CR" | awk 'tolower($1)=="date:" { $1=""; sub(/^ /,""); print; exit }')
      [ -n "$dato" ] && srv=$(http_date_to_epoch "$dato")
      [ -n "$srv" ] && break
    done
    if er_tall "$srv"; then
      lokal=$(( (t0 + t1) / 2 ))
      drift=$(( lokal - srv )); [ "$drift" -lt 0 ] && drift=$(( -drift ))
      if [ "$drift" -le 1 ]; then st=PASS; elif [ "$drift" -lt 5 ]; then st=WARN; else st=FAIL; fi
      add_result "$st" "Klokkeavvik mot HTTP Date ($url)" "$drift s (oppløsning 1 s)" "PASS <1 s, WARN <5 s, FAIL ≥5 s"
    else
      add_result SKIP "Klokkeavvik mot HTTP Date" "fikk ingen Date-header"
    fi
  else
    skip_tool "Klokkeavvik mot HTTP Date" curl
  fi
  case "$PLATFORM" in
    darwin) cap 10 systemsetup -getusingnetworktime; case "$OUT" in *On*) ntp="på";; *Off*) ntp="av";; esac
            [ -z "$ntp" ] && { cap 10 sntp -d 2>/dev/null; ntp=""; } ;;
    termux) ntp="" ;;
    *) if have timedatectl; then cap 10 timedatectl show -p NTPSynchronized --value; case "$OUT" in yes) ntp="synkronisert";; no) ntp="ikke synkronisert";; esac; fi
       if [ -z "$ntp" ] && have chronyc; then cap 10 chronyc tracking; printf '%s' "$OUT" | grep -q 'Leap status *: Normal' && ntp="synkronisert (chrony)"; fi ;;
  esac
  case "$ntp" in
    "på"|synkronisert*) add_result PASS "NTP-synkronisering" "$ntp" "synkronisert" ;;
    "av"|"ikke synkronisert") add_result FAIL "NTP-synkronisering" "$ntp" "synkronisert" ;;
    *) add_result INFO "NTP-synkronisering" "status ikke lesbar (timedatectl/chronyc/systemsetup svarte ikke, eller Android) — klokkeavviket over er den reelle testen" ;;
  esac
  # Captive portal
  if have curl; then
    cap 12 curl -sS -o /dev/null --max-time 8 -w "${NL}NETT %{http_code}" "$URL_PORTAL1"
    l=$(printf '%s\n' "$OUT" | awk '$1=="NETT"{print $2}' | tail -n 1)
    if [ "$l" = "204" ]; then add_result PASS "Captive portal (gstatic generate_204)" "HTTP 204" "204"
    else add_result FAIL "Captive portal (gstatic generate_204)" "HTTP ${l:-000} — portal/proxy/DNS-kapring?" "204"; fi
    cap 12 curl -sS -o "$TMPD/portal2.html" --max-time 8 -w "${NL}NETT %{http_code}" "$URL_PORTAL2"
    l=$(printf '%s\n' "$OUT" | awk '$1=="NETT"{print $2}' | tail -n 1)
    if [ "$l" = "200" ] && grep -q 'Success' "$TMPD/portal2.html" 2>/dev/null; then add_result PASS "Captive portal (captive.apple.com)" "HTTP 200 med 'Success'" "200 + Success"
    else add_result FAIL "Captive portal (captive.apple.com)" "HTTP ${l:-000}$(grep -q Success "$TMPD/portal2.html" 2>/dev/null || printf ' uten Success') — portal/proxy/DNS-kapring?" "200 + Success"; fi
  else
    skip_tool "Captive portal" curl
  fi
  # Proxy-variabler
  if [ "$PROXY_AKTIV" -eq 1 ]; then
    add_result WARN "Proxy-miljøvariabler" "http_proxy/https_proxy/ALL_PROXY er satt — alle HTTP-målinger gikk via proxy"
  else
    add_result INFO "Proxy-miljøvariabler" "ingen satt"
  fi
  # VPN
  case "$PLATFORM" in
    darwin)
      cap 10 ifconfig
      vpn=$(printf '%s\n' "$OUT" | awk '/^(utun|ipsec|ppp|tun|tap)[0-9]*:/ { i=$1; sub(/:$/,"",i) } /inet / && i!="" { printf "%s(%s) ", i, $2; i="" }')
      case "$IFACE" in utun*|ipsec*|ppp*) vpn="default-ruten går via $IFACE! $vpn" ;; esac ;;
    *)
      for l in /sys/class/net/*; do
        ll=${l##*/}
        case "$ll" in tun*|tap*|wg*|tailscale*|proton*|nordlynx*|ppp*|ipsec*|zt*)
          [ "$(cat "$l/operstate" 2>/dev/null)" = "down" ] || vpn="$vpn $ll" ;;
        esac
      done
      case "$IFACE" in tun*|tap*|wg*|tailscale*|proton*|nordlynx*|ppp*) vpn="default-ruten går via $IFACE!$vpn" ;; esac ;;
  esac
  if [ -n "$vpn" ]; then add_result WARN "VPN aktiv" "$vpn — målingene går (helt eller delvis) gjennom VPN" "ingen VPN"
  else add_result PASS "VPN aktiv" "ingen VPN-grensesnitt oppe" "ingen VPN"; fi
  # mDNS / Bonjour
  if have dns-sd; then
    cap 5 dns-sd -B _services._dns-sd._udp local.
    n=$(printf '%s\n' "$OUT" | grep -c ' Add ')
    add_result INFO "mDNS/Bonjour (dns-sd)" "$n tjenestetyper annonsert lokalt på 4 s"
  elif have avahi-browse; then
    cap 12 avahi-browse -t -a
    n=$(printf '%s\n' "$OUT" | grep -c '^+')
    add_result INFO "mDNS/Bonjour (avahi-browse)" "$n tjenester funnet"
  else
    add_result INFO "mDNS/Bonjour" "ikke testbart (mangler dns-sd/avahi-browse: $(inst_hint avahi-browse))"
  fi
  # IPv6 RA / global
  if [ -n "$IPV6_GLOBAL" ]; then add_result INFO "IPv6 RA / global adresse" "global IPv6 finnes: $IPV6_GLOBAL (default via ${IPV6_DEFAULT:-ingen})"
  else add_result INFO "IPv6 RA / global adresse" "ingen global IPv6-adresse (kun IPv4 / RA ikke mottatt)"; fi
  # Vertsbrannmur
  fw=""
  case "$PLATFORM" in
    darwin) cap 10 /usr/libexec/ApplicationFirewall/socketfilterfw --getglobalstate; fw=$(printf '%s' "$OUT" | head -n 1) ;;
    termux) fw="ikke lesbar på Android" ;;
    *)
      if have ufw; then cap 10 ufw status; case "$OUT" in *active*|*Status*) fw="ufw: $(printf '%s' "$OUT" | head -n 1)";; *) fw="ufw: krever root for status";; esac; fi
      if have nft; then cap 10 nft list ruleset; [ "$RC" -eq 0 ] && fw="$fw${fw:+; }nft: $(printf '%s\n' "$OUT" | wc -l | tr -d ' ') linjer regelsett"; fi
      [ -z "$fw" ] && have iptables && { cap 10 iptables -S; [ "$RC" -eq 0 ] && fw="iptables: $(printf '%s\n' "$OUT" | wc -l | tr -d ' ') regler"; }
      [ -z "$fw" ] && fw="ukjent (ufw/nft/iptables krever root eller mangler)" ;;
  esac
  add_result INFO "Vertsbrannmur" "$fw"
  # 169.254 på noe grensesnitt
  ll=""
  case "$PLATFORM" in
    darwin) cap 10 ifconfig; ll=$(printf '%s\n' "$OUT" | awk '/^[a-z0-9]+:/ { i=$1; sub(/:$/,"",i) } /inet 169\.254\./ { printf "%s(%s) ", i, $2 }') ;;
    *) if have ip; then cap 10 ip -o -4 addr; ll=$(printf '%s\n' "$OUT" | awk '$4 ~ /^169\.254\./ { printf "%s(%s) ", $2, $4 }')
       elif have hostname; then cap 5 hostname -I; ll=$(printf '%s\n' "$OUT" | tr ' ' "$NL" | grep '^169\.254\.' | tr "$NL" ' '); fi ;;
  esac
  if [ -n "$ll" ]; then add_result FAIL "Link-lokale adresser (169.254)" "$ll — DHCP feilet på disse" "ingen"
  else add_result PASS "Link-lokale adresser (169.254)" "ingen" "ingen"; fi
  if [ "$N_DEFAULT_ROUTES" -gt 1 ]; then add_result WARN "Flere default-ruter" "$N_DEFAULT_ROUTES" "1"; else add_result PASS "Flere default-ruter" "nei ($N_DEFAULT_ROUTES)" "1"; fi
  add_result INFO "DoH i nettlesere" "kan ikke oppdages her: nettlesere med DNS-over-HTTPS (Chrome/Firefox/Edge «sikker DNS») går utenom lokal DNS og interne navn — slå av for Adm-nett ved feilsøking"
  return 0
}

# ### 19. Rapportskriving (Markdown og JSON) ----------------------------------

json_esc() {
  local s="${1:-}"
  s=${s//\\/\\\\}; s=${s//\"/\\\"}; s=${s//$TAB/\\t}; s=${s//$NL/\\n}; s=${s//$CR/\\r}
  printf '%s' "$s"
}

skriv_meta_tsv() {
  {
    printf 'verktoy\t%s\nversjon\t%s\nhost\t%s\nos\t%s\ntid\t%s\n' "$VERKTOY" "$VERSJON" "$HOSTNAVN" "$OS_BESKRIVELSE" "$(date '+%Y-%m-%d %H:%M:%S %z')"
    printf 'param.rapportmappe\t%s\nparam.hurtig\t%s\nparam.forventet_ned\t%s\nparam.forventet_opp\t%s\n' "$RAPPORTMAPPE" "$HURTIG" "$FORVENTET_NED" "$FORVENTET_OPP"
    printf 'param.iperf_server\t%s\nparam.interne_navn\t%s\nparam.gateway\t%s\nparam.grensesnitt\t%s\nparam.ingen_farger\t%s\n' "$IPERF_SERVER" "$INTERNE_NAVN" "$GATEWAY" "$IFACE" "$INGEN_FARGER"
    printf 'plattform\t%s\nskript\t%s\n' "$PLATFORM" "$SKRIPTNAVN"
  } > "$TMPD/meta.tsv"
}

skriv_resultat_tsv() {
  : > "$TMPD/resultater.tsv"
  local l
  for l in ${RESULTS[@]+"${RESULTS[@]}"}; do printf '%s\n' "$l"; done > "$TMPD/resultater.tsv"
}

skriv_json() {
  local l first=1 k v
  skriv_meta_tsv
  skriv_resultat_tsv
  if have python3 && python3 "$TMPD/json.py" "$TMPD/resultater.tsv" "$TMPD/meta.tsv" "$RAPPORT_JSON" 2>/dev/null; then
    return 0
  fi
  {
    printf '{\n "meta": {'
    first=1
    while IFS= read -r l; do
      k=${l%%"$TAB"*}; v=${l#*"$TAB"}
      case "$k" in param.*) continue ;; esac
      [ "$first" -eq 1 ] || printf ','
      first=0
      printf '\n  "%s": "%s"' "$(json_esc "$k")" "$(json_esc "$v")"
    done < "$TMPD/meta.tsv"
    printf ',\n  "parametre": {'
    first=1
    while IFS= read -r l; do
      k=${l%%"$TAB"*}; v=${l#*"$TAB"}
      case "$k" in param.*) ;; *) continue ;; esac
      [ "$first" -eq 1 ] || printf ','
      first=0
      printf '\n   "%s": "%s"' "$(json_esc "${k#param.}")" "$(json_esc "$v")"
    done < "$TMPD/meta.tsv"
    printf '\n  }\n },\n "resultater": ['
    first=1
    while IFS= read -r l; do
      split_result "$l"
      [ "$first" -eq 1 ] || printf ','
      first=0
      printf '\n  {"seksjon": "%s", "sjekk": "%s", "status": "%s", "verdi": "%s", "terskel": "%s", "detaljer": "%s"}' \
        "$(json_esc "$R_SEK")" "$(json_esc "$R_SJEKK")" "$(json_esc "$R_STATUS")" "$(json_esc "$R_VERDI")" "$(json_esc "$R_TERSKEL")" "$(json_esc "$R_DET")"
    done < "$TMPD/resultater.tsv"
    printf '\n ],\n "oppsummering": {"pass": %d, "warn": %d, "fail": %d, "skip": %d, "info": %d}\n}\n' "$N_PASS" "$N_WARN" "$N_FAIL" "$N_SKIP" "$N_INFO"
  } > "$RAPPORT_JSON"
}

skriv_markdown() {
  local i navn l raw
  {
    printf '# nettsjekk-rapport — %s — %s\n\n' "$HOSTNAVN" "$(date '+%Y-%m-%d %H:%M:%S %z')"
    printf -- '- Verktøy: %s %s v%s (plattform %s)\n' "$VERKTOY" "$SKRIPTNAVN" "$VERSJON" "$PLATFORM"
    printf -- '- OS: %s\n' "$OS_BESKRIVELSE"
    printf -- '- Grensesnitt: %s (%s), IPv4 %s/%s, gateway %s, MTU %s\n' "${IFACE:-ukjent}" "$([ "$IS_WIFI" -eq 1 ] && printf 'Wi-Fi' || printf 'kablet/ukjent')" "${IPV4:-?}" "${PREFIX:-?}" "${GATEWAY:-ingen}" "$MTU"
    [ "$IS_WIFI" -eq 1 ] && printf -- '- Wi-Fi: SSID %s, BSSID %s, %s kanal %s, RSSI %s dBm\n' "${SSID:-?}" "${BSSID:-?}" "${BAND:-?}" "${CHANNEL:-?}" "${RSSI:-?}"
    printf -- '- Parametre: hurtig=%s forventet-ned=%s forventet-opp=%s iperf-server=%s interne-navn=%s\n' "$HURTIG" "$FORVENTET_NED" "$FORVENTET_OPP" "${IPERF_SERVER:-ingen}" "${INTERNE_NAVN:-ingen}"
    printf -- '- Endrer ingenting — kun lesing og målinger. Varighet: %s s\n' "$(( $(date +%s) - STARTTID ))"
    printf '\n## Oppsummering\n\nPASS %s · WARN %s · FAIL %s · SKIP %s · INFO %s\n\n' "$N_PASS" "$N_WARN" "$N_FAIL" "$N_SKIP" "$N_INFO"
    for l in ${RESULTS[@]+"${RESULTS[@]}"}; do
      split_result "$l"
      case "$R_STATUS" in FAIL|WARN) printf -- '- **[%s]** %s: %s — %s%s\n' "$R_STATUS" "$R_SEK" "$R_SJEKK" "$R_VERDI" "${R_TERSKEL:+ (terskel $R_TERSKEL)}" ;; esac
    done
    i=0
    while [ "$i" -lt 14 ]; do
      navn="${SEC_NAMES[$i]}"
      printf '\n## %s\n\n' "$navn"
      for l in ${RESULTS[@]+"${RESULTS[@]}"}; do
        split_result "$l"
        [ "$R_SEK" = "$navn" ] || continue
        printf -- '- **[%s]** %s' "$R_STATUS" "$R_SJEKK"
        [ -n "$R_VERDI" ] && printf -- ' — %s' "$R_VERDI"
        [ -n "$R_TERSKEL" ] && printf ' (terskel %s)' "$R_TERSKEL"
        [ -n "$R_DET" ] && printf ' — %s' "$R_DET"
        printf '\n'
      done
      raw="$TMPD/raw-$i.txt"
      if [ -s "$raw" ]; then
        printf '\n<details><summary>Rå utdata %s</summary>\n\n```text\n' "$navn"
        sed 's/```/` ` `/g' "$raw"
        printf '```\n\n</details>\n'
      fi
      i=$((i + 1))
    done
    printf '\n---\nLim inn innholdet i .md-filen i chatten for analyse.\n'
  } > "$RAPPORT_MD"
}

# ### 20. Seksjon 13 Oppsummering og main ------------------------------------

sek13_oppsummering() {
  local l antall_fw=0
  start_sec 13
  add_result INFO "Antall" "PASS $N_PASS, WARN $N_WARN, FAIL $N_FAIL, SKIP $N_SKIP, INFO $N_INFO"
  add_result INFO "Varighet" "$(( $(date +%s) - STARTTID )) s"
  for l in ${RESULTS[@]+"${RESULTS[@]}"}; do
    split_result "$l"
    case "$R_STATUS" in
      FAIL|WARN) [ "$R_SEK" = "${SEC_NAMES[13]}" ] && continue
                 antall_fw=$((antall_fw + 1))
                 printf '  %s[%s]%s %s: %s — %s\n' "$([ "$R_STATUS" = FAIL ] && printf '%s' "$C_RED" || printf '%s' "$C_YELLOW")" "$R_STATUS" "$C_RESET" "$R_SEK" "$R_SJEKK" "$R_VERDI" ;;
    esac
  done
  [ "$antall_fw" -eq 0 ] && add_result PASS "Avvik" "ingen FAIL eller WARN"
  skriv_markdown
  skriv_json
  add_result INFO "Rapport (Markdown)" "$RAPPORT_MD"
  add_result INFO "Rapport (JSON)" "$RAPPORT_JSON"
  # Rapportfilene skrives på nytt slik at også disse linjene er med
  skriv_markdown
  skriv_json
  printf '\n%sLim inn innholdet i .md-filen i chatten for analyse%s\n' "$C_BOLD" "$C_RESET"
  return 0
}

main() {
  parse_args "$@"
  trap cleanup EXIT
  trap 'cleanup; exit 130' INT TERM
  init
  sek0_system
  sek1_lenke
  sek2_ip
  sek3_dhcp
  sek4_dns
  sek5_gateway
  sek6_wan
  sek7_tcp
  sek8_hastighet
  sek7_etter
  sek9_bufferbloat
  sek10_video
  sek11_roaming
  sek12_hygiene
  sek13_oppsummering
  exit 0
}

main "$@"
