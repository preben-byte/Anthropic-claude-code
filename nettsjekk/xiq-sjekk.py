#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
xiq-sjekk.py — AP ↔ klient-helsesjekk for Marivold Camping via ExtremeCloud IQ (XIQ) REST-API

Formål:
    Leser status for aksesspunkter (AP305C/AP305CX/AP460C/Atom AP30), radioer og kanaler,
    aktive Wi-Fi-klienter (inkl. din egen telefon), roaming-historikk og varsler fra
    XIQ-skyen (https://api.extremecloudiq.com). Kan kjøres fra hvor som helst med internett —
    trenger ikke tilgang til LAN-et. Fiber, brannmur og svitsjer er utenfor omfanget.

Bruk (eksempler):
    export XIQ_TOKEN='...'                     # API-token fra XIQ (Global Settings → API Token Management)
    python3 xiq-sjekk.py
    python3 xiq-sjekk.py --token-fil ~/.xiq-token --klient "AA:BB:CC:DD:EE:FF"
    python3 xiq-sjekk.py --bruker preben@example.no --klient iphone --rapportmappe ./rapporter
    python3 xiq-sjekk.py --cli --cli-kommandoer "show version;show capwap client"   # kun 'show'-kommandoer
    python3 xiq-sjekk.py --hjelp

Skriver 'xiq-rapport-<YYYYMMDD-HHMMSS>.md' og '.json' til --rapportmappe (standard: gjeldende mappe).
Lim inn innholdet i .md-filen i chatten for analyse.

Versjon 1.0 — 2026-09-09
Endrer ingenting — kun lesing.
(Eneste POST-kall: /login ved passordinnlogging, og /devices/:cli med --cli der hver kommando må begynne med 'show '.)
"""

import argparse
import getpass
import json
import os
import re
import socket
import ssl
import statistics
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from datetime import datetime, timezone, timedelta

VERKTOY = "xiq-sjekk"
VERSJON = "1.0"
STANDARD_BASE_URL = "https://api.extremecloudiq.com"
TIDSAVBRUDD = 20          # sekunder per HTTP-kall
CLI_TIDSAVBRUDD = 90      # sekunder for CLI-kall (LRO)
PAUSE_VED_RETRY = 2.0
STANDARD_CLI = ["show version", "show capwap client", "show acsp", "show station", "show roaming cache"]

SEK0 = "0 Konto og token"
SEK1 = "1 AP-oversikt"
SEK2 = "2 Radioer og kanaler"
SEK3 = "3 Klienter"
SEK4 = "4 Din klient"
SEK5 = "5 Varsler"
SEK6 = "6 CLI"
SEK7 = "7 Oppsummering"

UKJENT = "ukjent"


# --------------------------------------------------------------------------------------
# Hjelpefunksjoner
# --------------------------------------------------------------------------------------

class Farger:
    def __init__(self, aktiv):
        self.aktiv = aktiv
        self.koder = {
            "PASS": "\033[32m", "WARN": "\033[33m", "FAIL": "\033[31m",
            "INFO": "\033[36m", "SKIP": "\033[90m", "HEAD": "\033[1m", "RESET": "\033[0m",
        }

    def f(self, status, tekst):
        if not self.aktiv:
            return tekst
        return self.koder.get(status, "") + tekst + self.koder["RESET"]


def na():
    return datetime.now(timezone.utc)


def ms(dt):
    return int(dt.timestamp() * 1000)


def parse_tid(v):
    """ISO 8601-streng eller epoch (sekunder/millisekunder) -> tidssone-bevisst datetime, ellers None."""
    if v in (None, "", 0, "0"):
        return None
    try:
        if isinstance(v, bool):
            return None
        if isinstance(v, (int, float)):
            x = float(v)
            if x <= 0:
                return None
            if x > 1e11:
                x /= 1000.0
            return datetime.fromtimestamp(x, tz=timezone.utc)
        s = str(v).strip()
        if re.fullmatch(r"\d{9,}", s):
            return parse_tid(int(s))
        if s.endswith("Z"):
            s = s[:-1] + "+00:00"
        m = re.match(r"^(\d{4}-\d{2}-\d{2})[T ](\d{2}:\d{2}:\d{2})(\.\d+)?(.*)$", s)
        if m:
            frac = (m.group(3) or "")[:7]
            s = m.group(1) + "T" + m.group(2) + frac + m.group(4)
        dt = datetime.fromisoformat(s)
        if dt.tzinfo is None:
            dt = dt.replace(tzinfo=timezone.utc)
        return dt
    except Exception:
        return None


def fmt_tid(v):
    dt = v if isinstance(v, datetime) else parse_tid(v)
    if dt is None:
        return UKJENT
    try:
        return dt.astimezone().strftime("%Y-%m-%d %H:%M")
    except Exception:
        return dt.strftime("%Y-%m-%d %H:%M")


def fmt_varighet(sek):
    if sek is None:
        return UKJENT
    try:
        sek = int(sek)
    except Exception:
        return UKJENT
    if sek < 0:
        sek = 0
    d, rest = divmod(sek, 86400)
    t, rest = divmod(rest, 3600)
    m = rest // 60
    if d:
        return "%d d %d t %d min" % (d, t, m)
    if t:
        return "%d t %d min" % (t, m)
    return "%d min" % m


def tall(v, standard=None):
    """Konverter til tall om mulig, ellers standard."""
    if v is None or isinstance(v, bool):
        return standard
    try:
        if isinstance(v, str):
            v = v.strip().replace(",", ".")
            if v == "":
                return standard
        return float(v)
    except Exception:
        return standard


def heltall(v, standard=None):
    x = tall(v, None)
    return standard if x is None else int(round(x))


def s(v):
    """Trygg streng for tabeller."""
    if v is None or v == "":
        return UKJENT
    if isinstance(v, bool):
        return "ja" if v else "nei"
    if isinstance(v, float):
        return ("%.1f" % v).replace(".", ",")
    return str(v).replace("|", "\\|").replace("\n", " ")


def norm_mac(m):
    if not m:
        return ""
    return re.sub(r"[^0-9a-f]", "", str(m).lower())


def pen_mac(m):
    n = norm_mac(m)
    if len(n) != 12:
        return s(m)
    return ":".join(n[i:i + 2] for i in range(0, 12, 2)).upper()


def band_fra_tekst(t):
    """'2.4GHz' / '5GHz' / '6GHz' / '_11ax_2g' / 'wifi0' -> '2,4 GHz' | '5 GHz' | '6 GHz' | None."""
    if t is None:
        return None
    x = str(t).lower().replace(" ", "").replace(",", ".")
    if "2.4" in x or x.endswith("2g") or "_2g" in x or x in ("11bg", "_11bg", "_11ng", "11ng"):
        return "2,4 GHz"
    if "6g" in x or x.startswith("6"):
        return "6 GHz"
    if "5g" in x or x.startswith("5") or x in ("_11a", "_11an", "_11ac"):
        return "5 GHz"
    return None


def band_fra_kanal(k):
    k = heltall(k)
    if k is None:
        return None
    if 1 <= k <= 14:
        return "2,4 GHz"
    if 32 <= k <= 177:
        return "5 GHz"
    return None


def band_fra_radio_type(rt):
    return {1: "2,4 GHz", 2: "5 GHz", 3: "kablet", 4: "6 GHz", 5: "Thread"}.get(heltall(rt))


def kanalbredde(v):
    """'MHZ_40' / 40 -> 40"""
    if v is None:
        return None
    if isinstance(v, (int, float)):
        return int(v)
    m = re.search(r"(\d+)", str(v))
    return int(m.group(1)) if m else None


def json_utdrag(obj, maks=2500):
    try:
        t = json.dumps(obj, ensure_ascii=False, indent=1, default=str)
    except Exception:
        t = str(obj)
    if len(t) > maks:
        t = t[:maks] + "\n… (avkortet, %d tegn totalt)" % len(t)
    return t


def md_tabell(kolonner, rader):
    if not rader:
        return "_(ingen rader)_\n"
    ut = ["| " + " | ".join(kolonner) + " |", "|" + "|".join(["---"] * len(kolonner)) + "|"]
    for r in rader:
        ut.append("| " + " | ".join(s(c) for c in r) + " |")
    return "\n".join(ut) + "\n"


AUTH_KODER = {-1: "N/A", 0: "CWP", 1: "OPEN", 2: "WEP-OPEN", 3: "WEP-SHARED", 4: "WPA-PSK", 5: "WPA2-PSK",
              6: "WPA-802.1X", 7: "WPA2-802.1X", 8: "WPA-AUTO-PSK", 9: "WPA-AUTO-802.1X", 10: "DYNAMIC-WEP",
              11: "802.1X", 12: "WPA3-SAE", 13: "WPA3-802.1X", 14: "OWE", 15: "THREAD-PSKD", 16: "MAC",
              17: "WPA3-SAE-EXT", 18: "WPA3-802.1X-SUITEB"}


# --------------------------------------------------------------------------------------
# Resultatsamler og rapport
# --------------------------------------------------------------------------------------

class Rapport:
    def __init__(self, farger):
        self.farger = farger
        self.resultater = []
        self.tillegg = {}       # seksjon -> liste av markdown-biter
        self.seksjonsrekkefolge = []
        self.api_kall = []

    def seksjon(self, navn):
        if navn not in self.seksjonsrekkefolge:
            self.seksjonsrekkefolge.append(navn)
        print()
        print(self.farger.f("HEAD", "== %s ==" % navn))

    def legg(self, seksjon, sjekk, status, verdi="", terskel="", detaljer=""):
        if seksjon not in self.seksjonsrekkefolge:
            self.seksjonsrekkefolge.append(seksjon)
        status = status.upper()
        r = {"seksjon": seksjon, "sjekk": sjekk, "status": status,
             "verdi": "" if verdi is None else str(verdi),
             "terskel": "" if terskel is None else str(terskel),
             "detaljer": "" if detaljer is None else str(detaljer)}
        self.resultater.append(r)
        linje = "[%s] %s: %s" % (status, seksjon, sjekk)
        if r["verdi"]:
            linje += " — " + r["verdi"]
        if r["terskel"]:
            linje += " (terskel %s)" % r["terskel"]
        print(self.farger.f(status, linje))
        return r

    def md(self, seksjon, tekst):
        if seksjon not in self.seksjonsrekkefolge:
            self.seksjonsrekkefolge.append(seksjon)
        self.tillegg.setdefault(seksjon, []).append(tekst)

    def oppsummering(self):
        o = {"pass": 0, "warn": 0, "fail": 0, "skip": 0, "info": 0}
        for r in self.resultater:
            k = r["status"].lower()
            if k in o:
                o[k] += 1
        return o

    def skriv(self, mappe, parametre, tidsstempel):
        os.makedirs(mappe, exist_ok=True)
        stamme = os.path.join(mappe, "xiq-rapport-%s" % tidsstempel)
        json_sti = stamme + ".json"
        md_sti = stamme + ".md"
        data = {
            "meta": {"verktoy": VERKTOY, "versjon": VERSJON, "tid": na().astimezone().isoformat(timespec="seconds"),
                     "parametre": parametre},
            "resultater": self.resultater,
            "oppsummering": self.oppsummering(),
        }
        with open(json_sti, "w", encoding="utf-8") as f:
            json.dump(data, f, ensure_ascii=False, indent=1)
        with open(md_sti, "w", encoding="utf-8") as f:
            f.write(self.til_markdown(parametre))
        return md_sti, json_sti

    def til_markdown(self, parametre):
        o = self.oppsummering()
        ut = []
        ut.append("# XIQ-sjekk — Marivold Camping (AP ↔ klient)\n")
        ut.append("- Verktøy: %s %s  \n- Tid: %s  \n- Base-URL: %s  \n- Parametre: `%s`\n" % (
            VERKTOY, VERSJON, na().astimezone().strftime("%Y-%m-%d %H:%M:%S %Z"),
            parametre.get("base_url", ""), json.dumps(parametre, ensure_ascii=False)))
        ut.append("**Oppsummering:** PASS %d · WARN %d · FAIL %d · INFO %d · SKIP %d\n" % (
            o["pass"], o["warn"], o["fail"], o["info"], o["skip"]))
        for sek in self.seksjonsrekkefolge:
            ut.append("\n## %s\n" % sek)
            linjer = [r for r in self.resultater if r["seksjon"] == sek]
            if not linjer and not self.tillegg.get(sek):
                ut.append("_(ingen resultater — kjøringen ble avbrutt før seksjonen var ferdig)_\n")
            if linjer:
                ut.append("```text")
                for r in linjer:
                    l = "[%s] %s" % (r["status"], r["sjekk"])
                    if r["verdi"]:
                        l += " — " + r["verdi"]
                    if r["terskel"]:
                        l += " (terskel %s)" % r["terskel"]
                    if r["detaljer"]:
                        l += "  · " + r["detaljer"]
                    ut.append(l)
                ut.append("```\n")
            for bit in self.tillegg.get(sek, []):
                ut.append(bit)
                if not bit.endswith("\n"):
                    ut.append("\n")
        if self.api_kall:
            ut.append("\n## API-kall (kun lesing)\n")
            telling = {}
            for m, p, st in self.api_kall:
                n = "%s %s" % (m, p)
                telling.setdefault(n, [0, set()])
                telling[n][0] += 1
                telling[n][1].add(str(st))
            ut.append(md_tabell(["Kall", "Antall", "HTTP-status"],
                                [[k, v[0], ", ".join(sorted(v[1]))] for k, v in sorted(telling.items())]))
        return "\n".join(ut) + "\n"


# --------------------------------------------------------------------------------------
# HTTP-klient mot XIQ
# --------------------------------------------------------------------------------------

class ApiFeil(Exception):
    def __init__(self, melding, status=None, kropp=None):
        super().__init__(melding)
        self.status = status
        self.kropp = kropp


class AuthFeil(ApiFeil):
    pass


class XiqApi:
    def __init__(self, base_url, token=None, rapport=None):
        self.base_url = base_url.rstrip("/")
        self.token = token
        self.rapport = rapport
        self.ssl_ctx = ssl.create_default_context()

    @staticmethod
    def _qs(params):
        deler = []
        for k, v in (params or {}).items():
            if v is None:
                continue
            verdier = v if isinstance(v, (list, tuple, set)) else [v]
            for x in verdier:
                if isinstance(x, bool):
                    x = "true" if x else "false"
                deler.append((k, str(x)))
        return urllib.parse.urlencode(deler)

    @staticmethod
    def _mal(path):
        return re.sub(r"/\d{4,}", "/{id}", re.sub(r"/[0-9A-Fa-f]{12}(?=/|$)", "/{mac}", path))

    def _logg(self, method, path, status):
        if self.rapport is not None:
            self.rapport.api_kall.append((method, self._mal(path), status))

    def kall(self, method, path, params=None, body=None, timeout=TIDSAVBRUDD, _forsok=0):
        """Returnerer (status, json_eller_tekst, headers). Kaster AuthFeil/ApiFeil."""
        url = self.base_url + path
        qs = self._qs(params)
        if qs:
            url += "?" + qs
        data = json.dumps(body).encode("utf-8") if body is not None else None
        headers = {"Accept": "application/json", "User-Agent": "%s/%s" % (VERKTOY, VERSJON)}
        if data is not None:
            headers["Content-Type"] = "application/json"
        if self.token:
            headers["Authorization"] = "Bearer " + self.token
        req = urllib.request.Request(url, data=data, method=method, headers=headers)
        try:
            with urllib.request.urlopen(req, timeout=timeout, context=self.ssl_ctx) as resp:
                status, raa, hdr = resp.status, resp.read(), resp.headers
        except urllib.error.HTTPError as e:
            status, hdr = e.code, e.headers
            try:
                raa = e.read()
            except Exception:
                raa = b""
        except (urllib.error.URLError, socket.timeout, ssl.SSLError, ConnectionError, OSError) as e:
            self._logg(method, path, "nettfeil")
            if _forsok == 0:
                time.sleep(PAUSE_VED_RETRY)
                return self.kall(method, path, params, body, timeout, _forsok=1)
            raise ApiFeil("nettverksfeil mot %s: %s" % (self._mal(path), getattr(e, "reason", e)))
        self._logg(method, path, status)
        if (status == 429 or status >= 500) and _forsok == 0:
            time.sleep(PAUSE_VED_RETRY)
            return self.kall(method, path, params, body, timeout, _forsok=1)
        tekst = raa.decode("utf-8", "replace") if raa else ""
        obj = None
        if tekst:
            try:
                obj = json.loads(tekst)
            except ValueError:
                obj = tekst
        if status in (401, 403):
            raise AuthFeil("HTTP %d: token ugyldig/utløpt eller mangler rettigheter (%s)" % (
                status, self._feilmelding(obj)), status, obj)
        if status >= 400:
            raise ApiFeil("HTTP %d fra %s: %s" % (status, self._mal(path), self._feilmelding(obj)), status, obj)
        return status, obj, hdr

    @staticmethod
    def _feilmelding(obj):
        if isinstance(obj, dict):
            for k in ("error_message", "error_message_description", "message", "error"):
                if obj.get(k):
                    return str(obj[k])[:300]
            return json.dumps(obj, ensure_ascii=False)[:300]
        if isinstance(obj, str):
            return obj[:300]
        return "ingen feilmelding"

    def get(self, path, params=None, timeout=TIDSAVBRUDD):
        return self.kall("GET", path, params=params, timeout=timeout)[1]

    def hent_sider(self, path, params=None, maks=None, limit=100):
        """Paginerer 'page/limit' -> (liste, siste_svar)."""
        alle, side, svar = [], 1, {}
        while True:
            p = dict(params or {})
            p["page"], p["limit"] = side, limit
            svar = self.get(path, p)
            if not isinstance(svar, dict):
                break
            data = svar.get("data") or []
            alle.extend(data)
            total_sider = heltall(svar.get("total_pages"), 1) or 1
            if not data or side >= total_sider or (maks and len(alle) >= maks) or side > 200:
                break
            side += 1
        if maks:
            alle = alle[:maks]
        return alle, svar

    def logg_inn(self, bruker, passord):
        status, obj, _ = self.kall("POST", "/login", body={"username": bruker, "password": passord})
        if not isinstance(obj, dict) or not obj.get("access_token"):
            raise ApiFeil("innlogging ga ikke noe access_token (HTTP %s)" % status, status, obj)
        self.token = obj["access_token"]
        return heltall(obj.get("expires_in"))

    def vent_paa_operasjon(self, op_id, maks_sek=CLI_TIDSAVBRUDD):
        """LRO: poll GET /operations/{id} til done."""
        start = time.time()
        siste = None
        while time.time() - start < maks_sek:
            siste = self.get("/operations/%s" % op_id)
            if isinstance(siste, dict) and siste.get("done"):
                meta = siste.get("metadata") or {}
                if meta.get("status") in ("FAILED", "CANCELED") or siste.get("error"):
                    raise ApiFeil("LRO %s endte med %s: %s" % (
                        op_id, meta.get("status"), self._feilmelding(siste.get("error"))))
                return siste.get("response")
            time.sleep(3)
        raise ApiFeil("LRO %s ble ikke ferdig innen %d s" % (op_id, maks_sek))


# --------------------------------------------------------------------------------------
# Terskler
# --------------------------------------------------------------------------------------

def vurder_rssi(r):
    if r is None:
        return "INFO"
    return "PASS" if r >= -65 else ("WARN" if r >= -72 else "FAIL")


def vurder_snr(v):
    if v is None:
        return "INFO"
    return "PASS" if v >= 25 else ("WARN" if v >= 15 else "FAIL")


def vurder_utnyttelse(u):
    if u is None:
        return "INFO"
    return "PASS" if u < 50 else ("WARN" if u < 70 else "FAIL")


def vurder_stoygulv(n):
    if n is None:
        return "INFO"
    return "PASS" if n <= -90 else ("WARN" if n <= -85 else "FAIL")


# --------------------------------------------------------------------------------------
# Seksjoner
# --------------------------------------------------------------------------------------

def seksjon_konto(api, rap, auth_metode):
    rap.seksjon(SEK0)
    me = api.get("/users/me")          # port-vakt: 401/403 her er fatalt (AuthFeil bobler opp)
    if not isinstance(me, dict):
        me = {}
    navn = me.get("display_name") or " ".join(x for x in [me.get("first_name"), me.get("last_name")] if x) or UKJENT
    rap.legg(SEK0, "innlogget bruker", "PASS", "%s (%s), rolle %s" % (
        navn, me.get("login_name") or UKJENT, me.get("user_role") or UKJENT),
        "", "autentisering: %s; siste innlogging %s" % (auth_metode, fmt_tid(me.get("last_login_time"))))
    rap.md(SEK0, "**/users/me (utdrag)**\n```json\n%s\n```" % json_utdrag(
        {k: me.get(k) for k in ("id", "login_name", "display_name", "user_role", "last_login_time",
                                "access_scope", "viq_access_control", "org_id")}, 1200))

    if auth_metode != "innlogging (bruker/passord)":
        try:
            info = api.get("/auth/apitoken/info")
            if not isinstance(info, dict):
                info = {}
            utl = parse_tid(info.get("expiration_time"))
            rest = None
            if utl:
                rest = (utl - na()).total_seconds()
            elif info.get("expires_in") is not None:
                rest = tall(info.get("expires_in"))
            if rest is None:
                st, verdi = "INFO", "utløp ukjent"
            elif rest <= 0:
                st, verdi = "FAIL", "utløpt %s" % fmt_tid(utl)
            elif rest < 7 * 86400:
                st, verdi = "WARN", "utløper %s (om %s)" % (fmt_tid(utl) if utl else "?", fmt_varighet(rest))
            else:
                st, verdi = "PASS", "utløper %s (om %s)" % (fmt_tid(utl) if utl else "?", fmt_varighet(rest))
            scopes = info.get("scopes") or []
            rap.legg(SEK0, "API-token", st, verdi, "> 7 dager igjen",
                     "rolle %s, %d rettigheter (scopes), datasenter %s" % (
                         info.get("role") or UKJENT, len(scopes), info.get("data_center") or UKJENT))
            rap.md(SEK0, "**/auth/apitoken/info (utdrag)**\n```json\n%s\n```" % json_utdrag(
                {"role": info.get("role"), "issued_at": info.get("issued_at"),
                 "expiration_time": info.get("expiration_time"), "data_center": info.get("data_center"),
                 "scopes": scopes[:40]}, 1500))
        except AuthFeil as e:
            rap.legg(SEK0, "API-token", "INFO", "kunne ikke introspektere token", "", str(e))
        except ApiFeil as e:
            rap.legg(SEK0, "API-token", "INFO", "ikke et API-token (trolig innloggingstoken)", "", str(e))
    else:
        rap.legg(SEK0, "API-token", "INFO", "innloggingstoken fra /login (ingen token-introspeksjon)")

    try:
        viq = api.get("/account/viq")
        if not isinstance(viq, dict):
            viq = {}
        lis = viq.get("licenses") or []
        lis_tekst = "; ".join("%s %s (%s/%s enheter, utløper %s)" % (
            l.get("mode") or "?", l.get("status") or "?", l.get("activated", "?"), l.get("devices", "?"),
            fmt_tid(l.get("expire_date"))) for l in lis[:5]) or "ingen lisensdata"
        st = "WARN" if viq.get("expired") else "INFO"
        rap.legg(SEK0, "VIQ-konto", st, "vhm_id %s, %s lisensierte enheter, utløpt=%s" % (
            viq.get("vhm_id") or UKJENT, viq.get("devices", UKJENT), s(viq.get("expired"))), "", lis_tekst)
    except ApiFeil as e:
        rap.legg(SEK0, "VIQ-konto", "SKIP", "kunne ikke hentes", "", str(e))


def beregn_oppetid(enhet, naa):
    """system_up_time: epoch-ms for oppstart (>1e11) eller varighet i ms/s. Returnerer sekunder eller None."""
    v = tall(enhet.get("system_up_time"))
    if v is None or v <= 0:
        return None
    if v > 1e11:
        return max(0.0, naa.timestamp() - v / 1000.0)
    if v > 6.3e8:      # > 20 år i sekunder -> antakelig millisekunder
        return v / 1000.0
    return v


def seksjon_ap(api, rap):
    rap.seksjon(SEK1)
    naa = na()
    try:
        enheter, _ = api.hent_sider("/devices", {"views": ["FULL"], "deviceTypes": ["REAL"]}, maks=1000)
    except ApiFeil as e:
        rap.legg(SEK1, "hent enheter", "FAIL", "kunne ikke hente /devices", "", str(e))
        return []
    try:
        stats = api.get("/devices/stats")
        if isinstance(stats, dict):
            rap.legg(SEK1, "enhetsstatistikk", "INFO", "totalt %s, administrert %s, tilkoblet %s" % (
                stats.get("total_device_count", UKJENT), stats.get("managed_device_count", UKJENT),
                stats.get("connected_device_count", UKJENT)))
    except ApiFeil as e:
        rap.legg(SEK1, "enhetsstatistikk", "SKIP", "", "", str(e))

    aper = [d for d in enheter if isinstance(d, dict) and str(d.get("device_function") or "").upper() == "AP"]
    andre = [d for d in enheter if isinstance(d, dict) and d not in aper]
    rap.legg(SEK1, "antall aksesspunkter", "PASS" if aper else "FAIL", "%d AP (av %d enheter)" % (len(aper), len(enheter)),
             "≥ 1", "" if aper else "ingen enheter med device_function=AP — sjekk konto/tilgang")
    if andre:
        rap.legg(SEK1, "andre enheter (ikke AP)", "INFO", ", ".join(
            "%s (%s, %s)" % (d.get("hostname") or UKJENT, d.get("device_function") or "?",
                             "tilkoblet" if d.get("connected") else "frakoblet") for d in andre[:20]))

    rader = []
    versjoner = {}
    for d in sorted(aper, key=lambda x: str(x.get("hostname") or "")):
        navn = d.get("hostname") or ("id %s" % d.get("id"))
        tilk = bool(d.get("connected"))
        opp = beregn_oppetid(d, naa) if tilk else None
        lok = " / ".join(str(l.get("name")) for l in (d.get("locations") or []) if isinstance(l, dict) and l.get("name")) or UKJENT
        ver = d.get("software_version") or d.get("display_version") or UKJENT
        versjoner.setdefault(ver, []).append(navn)
        rader.append([navn, d.get("product_type"), d.get("serial_number"), d.get("ip_address"), pen_mac(d.get("mac_address")),
                      ver, "ja" if tilk else "NEI", fmt_varighet(opp) if opp is not None else UKJENT, lok,
                      d.get("network_policy_name"), d.get("active_clients"), fmt_tid(d.get("last_connect_time"))])
        rap.legg(SEK1, "%s tilkoblet" % navn, "PASS" if tilk else "FAIL", "ja" if tilk else "nei — AP er frakoblet fra XIQ",
                 "connected=true", "%s, %s, IP %s, siste tilkobling %s" % (
                     d.get("product_type") or UKJENT, d.get("serial_number") or UKJENT, d.get("ip_address") or UKJENT,
                     fmt_tid(d.get("last_connect_time"))))
        if tilk:
            if opp is None:
                rap.legg(SEK1, "%s oppetid" % navn, "INFO", UKJENT, "≥ 24 t", "system_up_time=%s" % d.get("system_up_time"))
            else:
                rap.legg(SEK1, "%s oppetid" % navn, "WARN" if opp < 86400 else "PASS", fmt_varighet(opp), "≥ 24 t",
                         "nylig omstart" if opp < 86400 else "")
        adm = str(d.get("device_admin_state") or UKJENT)
        rap.legg(SEK1, "%s admin-tilstand" % navn, "INFO" if adm == "MANAGED" else "WARN",
                 "%s, administrert av %s, konfig-avvik=%s" % (adm, d.get("managed_by") or UKJENT, s(d.get("config_mismatch"))),
                 "MANAGED", "nettverkspolicy %s" % (d.get("network_policy_name") or UKJENT))

    if len(versjoner) > 1:
        rap.legg(SEK1, "programvareversjoner", "WARN", "%d ulike versjoner" % len(versjoner), "lik på alle AP",
                 "; ".join("%s: %s" % (v, ", ".join(n)) for v, n in versjoner.items()))
    elif versjoner:
        rap.legg(SEK1, "programvareversjoner", "PASS", list(versjoner.keys())[0], "lik på alle AP")

    rap.md(SEK1, "**Aksesspunkter**\n\n" + md_tabell(
        ["Hostname", "Modell", "Serienr", "IP", "MAC", "Programvare", "Tilkoblet", "Oppetid", "Lokasjon",
         "Nettverkspolicy", "Aktive klienter", "Siste tilkobling"], rader))
    if aper:
        rap.md(SEK1, "**/devices (utdrag, første AP)**\n```json\n%s\n```" % json_utdrag(
            {k: aper[0].get(k) for k in ("id", "hostname", "product_type", "serial_number", "mac_address", "ip_address",
                                          "software_version", "device_admin_state", "connected", "last_connect_time",
                                          "system_up_time", "network_policy_name", "active_clients", "managed_by",
                                          "config_mismatch", "locations", "lldp_cdp_infos")}, 1800))
    return aper


def seksjon_radioer(api, rap, aper):
    rap.seksjon(SEK2)
    if not aper:
        rap.legg(SEK2, "radioer", "SKIP", "ingen AP-er å sjekke")
        return {}
    tilkoblede = [d for d in aper if d.get("connected")]
    ids = [heltall(d.get("id")) for d in tilkoblede if heltall(d.get("id")) is not None]
    navn_av_id = {heltall(d.get("id")): d.get("hostname") or ("id %s" % d.get("id")) for d in aper}
    naa = na()

    # --- /devices/radio-information (konfigurerte radioer: kanal, bredde, effekt, SSID-er)
    radioinfo = {}   # device_id -> [radio, ...]
    for i in range(0, len(ids), 50):
        batch = ids[i:i + 50]
        try:
            side, svar = api.hent_sider("/devices/radio-information",
                                        {"deviceIds": batch, "includeDisabledRadio": False}, maks=500, limit=50)
            for ent in side:
                if isinstance(ent, dict):
                    radioinfo[heltall(ent.get("device_id"))] = ent.get("radios") or []
        except ApiFeil as e:
            rap.legg(SEK2, "radio-information", "SKIP", "kunne ikke hentes for %d AP" % len(batch), "", str(e))
    if radioinfo:
        forste = next(iter(radioinfo.items()))
        rap.md(SEK2, "**/devices/radio-information (utdrag, %s)**\n```json\n%s\n```" % (
            navn_av_id.get(forste[0], forste[0]), json_utdrag(forste[1], 1800)))

    # --- /devices/{id}/interfaces/wifi (statistikk: utnyttelse, støy, retries)
    wifistat = {}    # device_id -> [interface, ...]
    forste_wifi = None
    for d in tilkoblede:
        did = heltall(d.get("id"))
        if did is None:
            continue
        data = None
        for timer in (1, 24):
            try:
                svar = api.get("/devices/%d/interfaces/wifi" % did,
                               {"startTime": ms(naa - timedelta(hours=timer)), "endTime": ms(naa)})
                if isinstance(svar, list) and svar:
                    data = svar
                    break
                if isinstance(svar, dict) and isinstance(svar.get("data"), list) and svar["data"]:
                    data = svar["data"]
                    break
            except ApiFeil as e:
                rap.legg(SEK2, "%s wifi-statistikk" % navn_av_id.get(did), "SKIP", "kunne ikke hentes", "", str(e))
                break
        if data:
            wifistat[did] = [x for x in data if isinstance(x, dict)]
            if forste_wifi is None:
                forste_wifi = (navn_av_id.get(did), data)
    if forste_wifi:
        rap.md(SEK2, "**/devices/{id}/interfaces/wifi (utdrag, %s)**\n```json\n%s\n```" % (
            forste_wifi[0], json_utdrag(forste_wifi[1], 2200)))

    # --- slå sammen per AP per radio
    rader = []
    radioer_per_ap = {}   # ap-navn -> liste av dict(band, kanal, bredde, effekt, klienter, ...)
    for did in ids:
        apnavn = navn_av_id.get(did, str(did))
        samlet = {}   # nøkkel (grensesnittnavn eller bånd) -> dict
        for r in radioinfo.get(did, []) or []:
            if not isinstance(r, dict):
                continue
            band = band_fra_tekst(r.get("frequency")) or band_fra_tekst(r.get("mode")) or band_fra_kanal(r.get("channel_number"))
            n = str(r.get("name") or band or "radio").lower()
            samlet[n] = {"grensesnitt": r.get("name"), "band": band, "kanal": heltall(r.get("channel_number")),
                         "bredde": kanalbredde(r.get("channel_width")), "effekt": heltall(r.get("power")),
                         "modus": r.get("mode"), "bssid_mac": r.get("mac_address"),
                         "ssider": sorted({str(w.get("ssid")) for w in (r.get("wlans") or []) if isinstance(w, dict) and w.get("ssid")}),
                         "klienter": None, "utnyttelse": None, "stoygulv": None, "interferens": None,
                         "retry_tx": None, "retry_pct": None, "crc": None}
        for w in wifistat.get(did, []) or []:
            band = band_fra_tekst(w.get("frequency")) or band_fra_kanal(w.get("channel"))
            n = str(w.get("interface_name") or band or "radio").lower()
            post = samlet.get(n)
            if post is None:
                # prøv å matche på bånd
                for k, v in samlet.items():
                    if v.get("band") and v.get("band") == band and v.get("utnyttelse") is None:
                        post = v
                        break
            if post is None:
                post = samlet.setdefault(n, {"grensesnitt": w.get("interface_name"), "band": band, "kanal": None, "bredde": None,
                                             "effekt": None, "modus": None, "bssid_mac": w.get("mac_address"), "ssider": [],
                                             "klienter": None, "utnyttelse": None, "stoygulv": None, "interferens": None,
                                             "retry_tx": None, "retry_pct": None, "crc": None})
            post["band"] = post.get("band") or band
            post["kanal"] = post.get("kanal") if post.get("kanal") is not None else heltall(w.get("channel"))
            post["bredde"] = post.get("bredde") if post.get("bredde") is not None else kanalbredde(w.get("channel_width"))
            post["effekt"] = post.get("effekt") if post.get("effekt") is not None else heltall(w.get("power"))
            post["klienter"] = heltall(w.get("client_count"))
            post["utnyttelse"] = tall(w.get("channel_util"))
            post["stoygulv"] = tall(w.get("noise_floor"))
            post["interferens"] = tall(w.get("scan_avg_interference"))
            post["crc"] = heltall(w.get("crc_error_frame"))
            rt = tall(w.get("tx_retry_frame"))
            utx = tall(w.get("unicast_tx_packet_count"))
            post["retry_tx"] = heltall(rt)
            if rt is not None and utx:
                post["retry_pct"] = 100.0 * rt / utx
            post["radioprofil"] = w.get("radio_profile_name")
            post["ssid_antall"] = heltall(w.get("ssid_count"))
        radioer_per_ap[apnavn] = list(samlet.values())

    # --- vurderinger
    fem_ghz_kanaler = {}
    dfs_antall = 0
    for apnavn, radioer in radioer_per_ap.items():
        effekt = {}
        for r in radioer:
            band = r.get("band") or UKJENT
            merkelapp = "%s %s (%s, kanal %s)" % (apnavn, r.get("grensesnitt") or "radio", band, s(r.get("kanal")))
            u = r.get("utnyttelse")
            rap.legg(SEK2, "%s kanalutnyttelse" % merkelapp, vurder_utnyttelse(u),
                     ("%d %%" % round(u)) if u is not None else UKJENT, "< 50 % PASS, < 70 % WARN, ≥ 70 % FAIL",
                     "klienter %s, interferens %s, retries tx %s%s" % (
                         s(r.get("klienter")), s(r.get("interferens")), s(r.get("retry_tx")),
                         (" (%.1f %%)" % r["retry_pct"]) if r.get("retry_pct") is not None else ""))
            n = r.get("stoygulv")
            rap.legg(SEK2, "%s støygulv" % merkelapp, vurder_stoygulv(n),
                     ("%s dBm" % s(heltall(n))) if n is not None else UKJENT, "≤ -90 PASS, ≤ -85 WARN, > -85 FAIL")
            if band == "2,4 GHz":
                k = r.get("kanal")
                if k is not None:
                    rap.legg(SEK2, "%s kanalvalg 2,4 GHz" % merkelapp, "PASS" if k in (1, 6, 11) else "WARN",
                             "kanal %d" % k, "1/6/11", "" if k in (1, 6, 11) else "overlappende kanal — bruk 1, 6 eller 11")
                b = r.get("bredde")
                if b is not None:
                    rap.legg(SEK2, "%s kanalbredde 2,4 GHz" % merkelapp, "PASS" if b <= 20 else "WARN", "%d MHz" % b, "20 MHz",
                             "" if b <= 20 else "40 MHz på 2,4 GHz gir mer interferens — sett 20 MHz")
            if band == "5 GHz" and r.get("kanal") is not None:
                fem_ghz_kanaler.setdefault(r["kanal"], []).append(apnavn)
                if 52 <= r["kanal"] <= 144:
                    dfs_antall += 1
            if band in ("2,4 GHz", "5 GHz") and r.get("effekt") is not None:
                effekt.setdefault(band, []).append(r["effekt"])
            rader.append([apnavn, r.get("grensesnitt"), band, r.get("kanal"), r.get("bredde"),
                          ("%s dBm" % r["effekt"]) if r.get("effekt") is not None else UKJENT, r.get("klienter"),
                          r.get("utnyttelse"), r.get("stoygulv"), r.get("interferens"),
                          ("%s (%.1f %%)" % (r["retry_tx"], r["retry_pct"])) if r.get("retry_pct") is not None else r.get("retry_tx"),
                          r.get("crc"), ", ".join(r.get("ssider") or []) or UKJENT, r.get("modus")])
        if effekt.get("2,4 GHz") and effekt.get("5 GHz"):
            p24, p5 = max(effekt["2,4 GHz"]), max(effekt["5 GHz"])
            rap.legg(SEK2, "%s tx-effekt 2,4 vs 5 GHz" % apnavn, "WARN" if p24 > p5 else "PASS",
                     "2,4 GHz %d dBm, 5 GHz %d dBm" % (p24, p5), "2,4 GHz ≤ 5 GHz",
                     "2,4 GHz-klissete klienter: senk 2,4 GHz-effekten under 5 GHz for bedre båndstyring" if p24 > p5 else "")
        if not radioer:
            rap.legg(SEK2, "%s radioer" % apnavn, "INFO", "ingen radiodata (frakoblet eller ingen data i XIQ)")

    dup = {k: v for k, v in fem_ghz_kanaler.items() if len(v) > 1}
    if dup:
        rap.legg(SEK2, "samme 5 GHz-kanal på flere AP (co-channel)", "INFO", "; ".join(
            "kanal %s: %s" % (k, ", ".join(v)) for k, v in sorted(dup.items())), "",
            "co-channel-interferens hvis AP-ene overlapper i dekning — vurder ACS/kanalplan")
    elif fem_ghz_kanaler:
        rap.legg(SEK2, "samme 5 GHz-kanal på flere AP (co-channel)", "INFO", "ingen duplikater")
    if radioer_per_ap:
        rap.legg(SEK2, "DFS-kanaler (52–144) på 5 GHz", "INFO", "%d radio(er)" % dfs_antall, "",
                 "DFS-kanaler kan gi kanalbytte ved radarhendelser (klienter mister forbindelse kort)")

    rap.md(SEK2, "**Radioer per AP**\n\n" + md_tabell(
        ["AP", "Radio", "Bånd", "Kanal", "Bredde MHz", "Tx-effekt", "Klienter", "Utnyttelse %", "Støygulv dBm",
         "Interferens", "Tx-retries", "CRC-feil", "SSID-er", "Modus"], rader))
    return radioer_per_ap


def klient_band(k):
    return band_fra_radio_type(k.get("radio_type")) or band_fra_tekst(k.get("mac_protocol")) or band_fra_kanal(k.get("channel"))


def klient_navn(k):
    return k.get("hostname") or k.get("alias") or k.get("username") or (k.get("vendor") or "") + " " + pen_mac(k.get("mac_address"))


def seksjon_klienter(api, rap, args, aper):
    rap.seksjon(SEK3)
    try:
        klienter, svar = api.hent_sider("/clients/active", {"views": ["FULL"], "clientConnectionTypes": [1],
                                                             "sortField": "RSSI", "sortOrder": "ASC"},
                                        maks=args.maks_klienter)
    except ApiFeil as e:
        rap.legg(SEK3, "hent klienter", "FAIL", "kunne ikke hente /clients/active", "", str(e))
        return []
    klienter = [k for k in klienter if isinstance(k, dict)]
    totalt = heltall((svar or {}).get("total_count"), len(klienter))
    try:
        summ = api.get("/clients/summary")
        if isinstance(summ, dict):
            rap.legg(SEK3, "klientsammendrag", "INFO", "%s trådløse tilkoblet, %s kablede oppdaget" % (
                summ.get("connected_wireless_client_count", UKJENT), summ.get("detected_wired_client_count", UKJENT)))
    except ApiFeil as e:
        rap.legg(SEK3, "klientsammendrag", "SKIP", "", "", str(e))
    rap.legg(SEK3, "antall aktive trådløse klienter", "INFO", "%d hentet (total_count %s)" % (len(klienter), s(totalt)),
             "", "begrenset til --maks-klienter %d" % args.maks_klienter if totalt and totalt > len(klienter) else "")

    per_ssid, per_ap, per_radio = {}, {}, {}
    rader = []
    rssi_liste = []
    darlige = []
    ssid_regel = (args.ssid or "").strip().lower()
    for k in klienter:
        band = klient_band(k) or UKJENT
        ssid = k.get("ssid") or UKJENT
        apn = k.get("device_name") or k.get("connected_to") or UKJENT
        per_ssid[ssid] = per_ssid.get(ssid, 0) + 1
        per_ap[apn] = per_ap.get(apn, 0) + 1
        per_radio[(apn, band)] = per_radio.get((apn, band), 0) + 1
        rssi, snr = heltall(k.get("rssi")), heltall(k.get("snr"))
        if rssi is not None and rssi > 0:
            rssi = None    # ugyldig verdi (0/positiv) -> ukjent
        helse = "/".join(s(k.get(x)) for x in ("client_health", "radio_health", "network_health", "application_health"))
        rader.append([klient_navn(k), pen_mac(k.get("mac_address")), k.get("ip_address"), ssid, apn, band, k.get("channel"),
                      rssi, snr, UKJENT, helse, " ".join(x for x in [k.get("os_type"), k.get("os_version")] if x) or UKJENT,
                      fmt_tid(k.get("online_time")), k.get("username")])
        if rssi is not None:
            rssi_liste.append((rssi, k))
        st_r, st_s = vurder_rssi(rssi), vurder_snr(snr)
        verste = "FAIL" if "FAIL" in (st_r, st_s) else ("WARN" if "WARN" in (st_r, st_s) else "PASS")
        if verste != "PASS":
            darlige.append((verste, k, rssi, snr, band, apn, ssid))
        if ssid_regel and ssid.lower() == ssid_regel and band == "2,4 GHz":
            rap.legg(SEK3, "%s på 2,4 GHz" % klient_navn(k), "WARN", "SSID %s via %s, kanal %s" % (ssid, apn, s(k.get("channel"))),
                     "5 GHz på %s" % args.ssid, "klienten bruker 2,4 GHz på admin-nettet — sjekk båndstyring/5 GHz-dekning")

    ant_pass = len(klienter) - len(darlige)
    rap.legg(SEK3, "signalkvalitet (RSSI/SNR)", "PASS" if not darlige else "INFO",
             "%d klienter OK, %d med WARN, %d med FAIL" % (
                 ant_pass, sum(1 for d in darlige if d[0] == "WARN"), sum(1 for d in darlige if d[0] == "FAIL")),
             "RSSI ≥ -65/-72 dBm, SNR ≥ 25/15 dB")
    vist = 0
    for verste, k, rssi, snr, band, apn, ssid in sorted(darlige, key=lambda x: (x[0] != "FAIL", x[2] if x[2] is not None else 0)):
        if vist >= 25:
            rap.legg(SEK3, "flere klienter med svakt signal", "INFO", "%d til (se tabell)" % (len(darlige) - vist))
            break
        rap.legg(SEK3, "%s signal" % klient_navn(k), verste, "RSSI %s dBm, SNR %s dB, %s via %s (%s)" % (
            s(rssi), s(snr), band, apn, ssid), "RSSI ≥ -65 PASS / ≥ -72 WARN; SNR ≥ 25 PASS / ≥ 15 WARN")
        vist += 1

    for (apn, band), n in sorted(per_radio.items()):
        if n > 30:
            rap.legg(SEK3, "%s %s klienter per radio" % (apn, band), "WARN", "%d klienter" % n, "≤ 30",
                     "høy last på én radio — vurder flere AP/kanaler eller båndstyring")
    if per_ssid:
        rap.legg(SEK3, "fordeling per SSID", "INFO", ", ".join("%s: %d" % (k2, v) for k2, v in sorted(per_ssid.items(), key=lambda x: -x[1])))
    if per_ap:
        rap.legg(SEK3, "fordeling per AP", "INFO", ", ".join("%s: %d" % (k2, v) for k2, v in sorted(per_ap.items(), key=lambda x: -x[1])))
    band_fordeling = {}
    for (apn, band), n in per_radio.items():
        band_fordeling[band] = band_fordeling.get(band, 0) + n
    if band_fordeling:
        rap.legg(SEK3, "fordeling per bånd", "INFO", ", ".join("%s: %d" % (k2, v) for k2, v in sorted(band_fordeling.items())))

    rap.md(SEK3, "**Fordeling**\n\n" + md_tabell(["SSID", "Klienter"], sorted(per_ssid.items(), key=lambda x: -x[1])) +
           "\n" + md_tabell(["AP", "Klienter"], sorted(per_ap.items(), key=lambda x: -x[1])) +
           "\n" + md_tabell(["AP", "Bånd", "Klienter"], [[a, b, n] for (a, b), n in sorted(per_radio.items())]))
    verste10 = sorted(rssi_liste, key=lambda x: x[0])[:10]
    rap.md(SEK3, "**10 svakeste klienter (RSSI)**\n\n" + md_tabell(
        ["Navn", "MAC", "RSSI", "SNR", "Bånd", "Kanal", "AP", "SSID"],
        [[klient_navn(k), pen_mac(k.get("mac_address")), r, k.get("snr"), klient_band(k), k.get("channel"),
          k.get("device_name"), k.get("ssid")] for r, k in verste10]))
    rap.md(SEK3, "**Alle aktive trådløse klienter (%d)**\n\n" % len(rader) + md_tabell(
        ["Navn", "MAC", "IP", "SSID", "AP", "Bånd", "Kanal", "RSSI", "SNR", "Tx/rx-rate", "Helse (klient/radio/nett/app)",
         "OS", "Tilkoblet siden", "Bruker"], rader))
    if klienter:
        rap.md(SEK3, "**/clients/active (utdrag, første klient)**\n```json\n%s\n```" % json_utdrag(
            {k2: klienter[0].get(k2) for k2 in ("id", "hostname", "alias", "mac_address", "ip_address", "ssid", "device_name",
                                                "device_id", "radio_type", "channel", "rssi", "snr", "client_health",
                                                "radio_health", "network_health", "application_health", "os_type",
                                                "mac_protocol", "auth", "encryption_method", "bssid", "online_time",
                                                "connection_duration", "username", "vendor", "user_profile_name", "vlan")}, 1600))
    return klienter


def finn_klient(api, rap, sok, klienter):
    """Returnerer (klientdict eller None, beskrivelse)."""
    sok_l = sok.strip().lower()
    mac_sok = norm_mac(sok) if re.fullmatch(r"[0-9a-fA-F:\-. ]{12,17}", sok.strip()) and len(norm_mac(sok)) == 12 else ""
    treff = []
    for k in klienter:
        felter = [str(k.get(x) or "").lower() for x in ("hostname", "alias", "ip_address", "username")]
        if (mac_sok and norm_mac(k.get("mac_address")) == mac_sok) or any(sok_l in f for f in felter if f):
            treff.append(k)
    if treff:
        k = treff[0]
        beskrivelse = "%d treff i aktive klienter" % len(treff)
        try:
            full = api.get("/clients/%s" % k.get("id"), {"views": ["FULL"]})
            if isinstance(full, dict) and full.get("id"):
                k = full
        except ApiFeil as e:
            beskrivelse += "; /clients/{id} feilet: %s" % e
        return k, beskrivelse
    if mac_sok:
        for variant in (mac_sok.upper(), pen_mac(mac_sok)):
            try:
                full = api.get("/clients/byMac/%s" % urllib.parse.quote(variant, safe=""), {"views": ["FULL"]})
                if isinstance(full, dict) and (full.get("id") or full.get("mac_address")):
                    return full, "funnet via /clients/byMac (ikke i aktiv-listen)"
            except ApiFeil as e:
                if e.status not in (404, 400):
                    return None, "/clients/byMac feilet: %s" % e
    return None, "ingen treff"


def seksjon_din_klient(api, rap, args, klienter):
    rap.seksjon(SEK4)
    if not args.klient:
        rap.legg(SEK4, "din klient", "SKIP", "ingen --klient oppgitt")
        return
    k, beskrivelse = finn_klient(api, rap, args.klient, klienter)
    if not k:
        rap.legg(SEK4, "din klient '%s'" % args.klient, "WARN", "ikke funnet (%s)" % beskrivelse, "",
                 "slå på Wi-Fi på telefonen og koble til Adm-nett, vent 1–2 min og kjør igjen; sjekk at MAC ikke er randomisert")
        return
    navn = klient_navn(k)
    band = klient_band(k) or UKJENT
    rssi, snr = heltall(k.get("rssi")), heltall(k.get("snr"))
    if rssi is not None and rssi > 0:
        rssi = None
    rap.legg(SEK4, "funnet", "INFO", "%s — %s, IP %s (%s)" % (navn, pen_mac(k.get("mac_address")), k.get("ip_address") or UKJENT, beskrivelse))
    rap.legg(SEK4, "tilkobling", "INFO" if k.get("connected", True) else "WARN",
             "%s, SSID %s via %s%s, %s kanal %s, BSSID %s" % (
                 "tilkoblet" if k.get("connected", True) else "FRAKOBLET", k.get("ssid") or UKJENT,
                 k.get("device_name") or k.get("connected_to") or UKJENT,
                 (" (%s)" % k.get("interface_name")) if k.get("interface_name") else "", band, s(k.get("channel")),
                 pen_mac(k.get("bssid")) if k.get("bssid") else UKJENT),
             "", "siden %s, varighet %s, VLAN %s, brukerprofil %s" % (
                 fmt_tid(k.get("online_time")), fmt_varighet(tall(k.get("connection_duration"))) if k.get("connection_duration") else UKJENT,
                 s(k.get("vlan")), k.get("user_profile_name") or UKJENT))
    rap.legg(SEK4, "RSSI", vurder_rssi(rssi), ("%d dBm" % rssi) if rssi is not None else UKJENT, "≥ -65 PASS, ≥ -72 WARN")
    rap.legg(SEK4, "SNR", vurder_snr(snr), ("%d dB" % snr) if snr is not None else UKJENT, "≥ 25 PASS, ≥ 15 WARN")
    rap.legg(SEK4, "helse-score", "INFO", "klient %s, radio %s, nett %s, app %s" % (
        s(k.get("client_health")), s(k.get("radio_health")), s(k.get("network_health")), s(k.get("application_health"))), "0–100")
    rap.legg(SEK4, "enhet/protokoll", "INFO", "%s %s, %s, auth %s, leverandør %s" % (
        k.get("os_type") or UKJENT, k.get("os_version") or "", k.get("mac_protocol") or UKJENT,
        AUTH_KODER.get(heltall(k.get("auth")), s(k.get("auth"))), k.get("vendor") or UKJENT))
    if args.ssid and str(k.get("ssid") or "").lower() == args.ssid.lower() and band == "2,4 GHz":
        rap.legg(SEK4, "bånd på %s" % args.ssid, "WARN", "2,4 GHz", "5 GHz", "telefonen henger på 2,4 GHz — sjekk 5 GHz-dekning/båndstyring")

    rap.md(SEK4, "**/clients/{id} (utdrag)**\n```json\n%s\n```" % json_utdrag(
        {x: k.get(x) for x in ("id", "hostname", "alias", "mac_address", "ip_address", "ssid", "device_name", "device_id",
                               "bssid", "interface_name", "radio_type", "channel", "rssi", "snr", "client_health", "radio_health",
                               "network_health", "application_health", "os_type", "os_version", "mac_protocol", "auth",
                               "encryption_method", "online_time", "connection_duration", "username", "vendor",
                               "user_profile_name", "vlan", "connected", "mobility")}, 2000))

    kid = heltall(k.get("id"))
    if kid is None:
        rap.legg(SEK4, "roaming-historikk", "SKIP", "mangler klient-ID")
        return
    naa = na()
    t24 = {"startTime": ms(naa - timedelta(hours=24)), "endTime": ms(naa)}

    try:
        info = api.get("/client-details/overview/info/%d" % kid, t24)
        if isinstance(info, dict):
            rap.legg(SEK4, "klientdetaljer (XIQ 360)", "INFO", "%s via %s, radio %s, %s, kanal %s, lokasjon %s" % (
                info.get("ssid") or UKJENT, info.get("connection_to") or UKJENT, info.get("radio") or UKJENT,
                info.get("wifi_protocol") or UKJENT, s(info.get("channel")), info.get("device_location_names") or UKJENT),
                "", "klienttype %s, RTTS-støtte %s, administrert av %s" % (
                    info.get("client_type") or UKJENT, s(info.get("rtts_supported")), info.get("device_managed_by") or UKJENT))
    except ApiFeil as e:
        rap.legg(SEK4, "klientdetaljer (XIQ 360)", "SKIP", "", "", str(e))

    try:
        tell = api.get("/client-details/client-trail/roaming-trail/count/%d" % kid, t24)
        if isinstance(tell, dict):
            fullfort, feilet, treg = heltall(tell.get("roam_completed"), 0), heltall(tell.get("roam_failed"), 0), heltall(tell.get("slow_roam_count"), 0)
            rap.legg(SEK4, "roaming siste 24 t", "WARN" if feilet else "INFO",
                     "%d fullført, %d feilet, %d trege" % (fullfort, feilet, treg), "0 feilet")
    except ApiFeil as e:
        rap.legg(SEK4, "roaming siste 24 t", "SKIP", "", "", str(e))

    try:
        trail = api.get("/client-details/client-trail/roaming-trail/grid/%d" % kid, dict(t24, precision=600000))
        hendelser = (trail or {}).get("data") if isinstance(trail, dict) else (trail if isinstance(trail, list) else [])
        hendelser = [h for h in (hendelser or []) if isinstance(h, dict)]
        hendelser.sort(key=lambda h: tall(h.get("timestamp"), 0), reverse=True)
        rader = []
        for h in hendelser[:30]:
            det = [d for d in (h.get("data") or []) if isinstance(d, dict)]
            d0 = det[-1] if det else {}
            rader.append([fmt_tid(h.get("timestamp")), h.get("device_name_from"), h.get("device_name_to"), h.get("status_action"),
                          h.get("roam_duration"), d0.get("channel_from"), d0.get("channel_to"), d0.get("rssi_from"), d0.get("rssi_to"),
                          d0.get("radio_type_from"), d0.get("radio_type_to"),
                          "; ".join("%s%s" % (d.get("status"), (" (" + str(d.get("reason")) + ")") if d.get("reason") else "") for d in det)])
        rap.legg(SEK4, "roaming-spor", "INFO", "%d hendelser siste 24 t (viser opptil 30 i rapporten)" % len(hendelser))
        for h in hendelser[:5]:
            st = "WARN" if str(h.get("status_action") or "").upper() in ("FAILED", "DISCONNECT") else "INFO"
            rap.legg(SEK4, "roam %s" % fmt_tid(h.get("timestamp")), st, "%s → %s, %s, %s ms" % (
                h.get("device_name_from") or "?", h.get("device_name_to") or "?", h.get("status_action") or "?", s(h.get("roam_duration"))))
        rap.md(SEK4, "**Roaming-spor siste 24 t**\n\n" + md_tabell(
            ["Tid", "Fra AP", "Til AP", "Status", "Varighet ms", "Kanal fra", "Kanal til", "RSSI fra", "RSSI til",
             "Radio fra", "Radio til", "Steg"], rader))
        if hendelser:
            rap.md(SEK4, "**roaming-trail (utdrag)**\n```json\n%s\n```" % json_utdrag(hendelser[:2], 1500))
    except ApiFeil as e:
        rap.legg(SEK4, "roaming-spor", "SKIP", "", "", str(e))

    try:
        t1 = {"startTime": ms(naa - timedelta(hours=1)), "endTime": ms(naa), "precision": 60000}
        chart = api.get("/client-details/overview/chart-data/%d" % kid, t1)
        punkter = (chart or {}).get("data") if isinstance(chart, dict) else (chart if isinstance(chart, list) else [])
        punkter = [p for p in (punkter or []) if isinstance(p, dict)]
        rs = [tall(p.get("rssi")) for p in punkter if tall(p.get("rssi")) is not None and tall(p.get("rssi")) < 0]
        sn = [tall(p.get("snr")) for p in punkter if tall(p.get("snr")) is not None]
        nf = [tall(p.get("noise_floor")) for p in punkter if tall(p.get("noise_floor")) is not None and tall(p.get("noise_floor")) < 0]
        roams = [p for p in punkter if isinstance(p.get("roam_details"), dict) and (p["roam_details"].get("device_name_to") or p["roam_details"].get("device_mac_to"))]
        if rs or sn:
            rap.legg(SEK4, "signal siste time (samplet)", "INFO", "RSSI snitt %s / min %s / maks %s dBm; SNR snitt %s dB; støygulv snitt %s dBm; %d roam" % (
                ("%.0f" % statistics.mean(rs)) if rs else "?", ("%.0f" % min(rs)) if rs else "?", ("%.0f" % max(rs)) if rs else "?",
                ("%.0f" % statistics.mean(sn)) if sn else "?", ("%.0f" % statistics.mean(nf)) if nf else "?", len(roams)),
                "", "%d målepunkter" % len(punkter))
        else:
            rap.legg(SEK4, "signal siste time (samplet)", "INFO", "ingen målepunkter")
    except ApiFeil as e:
        rap.legg(SEK4, "signal siste time (samplet)", "SKIP", "", "", str(e))

    try:
        ce = api.get("/client-details/client-trail/connectivity-experience/%d" % kid, dict(t24, precision=600000))
        rader_ce = (ce or {}).get("data") if isinstance(ce, dict) else []
        rader_ce = [r for r in (rader_ce or []) if isinstance(r, dict)]
        rader_ce.sort(key=lambda r: tall(r.get("start_timestamp"), 0), reverse=True)
        if rader_ce:
            r0 = rader_ce[0]
            problemer = [n for n, f in (("assoc", "association_circle_status"), ("auth", "auth_circle_status"), ("dhcp", "dhcp_circle_status"),
                                        ("dns", "dns_circle_status"), ("gateway", "gateway_circle_status"))
                         if str(r0.get(f) or "").upper() in ("ERROR", "INVALID")]
            rap.legg(SEK4, "tilkoblingsopplevelse (siste)", "WARN" if problemer else "INFO",
                     "%s via %s: auth %s, DHCP %s (%s ms), gateway %s (%s ms), DNS %s (%s ms), RSSI %s, SNR %s" % (
                         fmt_tid(r0.get("start_timestamp")), r0.get("device_name") or UKJENT, r0.get("auth_circle_status") or "?",
                         r0.get("dhcp_circle_status") or "?", s(r0.get("dhcp_server_response_time")), r0.get("gateway_circle_status") or "?",
                         s(r0.get("default_gateway_round_trip_delay_time")), r0.get("dns_circle_status") or "?",
                         s(r0.get("dns_server_response_time")), s(r0.get("avg_rssi")), s(r0.get("avg_snr"))),
                     "", ("feil i: " + ", ".join(problemer)) if problemer else "%d tilkoblinger siste 24 t" % len(rader_ce))
            rap.md(SEK4, "**Tilkoblingsopplevelse siste 24 t**\n\n" + md_tabell(
                ["Tid", "AP", "SSID", "Auth", "DHCP", "Gateway", "DNS", "RSSI", "SNR", "IP"],
                [[fmt_tid(r.get("start_timestamp")), r.get("device_name"), r.get("ssid"), r.get("auth_circle_status"),
                  r.get("dhcp_circle_status"), r.get("gateway_circle_status"), r.get("dns_circle_status"), r.get("avg_rssi"),
                  r.get("avg_snr"), r.get("client_ip")] for r in rader_ce[:15]]))
        else:
            rap.legg(SEK4, "tilkoblingsopplevelse (siste)", "INFO", "ingen data siste 24 t")
    except ApiFeil as e:
        rap.legg(SEK4, "tilkoblingsopplevelse (siste)", "SKIP", "", "", str(e))


def seksjon_varsler(api, rap, aper):
    rap.seksjon(SEK5)
    naa = na()
    t24 = {"startTime": ms(naa - timedelta(hours=24)), "endTime": ms(naa)}
    try:
        varsler, svar = api.hent_sider("/alerts", dict(t24, sortField="TIMESTAMP", order="DESC"), maks=300)
        varsler = [v for v in varsler if isinstance(v, dict)]
        teller = {}
        for v in varsler:
            navn = str(v.get("severity_name") or v.get("severity_id") or UKJENT).lower()
            teller[navn] = teller.get(navn, 0) + 1
        try:
            grp = api.get("/alerts/count-by-SEVERITY", t24)
            if isinstance(grp, list) and grp:
                teller = {str(g.get("group_name") or g.get("group_id")).lower(): heltall(g.get("count"), 0) for g in grp if isinstance(g, dict)}
        except ApiFeil:
            pass
        for navn, n in sorted(teller.items()):
            st = "INFO"
            if n > 0 and navn in ("critical", "kritisk"):
                st = "FAIL"
            elif n > 0 and navn in ("major", "warning", "minor", "advarsel"):
                st = "WARN"
            rap.legg(SEK5, "varsler siste 24 t, alvorlighet %s" % navn, st, "%d" % n, "critical → FAIL, major/warning → WARN")
        if not teller:
            rap.legg(SEK5, "varsler siste 24 t", "PASS", "ingen varsler", "0")
        else:
            rap.legg(SEK5, "varsler siste 24 t totalt", "INFO", "%d (total_count %s)" % (len(varsler), s((svar or {}).get("total_count"))))
        rader = []
        for v in varsler[:20]:
            kilde = v.get("source") if isinstance(v.get("source"), dict) else {}
            rader.append([fmt_tid(v.get("timestamp")), v.get("severity_name"), v.get("category_name"),
                          kilde.get("source_name") or kilde.get("source_id"), (v.get("summary") or "")[:200],
                          "ja" if v.get("acknowledged") else "nei"])
        rap.md(SEK5, "**Nyeste varsler (opptil 20)**\n\n" + md_tabell(
            ["Tid", "Alvorlighet", "Kategori", "Enhet/kilde", "Tekst", "Kvittert"], rader))
        if varsler:
            rap.md(SEK5, "**/alerts (utdrag)**\n```json\n%s\n```" % json_utdrag(varsler[:2], 1500))
    except ApiFeil as e:
        rap.legg(SEK5, "varsler siste 24 t", "SKIP", "kunne ikke hente /alerts", "", str(e))

    alarm_rader = []
    for d in aper:
        did = heltall(d.get("id"))
        navn = d.get("hostname") or ("id %s" % did)
        if did is None:
            continue
        try:
            alarmer, svar = api.hent_sider("/devices/%d/alarms" % did, t24, maks=100)
            alarmer = [a for a in alarmer if isinstance(a, dict)]
            if not alarmer:
                rap.legg(SEK5, "%s enhetsalarmer siste 24 t" % navn, "INFO", "0")
            else:
                sev = {}
                for a in alarmer:
                    sv = str(a.get("severity") or UKJENT).lower()
                    sev[sv] = sev.get(sv, 0) + 1
                st = "FAIL" if any(x in sev for x in ("critical",)) else "WARN"
                rap.legg(SEK5, "%s enhetsalarmer siste 24 t" % navn, st, ", ".join("%s: %d" % (a, b) for a, b in sorted(sev.items())),
                         "0", "; ".join((a.get("description") or "")[:80] for a in alarmer[:3]))
                for a in alarmer[:20]:
                    alarm_rader.append([navn, fmt_tid(a.get("timestamp")), a.get("severity"), a.get("category"),
                                        pen_mac(a.get("client_mac")) if a.get("client_mac") else "", (a.get("description") or "")[:200]])
        except ApiFeil as e:
            rap.legg(SEK5, "%s enhetsalarmer siste 24 t" % navn, "SKIP", "", "", str(e))
    if alarm_rader:
        rap.md(SEK5, "**Enhetsalarmer per AP (opptil 20 per AP)**\n\n" + md_tabell(
            ["AP", "Tid", "Alvorlighet", "Kategori", "Klient-MAC", "Beskrivelse"], alarm_rader))


def seksjon_cli(api, rap, args, aper):
    rap.seksjon(SEK6)
    if not args.cli:
        rap.legg(SEK6, "CLI", "SKIP", "ikke aktivert (bruk --cli)")
        return
    kommandoer = [c.strip() for c in (args.cli_kommandoer or ";".join(STANDARD_CLI)).split(";") if c.strip()]
    godkjente = []
    for c in kommandoer:
        if c.lower().startswith("show ") and "|" not in c and ";" not in c:
            godkjente.append(c)
        else:
            rap.legg(SEK6, "kommando nektet", "SKIP", c, "må begynne med 'show '", "verktøyet sender kun lesekommandoer")
    tilkoblede = [d for d in aper if d.get("connected") and heltall(d.get("id")) is not None]
    if not godkjente or not tilkoblede:
        rap.legg(SEK6, "CLI", "SKIP", "ingen godkjente kommandoer" if not godkjente else "ingen tilkoblede AP")
        return
    navn_av_id = {str(heltall(d.get("id"))): d.get("hostname") or ("id %s" % d.get("id")) for d in tilkoblede}
    ids = [heltall(d.get("id")) for d in tilkoblede]
    rap.legg(SEK6, "sender", "INFO", "%d kommando(er) til %d AP" % (len(godkjente), len(ids)), "", "; ".join(godkjente))
    try:
        status, obj, hdr = api.kall("POST", "/devices/:cli", params={"async": False},
                                    body={"devices": {"ids": ids}, "clis": godkjente}, timeout=CLI_TIDSAVBRUDD)
        if status == 202 or (isinstance(obj, dict) and obj.get("id") and "metadata" in obj and "device_cli_outputs" not in obj):
            op_id = None
            loc = hdr.get("Location") if hdr is not None else None
            if loc:
                op_id = loc.rstrip("/").split("/")[-1]
            if not op_id and isinstance(obj, dict):
                op_id = obj.get("id")
            if not op_id:
                raise ApiFeil("LRO-svar uten operasjons-ID (HTTP %s)" % status)
            rap.legg(SEK6, "LRO", "INFO", "operasjon %s — venter på resultat" % op_id)
            obj = api.vent_paa_operasjon(op_id)
    except ApiFeil as e:
        rap.legg(SEK6, "CLI-kall", "FAIL", "feilet", "", str(e))
        return
    utdata = (obj or {}).get("device_cli_outputs") if isinstance(obj, dict) else None
    if not isinstance(utdata, dict):
        rap.legg(SEK6, "CLI-kall", "WARN", "uventet svarformat", "", json_utdrag(obj, 400))
        return
    for did, liste in utdata.items():
        apnavn = navn_av_id.get(str(did), str(did))
        if not isinstance(liste, list):
            continue
        for u in liste:
            if not isinstance(u, dict):
                continue
            cli = str(u.get("cli") or "?")
            kode = str(u.get("response_code") or UKJENT)
            ut = str(u.get("output") or "")
            st = "INFO" if kode in ("SUCCEED", "CLI_SENT_SUCCEED") else "WARN"
            detalj = ""
            if cli.lower().startswith("show capwap"):
                m = re.search(r"RUN state\s*:\s*(.+)", ut, re.I)
                if m:
                    st = "PASS" if "connect" in m.group(1).lower() else "FAIL"
                    detalj = "RUN state: " + m.group(1).strip()
                elif re.search(r"\bRUN\b", ut):
                    st, detalj = "PASS", "fant 'RUN' i utdata"
                else:
                    st, detalj = "FAIL" if ut else "WARN", "fant ikke RUN-tilstand i utdata"
                rap.legg(SEK6, "%s capwap" % apnavn, st, kode, "RUN/Connected", detalj)
            else:
                rap.legg(SEK6, "%s '%s'" % (apnavn, cli), st, kode, "", "%d tegn utdata" % len(ut))
            rap.md(SEK6, "**%s — `%s` (%s)**\n```text\n%s\n```" % (apnavn, cli, kode, (ut[:4000] + ("\n… (avkortet)" if len(ut) > 4000 else "")) or "(tomt)"))


def seksjon_oppsummering(rap, avbrudd=None):
    rap.seksjon(SEK7)
    if avbrudd:
        rap.legg(SEK7, "avbrutt", avbrudd[0], avbrudd[1], "", avbrudd[2])
    o = rap.oppsummering()
    for r in rap.resultater:
        if r["status"] in ("FAIL", "WARN") and r["seksjon"] != SEK7:
            print(rap.farger.f(r["status"], "  [%s] %s: %s — %s" % (r["status"], r["seksjon"], r["sjekk"], r["verdi"])))
    print("  PASS %d · WARN %d · FAIL %d · INFO %d · SKIP %d" % (o["pass"], o["warn"], o["fail"], o["info"], o["skip"]))
    avvik = [r for r in rap.resultater if r["status"] in ("FAIL", "WARN")]
    rap.md(SEK7, "**Avvik (FAIL/WARN)**\n\n" + md_tabell(["Status", "Seksjon", "Sjekk", "Verdi", "Detaljer"],
                                                        [[r["status"], r["seksjon"], r["sjekk"], r["verdi"], r["detaljer"]] for r in avvik]))


# --------------------------------------------------------------------------------------
# Hovedprogram
# --------------------------------------------------------------------------------------

def lag_argparser():
    p = argparse.ArgumentParser(
        prog="xiq-sjekk.py", add_help=False,
        description="AP ↔ klient-helsesjekk for Marivold Camping via ExtremeCloud IQ (XIQ) sky-API. "
                    "Endrer ingenting — kun lesing. Skriver xiq-rapport-<tid>.md og .json.",
        epilog="Eksempel: XIQ_TOKEN=... python3 xiq-sjekk.py --klient \"AA:BB:CC:DD:EE:FF\" --rapportmappe ./rapporter")
    p.add_argument("-h", "--help", "--hjelp", action="help", help="vis denne hjelpen og avslutt")
    a = p.add_argument_group("autentisering (rekkefølge: --token, --token-fil, XIQ_TOKEN, --bruker)")
    a.add_argument("--token", help="XIQ API-token (Bearer). Skrives aldri ut.")
    a.add_argument("--token-fil", help="fil som inneholder API-token (én linje)")
    a.add_argument("--bruker", help="e-post for innlogging via POST /login (passord spørres med getpass)")
    a.add_argument("--passord-fil", help="fil med passord (første linje) — for kjøring uten terminal")
    a.add_argument("--base-url", default=STANDARD_BASE_URL, help="API-base (standard %(default)s)")
    v = p.add_argument_group("valg")
    v.add_argument("--klient", help="din klient: MAC eller del av navn/IP (ufølsom for store/små bokstaver)")
    v.add_argument("--ssid", default="Adm-nett", help="SSID der 2,4 GHz-klienter gir WARN (standard %(default)s)")
    v.add_argument("--cli", action="store_true", help="send lesekommandoer ('show …') til tilkoblede AP via /devices/:cli")
    v.add_argument("--cli-kommandoer", help="kommandoer adskilt med ';' (standard: %s)" % "; ".join(STANDARD_CLI))
    v.add_argument("--rapportmappe", default=".", help="mappe for rapportfiler (standard: gjeldende mappe)")
    v.add_argument("--ingen-farger", action="store_true", help="ingen ANSI-farger i utskrift")
    v.add_argument("--maks-klienter", type=int, default=500, help="maks antall klienter som hentes (standard %(default)s)")
    v.add_argument("--versjon", action="version", version="%s %s (2026-09-09)" % (VERKTOY, VERSJON), help="vis versjon")
    return p


def les_forste_linje(sti):
    with open(os.path.expanduser(sti), "r", encoding="utf-8") as f:
        for linje in f:
            linje = linje.strip()
            if linje:
                return linje
    return ""


def main(argv=None):
    args = lag_argparser().parse_args(argv)
    farger = Farger(not args.ingen_farger and sys.stdout.isatty() and not os.environ.get("NO_COLOR"))
    rap = Rapport(farger)
    tidsstempel = datetime.now().strftime("%Y%m%d-%H%M%S")
    parametre = {"base_url": args.base_url, "klient": args.klient, "ssid": args.ssid, "cli": args.cli,
                 "cli_kommandoer": args.cli_kommandoer, "rapportmappe": args.rapportmappe,
                 "maks_klienter": args.maks_klienter, "auth_metode": None}
    print(farger.f("HEAD", "%s %s — ExtremeCloud IQ, kun lesing — %s" % (VERKTOY, VERSJON, datetime.now().strftime("%Y-%m-%d %H:%M:%S"))))

    # --- autentisering
    token, auth_metode = None, None
    try:
        if args.token:
            token, auth_metode = args.token.strip(), "token (--token)"
        elif args.token_fil:
            token, auth_metode = les_forste_linje(args.token_fil), "token (--token-fil)"
        elif os.environ.get("XIQ_TOKEN", "").strip():
            token, auth_metode = os.environ["XIQ_TOKEN"].strip(), "token (XIQ_TOKEN)"
    except OSError as e:
        print(farger.f("FAIL", "[FAIL] %s: token-fil — kunne ikke leses: %s" % (SEK0, e)))
        return 1
    api = XiqApi(args.base_url, token, rap)
    utgang = 0
    avbrudd = None
    try:
        if not token:
            if not args.bruker:
                rap.seksjon(SEK0)
                rap.legg(SEK0, "autentisering", "FAIL", "ingen token og ingen --bruker",
                         "", "oppgi --token, --token-fil, XIQ_TOKEN eller --bruker EPOST")
                raise AuthFeil("mangler autentisering")
            auth_metode = "innlogging (bruker/passord)"
            if args.passord_fil:
                passord = les_forste_linje(args.passord_fil)
            else:
                if not sys.stdin.isatty():
                    rap.seksjon(SEK0)
                    rap.legg(SEK0, "autentisering", "FAIL", "ingen terminal for passord", "", "bruk --passord-fil eller et token")
                    raise AuthFeil("ingen terminal for passord")
                passord = getpass.getpass("Passord for %s: " % args.bruker)
            rap.seksjon(SEK0)
            try:
                utloper = api.logg_inn(args.bruker, passord)
                rap.legg(SEK0, "innlogging", "PASS", "OK for %s" % args.bruker, "",
                         "token gyldig i %s" % fmt_varighet(utloper) if utloper else "")
            except AuthFeil as e:
                rap.legg(SEK0, "innlogging", "FAIL", "avvist for %s" % args.bruker, "", str(e))
                raise
            except ApiFeil as e:
                rap.legg(SEK0, "innlogging", "FAIL", "feilet for %s" % args.bruker, "", str(e))
                raise AuthFeil(str(e), e.status, e.kropp)
            finally:
                passord = None
        parametre["auth_metode"] = auth_metode

        seksjon_konto(api, rap, auth_metode)
        aper = seksjon_ap(api, rap)
        seksjon_radioer(api, rap, aper)
        klienter = seksjon_klienter(api, rap, args, aper)
        seksjon_din_klient(api, rap, args, klienter)
        seksjon_varsler(api, rap, aper)
        seksjon_cli(api, rap, args, aper)
    except AuthFeil as e:
        print(farger.f("FAIL", "[FAIL] autentisering: %s" % e))
        if auth_metode == "innlogging (bruker/passord)":
            print("Innlogging avvist: sjekk e-post og passord. Krever kontoen SSO/2FA, bruk et API-token i stedet "
                  "(XIQ: Global Settings → API Token Management).")
        else:
            print("Token ugyldig/utløpt eller mangler rettigheter. Lag nytt API-token i XIQ (Global Settings → "
                  "API Token Management) eller logg inn med --bruker.")
        avbrudd = ("FAIL", "autentiseringsfeil", str(e))
        utgang = 1
    except ApiFeil as e:
        print(farger.f("FAIL", "[FAIL] API-feil: %s" % e))
        avbrudd = ("FAIL", "API-feil", str(e))
        utgang = 1
    except KeyboardInterrupt:
        avbrudd = ("WARN", "avbrutt av bruker (Ctrl-C)", "")
        utgang = 1
    except Exception as e:      # aldri krasj uten rapport
        avbrudd = ("FAIL", "uventet feil: %s: %s" % (type(e).__name__, e), "")
        utgang = 1

    seksjon_oppsummering(rap, avbrudd)
    try:
        md_sti, json_sti = rap.skriv(args.rapportmappe, parametre, tidsstempel)
        print("  Rapport: %s" % md_sti)
        print("  JSON:    %s" % json_sti)
        print("  Lim inn innholdet i .md-filen i chatten for analyse.")
    except OSError as e:
        print(farger.f("FAIL", "[FAIL] %s: kunne ikke skrive rapport — %s" % (SEK7, e)))
        return 1
    return utgang


if __name__ == "__main__":
    sys.exit(main())
