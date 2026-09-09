# =====================================================================================
# roaming-logg.ps1 — nettsjekk: roaming-logg for Windows (PowerShell)
#
# Formål : Logger Wi-Fi-tilkoblingen (SSID, BSSID, radiotype, bånd, kanal, signal, hastighet)
#          og gateway-ping med fast intervall mens du går rundt på området (Marivold Camping,
#          Adm-nett). Oppdager roaming mellom AP-er (BSSID-bytte), måler avbrudd (gap) ved
#          roaming, finner «sticky client»-episoder og oppsummerer pakketap og RTT mot gateway.
#          Skriver CSV (alle prøver) + oppsummering (.md) som limes inn i chatten for analyse.
# Kjøring: powershell.exe -ExecutionPolicy Bypass -File .\roaming-logg.ps1
#          powershell.exe -ExecutionPolicy Bypass -File .\roaming-logg.ps1 -Varighet 300 -Rapportmappe C:\Temp
#          pwsh -File .\roaming-logg.ps1 -Intervall 2 -Varighet 0          (0 = kjør til Ctrl-C)
# Krav   : Windows PowerShell 5.1 eller PowerShell 7.x på Windows (bruker netsh wlan og ping.exe).
#          Ingen adminrettigheter nødvendig. Kjører også under PowerShell 7 på Linux/macOS, men da
#          blir Wi-Fi-feltene «ukjent» og gateway-ping gjøres via .NET (best effort).
# Versjon 1.0 — 2026-09-09
# Endrer ingenting — kun lesing og målinger.
# =====================================================================================

<#
.SYNOPSIS
    nettsjekk — roaming-logg: logger Wi-Fi-tilkobling og gateway-ping per sekund og oppdager roaming mellom AP-er.

.DESCRIPTION
    Skriptet tar én prøve per -Intervall sekund i -Varighet sekunder (eller til Ctrl-C). Hver prøve inneholder
    tidsstempel, SSID, BSSID, radiotype, bånd, kanal, signal i prosent og omtrentlig dBm (prosent/2 − 100,
    en tilnærming), mottaks-/sendehastighet fra «netsh wlan show interfaces», gateway-RTT fra «ping.exe -n 1 -w 1000»
    og hver 5. prøve også RTT mot 1.1.1.1.

    Roaming oppdages ved BSSID-bytte (reserve: kanalbytte eller signalhopp ≥ 12 dB). For hver roaming skrives en
    ROAM-linje med gammel → ny BSSID/kanal/bånd, signal før/etter, gap (antall tapte gateway-ping rundt hendelsen
    × intervall, i ms) og tid til første vellykkede ping etterpå.

    Ved avslutning (varighet nådd eller Ctrl-C) skrives alltid en oppsummering:
        roaming-logg-<host>-<YYYYMMDD-HHMMSS>.csv   (alle prøver, kommaseparert, UTF-8)
        roaming-logg-<host>-<YYYYMMDD-HHMMSS>.md    (statuslinjer, roaming-hendelser, BSSID-oversikt, terskler, rå utdata)
    Lim inn innholdet i .md-filen i chatten for analyse (CSV ved behov).

    Skriptet er READ-ONLY: det endrer aldri nettverksinnstillinger, fornyer/slipper ikke DHCP-lease,
    tømmer ikke DNS-cache, slår ikke av/på adaptere og krever aldri administratorrettigheter.
    Wi-Fi-passord/PSK leses aldri. Alle nettverksoperasjoner har tidsavbrudd.

.PARAMETER Intervall
    Sekunder mellom hver prøve (1–60). Standard: 1.

.PARAMETER Varighet
    Total loggetid i sekunder. Standard: 600. 0 = kjør til Ctrl-C. Ctrl-C avslutter alltid ryddig og skriver oppsummeringen.

.PARAMETER Rapportmappe
    Mappe der CSV- og MD-filen skrives. Standard: gjeldende mappe.

.PARAMETER Gateway
    Overstyr standard gateway (IPv4) som pinges. Standard: leses fra rutetabellen (Get-NetRoute 0.0.0.0/0, lavest metrikk).

.PARAMETER Grensesnitt
    Navn (eller del av navn/beskrivelse) på Wi-Fi-grensesnittet som skal logges. Standard: første tilkoblede WLAN-grensesnitt.

.PARAMETER IngenFarger
    Skriv alle linjer uten farger (for logging/omdirigering).

.EXAMPLE
    .\roaming-logg.ps1
    Logger i 10 minutter med 1 s intervall, filer i gjeldende mappe.

.EXAMPLE
    .\roaming-logg.ps1 -Varighet 0 -Rapportmappe C:\Temp
    Logger til du trykker Ctrl-C; filer i C:\Temp.

.EXAMPLE
    .\roaming-logg.ps1 -Intervall 2 -Varighet 1800 -Gateway 10.0.0.1 -Grensesnitt Wi-Fi -IngenFarger
    Logger i 30 minutter med 2 s intervall, mot oppgitt gateway og grensesnitt, uten farger.

.NOTES
    Versjon 1.0 — 2026-09-09. Endrer ingenting — kun lesing og målinger.
    Kompatibel med Windows PowerShell 5.1 og PowerShell 7.x.
    Terskler: roaming-gap PASS ≤ 100 ms, WARN ≤ 500 ms, FAIL > 500 ms. Pakketap mot gateway PASS < 1 %, WARN < 3 %, FAIL ≥ 3 %.
    Sticky client: omtrentlig signal < −75 dBm i mer enn 10 s uten roaming → WARN.
#>

[CmdletBinding()]
param(
    [Parameter()][ValidateRange(1, 60)][int]$Intervall = 1,
    [Parameter()][ValidateRange(0, 86400)][int]$Varighet = 600,
    [Parameter()][string]$Rapportmappe = '',
    [Parameter()][string]$Gateway = '',
    [Parameter()][string]$Grensesnitt = '',
    [Parameter()][switch]$IngenFarger
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Continue'
$ProgressPreference = 'SilentlyContinue'

# ------------------------------------------------------------------------------------
# Globale variabler og terskler
# ------------------------------------------------------------------------------------
$script:Versjon = '1.0'
$script:PaaWindows = ($env:OS -eq 'Windows_NT')
$script:Farger = -not $IngenFarger
$script:Inv = [System.Globalization.CultureInfo]::InvariantCulture
$script:KonsollModus = $false        # settes til $true etter Ctrl-C: da kan ikke cmdlets brukes, kun [Console]/.NET
$script:StartTid = [DateTime]::Now
$script:SluttTid = $null
$script:AvsluttetAv = 'ukjent'
$script:Resultater = [System.Collections.Generic.List[object]]::new()
$script:Prover = [System.Collections.Generic.List[object]]::new()
$script:Roams = [System.Collections.Generic.List[object]]::new()
$script:Sticky = [System.Collections.Generic.List[object]]::new()
$script:Frakoblinger = [System.Collections.Generic.List[object]]::new()
$script:Hendelser = [System.Collections.Generic.List[string]]::new()
$script:RaaUtdata = [System.Collections.Specialized.OrderedDictionary]::new()
$script:SeksjonNavn = @(
    '0 System og verktøy',
    '1 Lenke og Wi-Fi',
    '2 IP og TCP/IP',
    '3 DHCP',
    '4 DNS',
    '5 Gateway og brannmur',
    '6 Fiber og WAN',
    '7 TCP-ytelse',
    '8 Hastighet',
    '9 Bufferbloat og jitter under last',
    '10 Video og strømming',
    '11 Roaming',
    '12 Hygiene',
    '13 Oppsummering'
)
$script:NetshSti = ''
$script:PingSti = ''
$script:GatewayInfo = @{ Ip = ''; Kilde = ''; Grensesnitt = ''; Antall = 0 }
$script:AdapterInfo = @{ Tilgjengelig = $false; Roaming = ''; Band = ''; Raa = ''; Feil = ''; Alias = '' }
$script:WlanNavn = ''
$script:WlanBeskrivelse = ''
$script:WlanFeil = ''
$script:CsvSti = ''
$script:MdSti = ''
$script:Utf8Bom = [System.Text.UTF8Encoding]::new($true)
$script:Utf8 = [System.Text.UTF8Encoding]::new($false)
$script:NyLinje = [Environment]::NewLine

# Terskler (skrives også i rapporten)
$script:T_GapPass = 100          # ms
$script:T_GapWarn = 500          # ms
$script:T_TapPass = 1.0          # %
$script:T_TapWarn = 3.0          # %
$script:T_StickyDbm = -75        # dBm (omtrentlig)
$script:T_StickySek = 10         # s
$script:T_RssiHopp = 12          # dB (reserve-deteksjon)
$script:T_RssiPass = -65         # dBm
$script:T_RssiWarn = -72         # dBm

# ------------------------------------------------------------------------------------
# Små hjelpefunksjoner (kun .NET og språkkonstruksjoner — må også virke etter Ctrl-C)
# ------------------------------------------------------------------------------------
function Get-Egenskap {
    # Trygg egenskapslesing under Set-StrictMode (manglende egenskap gir standardverdi, ikke feil).
    param($Objekt, [string]$Navn, $Standard = $null)
    if ($null -eq $Objekt) { return $Standard }
    try {
        if ($Objekt -is [System.Collections.IDictionary]) {
            if ($Objekt.Contains($Navn)) { return $Objekt[$Navn] }
            return $Standard
        }
        $p = $Objekt.PSObject.Properties[$Navn]
        if ($null -ne $p) { return $p.Value }
    } catch { }
    return $Standard
}

function Get-Feilmelding {
    param($Feil)
    $e = $null
    if ($Feil -is [System.Management.Automation.ErrorRecord]) { $e = $Feil.Exception }
    elseif ($Feil -is [System.Exception]) { $e = $Feil }
    else { return [string]$Feil }
    try {
        $n = 0
        while ($null -ne $e -and $n -lt 6 -and $null -ne $e.InnerException -and
            ($e -is [System.AggregateException] -or $e -is [System.Reflection.TargetInvocationException] -or
             $e -is [System.Management.Automation.MethodInvocationException])) {
            $e = $e.InnerException
            $n++
        }
        if ($null -ne $e) { return [string]$e.Message }
    } catch { }
    return [string]$Feil
}

function Format-Tall {
    # Tall til tekst med norsk desimalkomma for skjerm/rapport (CSV bruker alltid punktum).
    param([double]$Verdi, [int]$Desimaler = 0)
    $fmt = '0'
    if ($Desimaler -gt 0) { $fmt = '0.' + ('0' * $Desimaler) }
    return $Verdi.ToString($fmt, $script:Inv).Replace('.', ',')
}

function Format-TallInv {
    param([double]$Verdi, [int]$Desimaler = 0)
    $fmt = '0'
    if ($Desimaler -gt 0) { $fmt = '0.' + ('0' * $Desimaler) }
    return $Verdi.ToString($fmt, $script:Inv)
}

function Get-Naa {
    # Klokke for tidsstempler (egen funksjon slik at den kan byttes ut i tester).
    return [DateTime]::Now
}

function Format-Tid {
    param([DateTime]$Tid)
    return $Tid.ToString('HH:mm:ss', $script:Inv)
}

function Format-TidFull {
    param([DateTime]$Tid)
    return $Tid.ToString('yyyy-MM-dd HH:mm:ss', $script:Inv)
}

function Format-Band {
    # Intern verdi '2.4 GHz' vises som '2,4 GHz' på norsk.
    param([string]$Band)
    if (-not $Band) { return 'ukjent' }
    return $Band.Replace('2.4', '2,4')
}

function Format-Kanal {
    param($Kanal)
    if ($null -eq $Kanal -or [int]$Kanal -lt 0) { return '-' }
    return ([int]$Kanal).ToString($script:Inv)
}

function Format-Dbm {
    param($Dbm)
    if ($null -eq $Dbm) { return 'ukjent' }
    return (([int]$Dbm).ToString($script:Inv) + ' dBm')
}

function Get-SortertListe {
    param($Verdier)
    $l = [System.Collections.Generic.List[double]]::new()
    foreach ($v in $Verdier) { if ($null -ne $v) { $l.Add([double]$v) } }
    $l.Sort()
    return ,$l    # unært komma: PowerShell skal ikke pakke ut listen ved retur
}

function Get-Median {
    param($Verdier)
    $l = Get-SortertListe $Verdier
    $n = $l.Count
    if ($n -eq 0) { return $null }
    if ($n % 2 -eq 1) { return [double]$l[[int][math]::Floor($n / 2)] }
    $h = [int]($n / 2)
    return ([double]$l[$h - 1] + [double]$l[$h]) / 2.0
}

function Get-Persentil {
    # Nærmeste rang (p i prosent).
    param($Verdier, [double]$P)
    $l = Get-SortertListe $Verdier
    $n = $l.Count
    if ($n -eq 0) { return $null }
    $idx = [int][math]::Ceiling($P / 100.0 * $n) - 1
    if ($idx -lt 0) { $idx = 0 }
    if ($idx -ge $n) { $idx = $n - 1 }
    return [double]$l[$idx]
}

function Get-Snitt {
    param($Verdier)
    $sum = 0.0; $n = 0
    foreach ($v in $Verdier) { if ($null -ne $v) { $sum += [double]$v; $n++ } }
    if ($n -eq 0) { return $null }
    return $sum / $n
}

function Get-Maks {
    param($Verdier)
    $m = $null
    foreach ($v in $Verdier) { if ($null -ne $v) { if ($null -eq $m -or [double]$v -gt $m) { $m = [double]$v } } }
    return $m
}

function Get-Min {
    param($Verdier)
    $m = $null
    foreach ($v in $Verdier) { if ($null -ne $v) { if ($null -eq $m -or [double]$v -lt $m) { $m = [double]$v } } }
    return $m
}

function Test-Kommando {
    param([string]$Navn)
    try { return ($null -ne (Get-Command -Name $Navn -ErrorAction SilentlyContinue)) } catch { return $false }
}

function Get-ExeSti {
    param([string[]]$Navn)
    foreach ($n in $Navn) {
        try {
            $c = Get-Command -Name $n -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($null -ne $c) {
                $s = [string](Get-Egenskap $c 'Path' '')
                if (-not $s) { $s = [string](Get-Egenskap $c 'Source' '') }
                if ($s) { return $s }
            }
        } catch { }
    }
    return ''
}

function Test-Inneholder {
    param([string]$Tekst, [string]$Del)
    if (-not $Tekst -or -not $Del) { return $false }
    return ($Tekst.IndexOf($Del, [System.StringComparison]::OrdinalIgnoreCase) -ge 0)
}

# ------------------------------------------------------------------------------------
# Utskrift: Write-Host i normal drift, [Console] etter Ctrl-C (cmdlets er da stoppet)
# ------------------------------------------------------------------------------------
function Write-Linje {
    param([string]$Tekst, [string]$Farge = '')
    $brukFarge = ($script:Farger -and $Farge)
    if ($script:KonsollModus) {
        if ($brukFarge) { try { [Console]::ForegroundColor = [System.ConsoleColor]$Farge } catch { } }
        try { [Console]::WriteLine($Tekst) } catch { }
        if ($brukFarge) { try { [Console]::ResetColor() } catch { } }
        return
    }
    try {
        if ($brukFarge) { Write-Host $Tekst -ForegroundColor $Farge } else { Write-Host $Tekst }
    } catch {
        $script:KonsollModus = $true
        try { [Console]::WriteLine($Tekst) } catch { }
    }
}

function Get-StatusFarge {
    param([string]$Status)
    $farge = 'Cyan'
    switch ($Status) {
        'PASS' { $farge = 'Green' }
        'WARN' { $farge = 'Yellow' }
        'FAIL' { $farge = 'Red' }
        'SKIP' { $farge = 'DarkGray' }
        default { $farge = 'Cyan' }
    }
    return $farge
}

function Write-Status {
    # '[PASS] <seksjon>: <sjekk> — <verdi> (terskel <t>)'. Lagres i resultatlisten med mindre -IkkeLagre.
    param([string]$Status, [int]$Nr, [string]$Sjekk, [string]$Verdi = '', [string]$Terskel = '', [string]$Detaljer = '', [switch]$IkkeLagre)
    $seksjon = $script:SeksjonNavn[$Nr]
    $linje = "[$Status] ${seksjon}: $Sjekk"
    if ($Verdi) { $linje += " — $Verdi" }
    if ($Terskel) { $linje += " (terskel $Terskel)" }
    Write-Linje -Tekst $linje -Farge (Get-StatusFarge $Status)
    if (-not $IkkeLagre) {
        $script:Resultater.Add(@{ Nr = $Nr; Seksjon = $seksjon; Sjekk = $Sjekk; Status = $Status; Verdi = $Verdi; Terskel = $Terskel; Detaljer = $Detaljer; Linje = $linje })
    }
    return $linje
}

function Write-Overskrift {
    param([int]$Nr)
    Write-Linje -Tekst ("" + $script:NyLinje + "=== " + $script:SeksjonNavn[$Nr] + " ===") -Farge 'White'
}

function Add-Hendelse {
    param([string]$Linje)
    $script:Hendelser.Add($Linje)
}

# ------------------------------------------------------------------------------------
# Ekstern prosess med tidsavbrudd (netsh, ping.exe)
# ------------------------------------------------------------------------------------
function Invoke-Ekstern {
    param([string]$Sti, [string]$Argumenter = '', [int]$TimeoutMs = 5000)
    $res = @{ Kjort = $false; Utdata = ''; Feil = ''; ExitCode = -1; TidsAvbrutt = $false }
    if (-not $Sti) { $res['Feil'] = 'kommandoen finnes ikke'; return $res }
    $psi = [System.Diagnostics.ProcessStartInfo]::new()
    $psi.FileName = $Sti
    $psi.Arguments = $Argumenter
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.RedirectStandardInput = $true
    $psi.CreateNoWindow = $true
    try {
        # Konsollens (OEM-)koding gir riktig dekoding av æøå i ping/netsh på norsk Windows.
        $psi.StandardOutputEncoding = [Console]::OutputEncoding
        $psi.StandardErrorEncoding = [Console]::OutputEncoding
    } catch { }
    $p = [System.Diagnostics.Process]::new()
    $p.StartInfo = $psi
    try {
        $null = $p.Start()
    } catch {
        $res['Feil'] = Get-Feilmelding $_
        return $res
    }
    $res['Kjort'] = $true
    try { $p.StandardInput.Close() } catch { }
    $utTask = $p.StandardOutput.ReadToEndAsync()
    $feilTask = $p.StandardError.ReadToEndAsync()
    $ferdig = $false
    try { $ferdig = $p.WaitForExit($TimeoutMs) } catch { $ferdig = $false }
    if (-not $ferdig) {
        $res['TidsAvbrutt'] = $true
        try { $p.Kill() } catch { }
        try { $null = $p.WaitForExit(2000) } catch { }
    } else {
        try { $res['ExitCode'] = $p.ExitCode } catch { }
    }
    try { if ($utTask.Wait(3000)) { $res['Utdata'] = [string]$utTask.Result } } catch { }
    try { if ($feilTask.Wait(1000)) { $res['Feil'] = [string]$feilTask.Result } } catch { }
    if ($res['TidsAvbrutt']) { $res['Feil'] = ('tidsavbrudd etter {0} ms. {1}' -f $TimeoutMs, $res['Feil']).Trim() }
    try { $p.Dispose() } catch { }
    return $res
}

# ------------------------------------------------------------------------------------
# netsh wlan-tolking (lokalt-uavhengig: «nøkkel : verdi», nøkler matches med EN|NO-regex)
# ------------------------------------------------------------------------------------
function ConvertFrom-NetshInterfaces {
    # 'netsh wlan show interfaces' -> liste av ordbøker (én per WLAN-grensesnitt).
    param([string]$Tekst)
    $blokker = [System.Collections.Generic.List[object]]::new()
    $gjeldende = $null
    if (-not $Tekst) { return @() }
    foreach ($l in ($Tekst -split "`r?`n")) {
        $m = [regex]::Match($l, '^\s*([^:]+?)\s*:\s*(.*)$')
        if (-not $m.Success) { continue }
        $k = $m.Groups[1].Value.Trim()
        $v = $m.Groups[2].Value.Trim()
        if ([regex]::IsMatch($k, '^(name|navn)$', 'IgnoreCase')) {
            $gjeldende = [System.Collections.Specialized.OrderedDictionary]::new()
            $blokker.Add($gjeldende)
        }
        if ($null -eq $gjeldende) {
            # Overskriftslinjen «There is 1 interface on the system:» / «Det er 1 grensesnitt på systemet:» har tom verdi — hopp over.
            if (-not $v) { continue }
            $gjeldende = [System.Collections.Specialized.OrderedDictionary]::new()
            $blokker.Add($gjeldende)
        }
        if (-not $gjeldende.Contains($k)) { $gjeldende.Add($k, $v) }
    }
    return @($blokker.ToArray())
}

function Get-NetshVerdi {
    # Første verdi der nøkkelen matcher regex (uavhengig av store/små bokstaver).
    param($Blokk, [string]$NokkelRegex)
    if ($null -eq $Blokk) { return '' }
    foreach ($k in $Blokk.Keys) {
        if ([regex]::IsMatch([string]$k, $NokkelRegex, 'IgnoreCase')) { return [string]$Blokk[$k] }
    }
    return ''
}

function Test-NetshTilkoblet {
    param([string]$Tilstand)
    if (-not $Tilstand) { return $false }
    if ([regex]::IsMatch($Tilstand, '^(disconnected|frakoblet|ikke tilkoblet|not connected)', 'IgnoreCase')) { return $false }
    return [regex]::IsMatch($Tilstand, '(connected|tilkoblet|koblet til)', 'IgnoreCase')
}

function ConvertTo-Heltall {
    param([string]$Tekst, [int]$Standard = -1)
    if (-not $Tekst) { return $Standard }
    $m = [regex]::Match($Tekst, '(-?\d+)')
    if ($m.Success) { try { return [int]$m.Groups[1].Value } catch { } }
    return $Standard
}

function ConvertTo-Desimal {
    # Tåler både '866.7' og '866,7'.
    param([string]$Tekst, [double]$Standard = -1)
    if (-not $Tekst) { return $Standard }
    $t = $Tekst.Replace(',', '.')
    $m = [regex]::Match($t, '(-?\d+(?:\.\d+)?)')
    if ($m.Success) {
        $d = 0.0
        if ([double]::TryParse($m.Groups[1].Value, [System.Globalization.NumberStyles]::Float, $script:Inv, [ref]$d)) { return $d }
    }
    return $Standard
}

function Get-BandFraKanal {
    # Tilnærming når netsh ikke oppgir bånd (eldre Windows 10): 1–14 → 2,4 GHz; 36–144 (delelig med 4) og 149–177
    # (UNII-3, ≡ 1 mod 4) → 5 GHz; ellers ≡ 1 mod 4 opp til 233 → 6 GHz. 6 GHz-kanaler 149–177 finnes ikke i Europa
    # (5945–6425 MHz = kanal 1–93), så 5 GHz får forrang der kanalnumrene overlapper.
    param([int]$Kanal)
    if ($Kanal -lt 1) { return 'ukjent' }
    if ($Kanal -le 14) { return '2.4 GHz' }
    if ($Kanal -ge 36 -and $Kanal -le 144 -and ($Kanal % 4) -eq 0) { return '5 GHz' }
    if ($Kanal -ge 149 -and $Kanal -le 177 -and ($Kanal % 4) -eq 1) { return '5 GHz' }
    if (($Kanal % 4) -eq 1 -and $Kanal -le 233) { return '6 GHz' }
    return 'ukjent'
}

function ConvertTo-Band {
    param([string]$Tekst, [int]$Kanal)
    if ($Tekst) {
        $m = [regex]::Match($Tekst.Replace(',', '.'), '(\d+(?:\.\d+)?)\s*GHz', 'IgnoreCase')
        if ($m.Success) {
            $v = $m.Groups[1].Value
            if ($v.StartsWith('2')) { return '2.4 GHz' }
            if ($v.StartsWith('5')) { return '5 GHz' }
            if ($v.StartsWith('6')) { return '6 GHz' }
        }
    }
    return (Get-BandFraKanal -Kanal $Kanal)
}

function Get-WlanProve {
    # Én prøve fra 'netsh wlan show interfaces'. Alt er 'ukjent' når netsh ikke finnes (ikke Windows).
    $p = @{
        Tilgjengelig = $false; Tilkoblet = $false; Navn = 'ukjent'; Beskrivelse = ''; Tilstand = 'ukjent'
        Ssid = 'ukjent'; Bssid = 'ukjent'; Radiotype = 'ukjent'; Band = 'ukjent'; Kanal = -1
        SignalPst = -1; Dbm = $null; Rx = -1.0; Tx = -1.0; Raa = ''; Feil = ''
    }
    if (-not $script:PaaWindows -or -not $script:NetshSti) {
        $p['Feil'] = 'netsh finnes ikke (ikke Windows)'
        return $p
    }
    $ut = Invoke-Ekstern -Sti $script:NetshSti -Argumenter 'wlan show interfaces' -TimeoutMs 5000
    $p['Raa'] = ([string]$ut['Utdata'] + [string]$ut['Feil']).Trim()
    if (-not $ut['Kjort']) { $p['Feil'] = [string]$ut['Feil']; return $p }
    $blokker = @(ConvertFrom-NetshInterfaces -Tekst ([string]$ut['Utdata']))
    $valgt = $null
    if ($Grensesnitt) {
        foreach ($b in $blokker) {
            $navn = Get-NetshVerdi $b '^(name|navn)$'
            $beskr = Get-NetshVerdi $b '^(description|beskrivelse)$'
            if ((Test-Inneholder $navn $Grensesnitt) -or (Test-Inneholder $beskr $Grensesnitt)) { $valgt = $b; break }
        }
    }
    if ($null -eq $valgt) {
        foreach ($b in $blokker) {
            if (Test-NetshTilkoblet (Get-NetshVerdi $b '^(state|tilstand)$')) { $valgt = $b; break }
        }
    }
    if ($null -eq $valgt -and $blokker.Count -gt 0) { $valgt = $blokker[0] }
    if ($null -eq $valgt) {
        $p['Feil'] = 'ingen WLAN-grensesnitt i netsh-utdata (ingen Wi-Fi-adapter, eller tjenesten WLAN AutoConfig kjører ikke)'
        return $p
    }
    $p['Tilgjengelig'] = $true
    $navn = Get-NetshVerdi $valgt '^(name|navn)$'
    if ($navn) { $p['Navn'] = $navn }
    $p['Beskrivelse'] = Get-NetshVerdi $valgt '^(description|beskrivelse)$'
    $tilstand = Get-NetshVerdi $valgt '^(state|tilstand)$'
    if ($tilstand) { $p['Tilstand'] = $tilstand }
    $p['Tilkoblet'] = Test-NetshTilkoblet $tilstand
    if (-not $p['Tilkoblet']) {
        $p['Ssid'] = ''; $p['Bssid'] = ''
        return $p
    }
    $ssid = Get-NetshVerdi $valgt '^ssid$'
    if ($ssid) { $p['Ssid'] = $ssid }
    $bssid = Get-NetshVerdi $valgt '^bssid$'
    if ($bssid) { $p['Bssid'] = $bssid.ToLowerInvariant() }
    $radio = Get-NetshVerdi $valgt '^(radio\s*type|radiotype)$'
    if ($radio) { $p['Radiotype'] = $radio }
    $p['Kanal'] = ConvertTo-Heltall (Get-NetshVerdi $valgt '^(channel|kanal)$') -1
    $p['Band'] = ConvertTo-Band -Tekst (Get-NetshVerdi $valgt '^(band|bånd|frekvensbånd)$') -Kanal $p['Kanal']
    $sig = ConvertTo-Heltall (Get-NetshVerdi $valgt '^(signal|signalstyrke)$') -1
    if ($sig -ge 0) {
        $p['SignalPst'] = $sig
        # Tilnærming: dBm ≈ prosent/2 − 100 (Windows' egen lineære kartlegging; ikke en eksakt måling).
        $p['Dbm'] = [int][math]::Round($sig / 2.0 - 100.0, [System.MidpointRounding]::AwayFromZero)
    }
    $p['Rx'] = ConvertTo-Desimal (Get-NetshVerdi $valgt '^(receive\s*rate|mottakshastighet)') -1
    $p['Tx'] = ConvertTo-Desimal (Get-NetshVerdi $valgt '^(transmit\s*rate|sendehastighet)') -1
    return $p
}

# ------------------------------------------------------------------------------------
# Ping (ping.exe på Windows, .NET Ping ellers) og gateway
# ------------------------------------------------------------------------------------
function Invoke-Ping {
    param([string]$Mal)
    $r = @{ Forsokt = $false; Ok = $false; Ms = $null; Raa = '' }
    if (-not $Mal) { return $r }
    $r['Forsokt'] = $true
    if ($script:PaaWindows -and $script:PingSti) {
        $ut = Invoke-Ekstern -Sti $script:PingSti -Argumenter ('-n 1 -w 1000 ' + $Mal) -TimeoutMs 6000
        $tekst = [string]$ut['Utdata']
        $r['Raa'] = $tekst.Trim()
        # Lokalt-uavhengig: «time=3ms», «time<1ms», «tid=3ms», «tid<1ms»
        $m = [regex]::Match($tekst, '(?:time|tid)\s*[=<]\s*(\d+)\s*ms', 'IgnoreCase')
        if ($m.Success) {
            $r['Ok'] = $true
            $ms = [int]$m.Groups[1].Value
            if ($m.Value.Contains('<')) { $ms = 0 }
            $r['Ms'] = $ms
        }
        return $r
    }
    # Ikke Windows (eller ping.exe mangler): .NET Ping med 1000 ms tidsavbrudd, best effort.
    $ping = $null
    try {
        $ping = [System.Net.NetworkInformation.Ping]::new()
        $svar = $ping.Send($Mal, 1000)
        if ($null -ne $svar) {
            $r['Raa'] = [string]$svar.Status
            if ($svar.Status -eq [System.Net.NetworkInformation.IPStatus]::Success) {
                $r['Ok'] = $true
                $r['Ms'] = [int]$svar.RoundtripTime
            }
        }
    } catch {
        $r['Raa'] = Get-Feilmelding $_
    }
    if ($null -ne $ping) { try { $ping.Dispose() } catch { } }
    return $r
}

function Get-StandardGateway {
    # -Gateway, ellers Get-NetRoute 0.0.0.0/0 (lavest RouteMetric+InterfaceMetric), ellers .NET GatewayAddresses.
    $res = @{ Ip = ''; Kilde = ''; Grensesnitt = ''; Antall = 0 }
    if ($Gateway) {
        $res['Ip'] = $Gateway.Trim()
        $res['Kilde'] = 'parameter -Gateway'
        return $res
    }
    if ($script:PaaWindows -and (Test-Kommando 'Get-NetRoute')) {
        try {
            $ruter = @(Get-NetRoute -DestinationPrefix '0.0.0.0/0' -ErrorAction Stop |
                Sort-Object -Property @{ Expression = { [int](Get-Egenskap $_ 'RouteMetric' 0) + [int](Get-Egenskap $_ 'InterfaceMetric' 0) } })
            $res['Antall'] = $ruter.Count
            $valgt = $null
            if ($Grensesnitt) {
                foreach ($r in $ruter) {
                    if (Test-Inneholder ([string](Get-Egenskap $r 'InterfaceAlias' '')) $Grensesnitt) { $valgt = $r; break }
                }
            }
            if ($null -eq $valgt -and $ruter.Count -gt 0) { $valgt = $ruter[0] }
            if ($null -ne $valgt) {
                $res['Ip'] = [string](Get-Egenskap $valgt 'NextHop' '')
                $res['Grensesnitt'] = [string](Get-Egenskap $valgt 'InterfaceAlias' '')
                $res['Kilde'] = 'Get-NetRoute 0.0.0.0/0 (lavest metrikk)'
            }
        } catch { }
    }
    if (-not $res['Ip'] -or $res['Ip'] -eq '0.0.0.0') {
        $res['Ip'] = ''
        try {
            $antall = 0
            foreach ($nic in [System.Net.NetworkInformation.NetworkInterface]::GetAllNetworkInterfaces()) {
                if ([string]$nic.OperationalStatus -ne 'Up') { continue }
                if ([string]$nic.NetworkInterfaceType -eq 'Loopback') { continue }
                $navnOk = $true
                if ($Grensesnitt) { $navnOk = (Test-Inneholder $nic.Name $Grensesnitt) -or (Test-Inneholder $nic.Description $Grensesnitt) }
                foreach ($gw in $nic.GetIPProperties().GatewayAddresses) {
                    $a = $gw.Address
                    if ([string]$a.AddressFamily -ne 'InterNetwork') { continue }
                    $ip = $a.ToString()
                    if ($ip -eq '0.0.0.0') { continue }
                    $antall++
                    if ($navnOk -and -not $res['Ip']) {
                        $res['Ip'] = $ip
                        $res['Grensesnitt'] = $nic.Name
                        $res['Kilde'] = '.NET NetworkInterface.GatewayAddresses'
                    }
                }
            }
            if ($res['Antall'] -eq 0) { $res['Antall'] = $antall }
        } catch { }
    }
    return $res
}

function Get-AdapterEgenskaper {
    # Get-NetAdapterAdvancedProperty: 'Roaming Aggressiveness' og 'Preferred Band' (driveravhengige navn), kun INFO.
    param([string]$Alias)
    $res = @{ Tilgjengelig = $false; Roaming = ''; Band = ''; Raa = ''; Feil = ''; Alias = $Alias }
    if (-not $script:PaaWindows -or -not (Test-Kommando 'Get-NetAdapterAdvancedProperty')) {
        $res['Feil'] = 'Get-NetAdapterAdvancedProperty finnes ikke (ikke Windows / NetAdapter-modulen mangler)'
        return $res
    }
    try {
        $egensk = @()
        if ($Alias) {
            $egensk = @(Get-NetAdapterAdvancedProperty -Name $Alias -ErrorAction Stop)
        } else {
            $egensk = @(Get-NetAdapterAdvancedProperty -ErrorAction Stop | Where-Object {
                    ([string](Get-Egenskap $_ 'InterfaceDescription' '')) -match 'wi-?fi|wireless|wlan|802\.11' })
        }
        $res['Tilgjengelig'] = $true
        $sb = [System.Text.StringBuilder]::new()
        foreach ($e in $egensk) {
            $dn = [string](Get-Egenskap $e 'DisplayName' '')
            $dv = [string](Get-Egenskap $e 'DisplayValue' '')
            $rk = [string](Get-Egenskap $e 'RegistryKeyword' '')
            $alias = [string](Get-Egenskap $e 'Name' '')
            [void]$sb.AppendLine(('{0}: {1} = {2}  [{3}]' -f $alias, $dn, $dv, $rk))
            if (-not $res['Roaming'] -and (($dn -match 'roam') -or ($rk -match 'roam'))) { $res['Roaming'] = ('{0} = {1}' -f $dn, $dv) }
            if (-not $res['Band'] -and (($dn -match 'prefer.*band|band.*prefer') -or ($rk -match 'preferredband|bandpref'))) { $res['Band'] = ('{0} = {1}' -f $dn, $dv) }
        }
        $res['Raa'] = $sb.ToString().TrimEnd()
        if ($egensk.Count -eq 0) { $res['Feil'] = 'ingen avanserte egenskaper funnet for adapteren' }
    } catch {
        $res['Feil'] = Get-Feilmelding $_
    }
    return $res
}

# ------------------------------------------------------------------------------------
# CSV
# ------------------------------------------------------------------------------------
function ConvertTo-CsvFelt {
    param($Verdi)
    $s = ''
    if ($null -ne $Verdi) { $s = [string]$Verdi }
    if ($s -match '[",\r\n]') { return ('"' + $s.Replace('"', '""') + '"') }
    return $s
}

function Get-CsvHode {
    return 'tid,ssid,bssid,radiotype,band,kanal,signal_pst,rssi_dbm_ca,rx_mbps,tx_mbps,gw_ip,gw_ok,gw_ms,inet_ok,inet_ms,hendelse'
}

function ConvertTo-CsvLinje {
    param($S)
    $felt = [System.Collections.Generic.List[string]]::new()
    $felt.Add((ConvertTo-CsvFelt ([DateTime]$S['Tid']).ToString('yyyy-MM-dd HH:mm:ss.fff', $script:Inv)))
    $felt.Add((ConvertTo-CsvFelt $S['Ssid']))
    $felt.Add((ConvertTo-CsvFelt $S['Bssid']))
    $felt.Add((ConvertTo-CsvFelt $S['Radiotype']))
    $felt.Add((ConvertTo-CsvFelt $S['Band']))
    $felt.Add((ConvertTo-CsvFelt $(if ([int]$S['Kanal'] -ge 0) { ([int]$S['Kanal']).ToString($script:Inv) } else { '' })))
    $felt.Add((ConvertTo-CsvFelt $(if ([int]$S['SignalPst'] -ge 0) { ([int]$S['SignalPst']).ToString($script:Inv) } else { '' })))
    $felt.Add((ConvertTo-CsvFelt $(if ($null -ne $S['Dbm']) { ([int]$S['Dbm']).ToString($script:Inv) } else { '' })))
    $felt.Add((ConvertTo-CsvFelt $(if ([double]$S['Rx'] -ge 0) { Format-TallInv ([double]$S['Rx']) 1 } else { '' })))
    $felt.Add((ConvertTo-CsvFelt $(if ([double]$S['Tx'] -ge 0) { Format-TallInv ([double]$S['Tx']) 1 } else { '' })))
    $felt.Add((ConvertTo-CsvFelt $S['GwIp']))
    $felt.Add((ConvertTo-CsvFelt $(if ($S['GwForsokt']) { if ($S['GwOk']) { '1' } else { '0' } } else { '' })))
    $felt.Add((ConvertTo-CsvFelt $(if ($S['GwOk']) { ([int]$S['GwMs']).ToString($script:Inv) } else { '' })))
    $felt.Add((ConvertTo-CsvFelt $(if ($S['InetForsokt']) { if ($S['InetOk']) { '1' } else { '0' } } else { '' })))
    $felt.Add((ConvertTo-CsvFelt $(if ($S['InetOk']) { ([int]$S['InetMs']).ToString($script:Inv) } else { '' })))
    $felt.Add((ConvertTo-CsvFelt $S['Hendelse']))
    return ($felt.ToArray() -join ',')
}

function Add-CsvLinje {
    param([string]$Linje)
    try { [System.IO.File]::AppendAllText($script:CsvSti, $Linje + $script:NyLinje, $script:Utf8) } catch { }
}

# ------------------------------------------------------------------------------------
# Roaming-, gap- og sticky-logikk
# ------------------------------------------------------------------------------------
function Get-GapStatus {
    param($GapMs)
    if ($null -eq $GapMs) { return 'INFO' }
    if ([double]$GapMs -le $script:T_GapPass) { return 'PASS' }
    if ([double]$GapMs -le $script:T_GapWarn) { return 'WARN' }
    return 'FAIL'
}

function Get-TapteFor {
    # Antall tapte gateway-ping på rad rett før hendelsen (bakover fra siste prøve).
    $n = 0
    for ($i = $script:Prover.Count - 1; $i -ge 0; $i--) {
        $s = $script:Prover[$i]
        if (-not $s['GwForsokt']) { break }
        if ($s['GwOk']) { break }
        $n++
    }
    return $n
}

function Format-RoamLinje {
    param($Ev, [bool]$Forelopig)
    $fra = '{0} (kan {1}, {2})' -f $Ev['FraBssid'], (Format-Kanal $Ev['FraKanal']), (Format-Band $Ev['FraBand'])
    $til = '{0} (kan {1}, {2})' -f $Ev['TilBssid'], (Format-Kanal $Ev['TilKanal']), (Format-Band $Ev['TilBand'])
    $sig = 'signal {0} → {1}' -f (Format-Dbm $Ev['DbmFor']), (Format-Dbm $Ev['DbmEtter'])
    $navn = '{0} {1} {2} → {3}' -f $Ev['Type'], (Format-Tid $Ev['Tid']), $fra, $til
    if ($Forelopig) {
        $verdi = '{0}, {1} tapte gw-ping før, gateway svarer ikke ennå (venter på første OK-ping)' -f $sig, $Ev['TapteFor']
        return @{ Status = 'INFO'; Sjekk = $navn; Verdi = $verdi }
    }
    $gapTekst = 'gap ukjent (gateway-ping ikke målt)'
    if ($null -ne $Ev['GapMs']) {
        $gapTekst = 'gap {0} ms ({1}+{2} tapte gw-ping × {3} ms)' -f ([int]$Ev['GapMs']).ToString($script:Inv), $Ev['TapteFor'], $Ev['TapteEtter'], ($Intervall * 1000)
    }
    $okTekst = 'ingen OK-ping før loggen sluttet'
    if ($null -ne $Ev['TidTilOkMs']) { $okTekst = 'første OK-ping etter {0} ms' -f ([int]$Ev['TidTilOkMs']).ToString($script:Inv) }
    $verdi = '{0}, {1}, {2}' -f $sig, $gapTekst, $okTekst
    return @{ Status = (Get-GapStatus $Ev['GapMs']); Sjekk = $navn; Verdi = $verdi }
}

function Complete-Roam {
    param($Ev, $Prove)
    $Ev['GapMs'] = ([int]$Ev['TapteFor'] + [int]$Ev['TapteEtter']) * $Intervall * 1000
    if ($null -ne $Prove) {
        $Ev['TidTilOkMs'] = [int]([math]::Round(([DateTime]$Prove['Tid'] - [DateTime]$Ev['Tid']).TotalMilliseconds) + [int]$Prove['GwMs'])
    }
    $Ev['Ferdig'] = $true
    $f = Format-RoamLinje -Ev $Ev -Forelopig $false
    $Ev['Status'] = $f['Status']
    $linje = Write-Status -Status $f['Status'] -Nr 11 -Sjekk $f['Sjekk'] -Verdi $f['Verdi'] -Terskel ('gap ≤{0} ms PASS, ≤{1} ms WARN' -f $script:T_GapPass, $script:T_GapWarn) -IkkeLagre
    Add-Hendelse $linje
}

function Update-Roams {
    # Oppdaterer åpne roaming-hendelser med denne prøvens gateway-ping.
    param($Prove)
    foreach ($ev in $script:Roams) {
        if ($ev['Ferdig']) { continue }
        if (-not $Prove['GwForsokt']) {
            # Ingen gateway å pinge: gap kan ikke måles.
            $ev['GapMs'] = $null
            $ev['Ferdig'] = $true
            $f = Format-RoamLinje -Ev $ev -Forelopig $false
            $ev['Status'] = $f['Status']
            $linje = Write-Status -Status $f['Status'] -Nr 11 -Sjekk $f['Sjekk'] -Verdi $f['Verdi'] -IkkeLagre
            Add-Hendelse $linje
            continue
        }
        if ($Prove['GwOk']) {
            Complete-Roam -Ev $ev -Prove $Prove
        } else {
            $ev['TapteEtter'] = [int]$ev['TapteEtter'] + 1
            if (-not $ev['Varslet']) {
                $ev['Varslet'] = $true
                $f = Format-RoamLinje -Ev $ev -Forelopig $true
                $null = Write-Status -Status $f['Status'] -Nr 11 -Sjekk $f['Sjekk'] -Verdi $f['Verdi'] -IkkeLagre
            }
        }
    }
}

function Complete-AapneRoams {
    # Ved avslutning: lukk hendelser som fortsatt venter på første OK-ping.
    foreach ($ev in $script:Roams) {
        if ($ev['Ferdig']) { continue }
        $ev['GapMs'] = ([int]$ev['TapteFor'] + [int]$ev['TapteEtter']) * $Intervall * 1000
        $ev['TidTilOkMs'] = $null
        $ev['Ferdig'] = $true
        $f = Format-RoamLinje -Ev $ev -Forelopig $false
        $ev['Status'] = $f['Status']
        $linje = Write-Status -Status $f['Status'] -Nr 11 -Sjekk $f['Sjekk'] -Verdi $f['Verdi'] -Terskel ('gap ≤{0} ms PASS, ≤{1} ms WARN' -f $script:T_GapPass, $script:T_GapWarn) -IkkeLagre
        Add-Hendelse $linje
    }
}

function New-RoamHendelse {
    param([string]$Type, $Forrige, $Naa)
    $ev = @{
        Type = $Type; Tid = [DateTime]$Naa['Tid']; Nr = [int]$Naa['Nr']
        FraBssid = 'ukjent'; FraKanal = -1; FraBand = 'ukjent'; DbmFor = $null
        TilBssid = [string]$Naa['Bssid']; TilKanal = [int]$Naa['Kanal']; TilBand = [string]$Naa['Band']; DbmEtter = $Naa['Dbm']
        TapteFor = (Get-TapteFor); TapteEtter = 0; Ferdig = $false; GapMs = $null; TidTilOkMs = $null; Status = 'INFO'; Varslet = $false
    }
    if ($null -ne $Forrige) {
        $ev['FraBssid'] = [string]$Forrige['Bssid']; $ev['FraKanal'] = [int]$Forrige['Kanal']; $ev['FraBand'] = [string]$Forrige['Band']; $ev['DbmFor'] = $Forrige['Dbm']
    }
    if (-not $ev['FraBssid']) { $ev['FraBssid'] = 'ukjent' }
    if (-not $ev['TilBssid']) { $ev['TilBssid'] = 'ukjent' }
    return $ev
}

function Test-Roam {
    # BSSID-bytte; reserve: kanalbytte, ellers signalhopp ≥ 12 dB.
    param($Forrige, $Naa)
    if ($null -eq $Forrige) { return $false }
    if (-not $Forrige['Tilkoblet'] -or -not $Naa['Tilkoblet']) { return $false }
    $b1 = [string]$Forrige['Bssid']; $b2 = [string]$Naa['Bssid']
    if ($b1 -and $b2 -and $b1 -ne 'ukjent' -and $b2 -ne 'ukjent') { return ($b1 -ne $b2) }
    $k1 = [int]$Forrige['Kanal']; $k2 = [int]$Naa['Kanal']
    if ($k1 -ge 0 -and $k2 -ge 0) { return ($k1 -ne $k2) }
    if ($null -ne $Forrige['Dbm'] -and $null -ne $Naa['Dbm']) { return ([math]::Abs([int]$Naa['Dbm'] - [int]$Forrige['Dbm']) -ge $script:T_RssiHopp) }
    return $false
}

$script:StickyStart = $null
$script:StickyMin = $null
$script:StickyBssid = ''
$script:StickyKanal = -1
$script:StickyVarslet = $false

function Close-Sticky {
    param([DateTime]$Slutt, [string]$Aarsak)
    if ($null -eq $script:StickyStart) { return }
    $varighet = ($Slutt - [DateTime]$script:StickyStart).TotalSeconds
    if ($varighet -gt $script:T_StickySek) {
        $ep = @{ Start = [DateTime]$script:StickyStart; Slutt = $Slutt; Sekunder = $varighet; Bssid = $script:StickyBssid; Kanal = $script:StickyKanal; MinDbm = $script:StickyMin; Aarsak = $Aarsak }
        $script:Sticky.Add($ep)
        if (-not $script:StickyVarslet) { Write-StickyVarsel -Ep $ep }
        $linje = '[INFO] 11 Roaming: sticky-episode avsluttet {0} — {1} s på {2} (kan {3}), min {4}, avsluttet av {5}' -f (Format-Tid $Slutt), (Format-Tall $varighet 0), $script:StickyBssid, (Format-Kanal $script:StickyKanal), (Format-Dbm $script:StickyMin), $Aarsak
        Write-Linje -Tekst $linje -Farge 'Cyan'
        Add-Hendelse $linje
    }
    $script:StickyStart = $null; $script:StickyMin = $null; $script:StickyBssid = ''; $script:StickyKanal = -1; $script:StickyVarslet = $false
}

function Write-StickyVarsel {
    param($Ep)
    $verdi = '{0} i {1} s på {2} (kan {3}) siden {4}' -f (Format-Dbm $Ep['MinDbm']), (Format-Tall ([double]$Ep['Sekunder']) 0), $Ep['Bssid'], (Format-Kanal $Ep['Kanal']), (Format-Tid ([DateTime]$Ep['Start']))
    $linje = Write-Status -Status 'WARN' -Nr 11 -Sjekk 'sticky client – sjekk min-RSSI / BSS transition (802.11v) på AP-ene' -Verdi $verdi -Terskel ('< {0} dBm i > {1} s uten roam' -f $script:T_StickyDbm, $script:T_StickySek) -IkkeLagre
    Add-Hendelse $linje
    $script:StickyVarslet = $true
}

function Update-Sticky {
    param($Prove, [bool]$RoamNaa)
    $tid = [DateTime]$Prove['Tid']
    if ($RoamNaa) { Close-Sticky -Slutt $tid -Aarsak 'roaming'; return }
    if (-not $Prove['Tilkoblet'] -or $null -eq $Prove['Dbm']) { Close-Sticky -Slutt $tid -Aarsak 'frakobling/ukjent signal'; return }
    $dbm = [int]$Prove['Dbm']
    if ($dbm -ge $script:T_StickyDbm) { Close-Sticky -Slutt $tid -Aarsak 'signalet ble bedre'; return }
    if ($null -eq $script:StickyStart) {
        $script:StickyStart = $tid; $script:StickyMin = $dbm; $script:StickyBssid = [string]$Prove['Bssid']; $script:StickyKanal = [int]$Prove['Kanal']; $script:StickyVarslet = $false
        return
    }
    if ($dbm -lt [int]$script:StickyMin) { $script:StickyMin = $dbm }
    $varighet = ($tid - [DateTime]$script:StickyStart).TotalSeconds
    if ($varighet -gt $script:T_StickySek -and -not $script:StickyVarslet) {
        Write-StickyVarsel -Ep @{ Start = [DateTime]$script:StickyStart; Sekunder = $varighet; Bssid = $script:StickyBssid; Kanal = $script:StickyKanal; MinDbm = $script:StickyMin }
    }
}

$script:FrakobletStart = $null
$script:SisteBssid = ''
$script:SisteTilkobletProve = $null

function Format-ProveLinje {
    param($S)
    $deler = [System.Collections.Generic.List[string]]::new()
    $deler.Add(([DateTime]$S['Tid']).ToString('HH:mm:ss', $script:Inv))
    if ($S['Tilkoblet']) {
        $deler.Add([string]$S['Ssid'])
        $deler.Add([string]$S['Bssid'])
        $deler.Add(('kan {0}' -f (Format-Kanal $S['Kanal'])))
        $deler.Add((Format-Band $S['Band']))
        $deler.Add([string]$S['Radiotype'])
        if ([int]$S['SignalPst'] -ge 0) { $deler.Add(('{0} % (~{1})' -f $S['SignalPst'], (Format-Dbm $S['Dbm']))) } else { $deler.Add('signal ukjent') }
        $rx = '-'; $tx = '-'
        if ([double]$S['Rx'] -ge 0) { $rx = Format-Tall ([double]$S['Rx']) 0 }
        if ([double]$S['Tx'] -ge 0) { $tx = Format-Tall ([double]$S['Tx']) 0 }
        $deler.Add(('rx {0}/tx {1} Mbps' -f $rx, $tx))
    } elseif ($S['WlanTilgjengelig']) {
        $deler.Add(('Wi-Fi: {0}' -f $S['Tilstand']))
    } else {
        $deler.Add('Wi-Fi: ukjent')
    }
    if ($S['GwForsokt']) {
        if ($S['GwOk']) { $deler.Add(('gw {0} ms' -f $S['GwMs'])) } else { $deler.Add('gw TAPT') }
    } else {
        $deler.Add('gw ikke målt')
    }
    if ($S['InetForsokt']) {
        if ($S['InetOk']) { $deler.Add(('1.1.1.1 {0} ms' -f $S['InetMs'])) } else { $deler.Add('1.1.1.1 TAPT') }
    }
    return ($deler.ToArray() -join '  ')
}

function Invoke-Prove {
    param([int]$Nr)
    $tid = Get-Naa
    $w = Get-WlanProve
    if ($w['Tilgjengelig']) {
        if (-not $script:WlanNavn -or $script:WlanNavn -eq 'ukjent') { $script:WlanNavn = [string]$w['Navn']; $script:WlanBeskrivelse = [string]$w['Beskrivelse'] }
    } elseif (-not $script:WlanFeil) {
        $script:WlanFeil = [string]$w['Feil']
    }
    $gw = Invoke-Ping -Mal $script:GatewayInfo['Ip']
    $inet = @{ Forsokt = $false; Ok = $false; Ms = $null; Raa = '' }
    if ((($Nr - 1) % 5) -eq 0) { $inet = Invoke-Ping -Mal '1.1.1.1' }
    $s = @{
        Nr = $Nr; Tid = $tid
        WlanTilgjengelig = [bool]$w['Tilgjengelig']; Tilkoblet = [bool]$w['Tilkoblet']; Tilstand = [string]$w['Tilstand']
        Ssid = [string]$w['Ssid']; Bssid = [string]$w['Bssid']; Radiotype = [string]$w['Radiotype']; Band = [string]$w['Band']
        Kanal = [int]$w['Kanal']; SignalPst = [int]$w['SignalPst']; Dbm = $w['Dbm']; Rx = [double]$w['Rx']; Tx = [double]$w['Tx']
        GwIp = [string]$script:GatewayInfo['Ip']; GwForsokt = [bool]$gw['Forsokt']; GwOk = [bool]$gw['Ok']; GwMs = $gw['Ms']
        InetForsokt = [bool]$inet['Forsokt']; InetOk = [bool]$inet['Ok']; InetMs = $inet['Ms']
        Hendelse = ''; Raa = [string]$w['Raa']
    }
    if ($Nr -eq 1 -and $s['Raa']) { $script:RaaUtdata['netsh wlan show interfaces (første prøve)'] = $s['Raa'] }

    $forrige = $null
    if ($script:Prover.Count -gt 0) { $forrige = $script:Prover[$script:Prover.Count - 1] }
    # Hvis forrige prøve bare var en midlertidig netsh-feil (ikke en reell frakobling), sammenlign med siste tilkoblede prøve.
    if ($null -ne $forrige -and -not $forrige['WlanTilgjengelig'] -and $null -ne $script:SisteTilkobletProve -and $s['Tilkoblet']) { $forrige = $script:SisteTilkobletProve }

    # Roaming / til- og frakobling
    $roamNaa = $false
    $hendelser = [System.Collections.Generic.List[string]]::new()
    if ($null -ne $forrige) {
        if (Test-Roam -Forrige $forrige -Naa $s) {
            $roamNaa = $true
            $hendelser.Add('ROAM')
            $script:Roams.Add((New-RoamHendelse -Type 'ROAM' -Forrige $forrige -Naa $s))
        } elseif ($forrige['Tilkoblet'] -and -not $s['Tilkoblet'] -and $s['WlanTilgjengelig']) {
            $hendelser.Add('FRAKOBLET')
            $script:FrakobletStart = $tid
            $linje = Write-Status -Status 'WARN' -Nr 11 -Sjekk ('FRAKOBLET {0}' -f (Format-Tid $tid)) -Verdi ('Wi-Fi mistet forbindelsen (tilstand: {0}), sist på {1}' -f $s['Tilstand'], $script:SisteBssid) -IkkeLagre
            Add-Hendelse $linje
        } elseif (-not $forrige['Tilkoblet'] -and $s['Tilkoblet'] -and $forrige['WlanTilgjengelig']) {
            $hendelser.Add('TILKOBLET')
            $varighet = $null
            if ($null -ne $script:FrakobletStart) { $varighet = ($tid - [DateTime]$script:FrakobletStart).TotalSeconds }
            $script:Frakoblinger.Add(@{ Start = $script:FrakobletStart; Slutt = $tid; Sekunder = $varighet; TilBssid = [string]$s['Bssid']; FraBssid = $script:SisteBssid })
            $script:FrakobletStart = $null
            $ev = New-RoamHendelse -Type 'TILKOBLET' -Forrige $null -Naa $s
            $ev['FraBssid'] = $script:SisteBssid
            if (-not $ev['FraBssid']) { $ev['FraBssid'] = 'ukjent' }
            $script:Roams.Add($ev)
        }
    }
    if ($s['Tilkoblet']) { $script:SisteTilkobletProve = $s }
    if ($s['Tilkoblet'] -and $s['Bssid'] -and $s['Bssid'] -ne 'ukjent') { $script:SisteBssid = [string]$s['Bssid'] }

    # Gateway-ping oppdaterer åpne hendelser (gap / tid til første OK-ping)
    Update-Roams -Prove $s

    # Sticky client
    Update-Sticky -Prove $s -RoamNaa $roamNaa
    if ($null -ne $script:StickyStart -and $script:StickyVarslet) { $hendelser.Add('STICKY') }

    $s['Hendelse'] = ($hendelser.ToArray() -join '+')
    $script:Prover.Add($s)
    Add-CsvLinje (ConvertTo-CsvLinje $s)

    $farge = ''
    if ($s['GwForsokt'] -and -not $s['GwOk']) { $farge = 'Red' }
    elseif ($roamNaa) { $farge = 'Magenta' }
    elseif ($s['Band'] -eq '2.4 GHz') { $farge = 'Yellow' }
    Write-Linje -Tekst (Format-ProveLinje $s) -Farge $farge
}

# ------------------------------------------------------------------------------------
# Oppsummering (kun .NET/språkkonstruksjoner — kjøres også etter Ctrl-C)
# ------------------------------------------------------------------------------------
function Write-Oppsummering {
    $slutt = Get-Naa
    $script:SluttTid = $slutt
    Complete-AapneRoams
    Close-Sticky -Slutt $slutt -Aarsak 'loggen sluttet'
    if ($null -ne $script:FrakobletStart) {
        $script:Frakoblinger.Add(@{ Start = $script:FrakobletStart; Slutt = $slutt; Sekunder = ($slutt - [DateTime]$script:FrakobletStart).TotalSeconds; TilBssid = ''; FraBssid = $script:SisteBssid })
        $script:FrakobletStart = $null
    }

    $prover = $script:Prover
    $n = $prover.Count
    $varighetSek = ($slutt - $script:StartTid).TotalSeconds

    # --- Aggregering ---
    $tilkoblet = 0; $n24 = 0; $n5 = 0; $n6 = 0; $wifiData = 0
    $dbmListe = [System.Collections.Generic.List[object]]::new()
    $gwForsokt = 0; $gwOk = 0
    $gwRtt = [System.Collections.Generic.List[object]]::new()
    $inetForsokt = 0; $inetOk = 0
    $inetRtt = [System.Collections.Generic.List[object]]::new()
    $bssider = [System.Collections.Specialized.OrderedDictionary]::new()
    $avbrudd = [System.Collections.Generic.List[object]]::new()
    $avbruddStart = $null; $avbruddAntall = 0
    foreach ($s in $prover) {
        if ($s['WlanTilgjengelig']) { $wifiData++ }
        if ($s['Tilkoblet']) {
            $tilkoblet++
            $band = [string]$s['Band']
            if ($band -eq '2.4 GHz') { $n24++ } elseif ($band -eq '5 GHz') { $n5++ } elseif ($band -eq '6 GHz') { $n6++ }
            if ($null -ne $s['Dbm']) { $dbmListe.Add([int]$s['Dbm']) }
            $b = [string]$s['Bssid']
            if (-not $b) { $b = 'ukjent' }
            if (-not $bssider.Contains($b)) {
                $bssider.Add($b, @{ Bssid = $b; Antall = 0; Kanaler = ([System.Collections.Generic.List[string]]::new()); Band = $band; Radiotype = [string]$s['Radiotype']; Ssid = [string]$s['Ssid']; SumDbm = 0.0; AntDbm = 0; MinDbm = $null; MaksDbm = $null; Forste = [DateTime]$s['Tid']; Siste = [DateTime]$s['Tid'] })
            }
            $e = $bssider[$b]
            $e['Antall'] = [int]$e['Antall'] + 1
            $kan = Format-Kanal $s['Kanal']
            if (-not $e['Kanaler'].Contains($kan)) { $e['Kanaler'].Add($kan) }
            if ($null -ne $s['Dbm']) {
                $e['SumDbm'] = [double]$e['SumDbm'] + [int]$s['Dbm']; $e['AntDbm'] = [int]$e['AntDbm'] + 1
                if ($null -eq $e['MinDbm'] -or [int]$s['Dbm'] -lt [int]$e['MinDbm']) { $e['MinDbm'] = [int]$s['Dbm'] }
                if ($null -eq $e['MaksDbm'] -or [int]$s['Dbm'] -gt [int]$e['MaksDbm']) { $e['MaksDbm'] = [int]$s['Dbm'] }
            }
            $e['Siste'] = [DateTime]$s['Tid']
        }
        if ($s['GwForsokt']) {
            $gwForsokt++
            if ($s['GwOk']) {
                $gwOk++; $gwRtt.Add([int]$s['GwMs'])
                if ($null -ne $avbruddStart) {
                    if ($avbruddAntall -ge 2) { $avbrudd.Add(@{ Start = $avbruddStart; Antall = $avbruddAntall; Slutt = [DateTime]$s['Tid'] }) }
                    $avbruddStart = $null; $avbruddAntall = 0
                }
            } else {
                if ($null -eq $avbruddStart) { $avbruddStart = [DateTime]$s['Tid']; $avbruddAntall = 0 }
                $avbruddAntall++
            }
        }
        if ($s['InetForsokt']) {
            $inetForsokt++
            if ($s['InetOk']) { $inetOk++; $inetRtt.Add([int]$s['InetMs']) }
        }
    }
    if ($null -ne $avbruddStart -and $avbruddAntall -ge 2) { $avbrudd.Add(@{ Start = $avbruddStart; Antall = $avbruddAntall; Slutt = $slutt }) }

    $gapListe = [System.Collections.Generic.List[object]]::new()
    $roamAntall = 0; $tilkoblAntall = 0; $gapUkjent = 0
    foreach ($ev in $script:Roams) {
        if ($ev['Type'] -eq 'ROAM') { $roamAntall++ } else { $tilkoblAntall++ }
        if ($null -ne $ev['GapMs']) { $gapListe.Add([double]$ev['GapMs']) } else { $gapUkjent++ }
    }
    $gapMedian = Get-Median $gapListe
    $gapMaks = Get-Maks $gapListe
    $tapPst = $null
    if ($gwForsokt -gt 0) { $tapPst = 100.0 * ($gwForsokt - $gwOk) / $gwForsokt }
    $p50 = Get-Median $gwRtt
    $p95 = Get-Persentil $gwRtt 95
    $rttMaks = Get-Maks $gwRtt
    $rttSnitt = Get-Snitt $gwRtt
    $inetTap = $null
    if ($inetForsokt -gt 0) { $inetTap = 100.0 * ($inetForsokt - $inetOk) / $inetForsokt }
    $inetP50 = Get-Median $inetRtt
    $inetP95 = Get-Persentil $inetRtt 95
    $dbmMedian = Get-Median $dbmListe
    $dbmMin = Get-Min $dbmListe
    $andel24 = $null
    if ($tilkoblet -gt 0) { $andel24 = 100.0 * $n24 / $tilkoblet }

    # --- Statuslinjer ---
    Write-Linje -Tekst ''
    Write-Linje -Tekst ('nettsjekk roaming-logg {0} — oppsummering ({1})' -f $script:Versjon, $script:AvsluttetAv) -Farge 'White'

    Write-Overskrift 0
    $osTekst = 'ukjent'
    try { $osTekst = [System.Environment]::OSVersion.VersionString } catch { }
    $psTekst = 'ukjent'
    try { $psTekst = $PSVersionTable['PSVersion'].ToString() } catch { }
    $null = Write-Status -Status 'INFO' -Nr 0 -Sjekk 'Vert og miljø' -Verdi ('{0}, {1}, PowerShell {2}' -f [Environment]::MachineName, $osTekst, $psTekst)
    $null = Write-Status -Status 'INFO' -Nr 0 -Sjekk 'Loggperiode' -Verdi ('{0} → {1}, {2} s, {3} prøver, intervall {4} s' -f (Format-TidFull $script:StartTid), (Format-TidFull $slutt), (Format-Tall $varighetSek 0), $n, $Intervall)
    if ($script:GatewayInfo['Ip']) {
        $gwVerdi = '{0} via {1}' -f $script:GatewayInfo['Ip'], $script:GatewayInfo['Kilde']
        if ($script:GatewayInfo['Grensesnitt']) { $gwVerdi += (', grensesnitt {0}' -f $script:GatewayInfo['Grensesnitt']) }
        $gwStatus = 'INFO'
        if ([int]$script:GatewayInfo['Antall'] -gt 1) { $gwStatus = 'WARN'; $gwVerdi += (' — {0} default-ruter funnet' -f $script:GatewayInfo['Antall']) }
        $null = Write-Status -Status $gwStatus -Nr 0 -Sjekk 'Gateway' -Verdi $gwVerdi -Terskel 'én default-rute'
    } else {
        $null = Write-Status -Status 'SKIP' -Nr 0 -Sjekk 'Gateway' -Verdi 'ingen standard gateway funnet — gateway-ping ikke målt (bruk -Gateway <IP>)'
    }
    if ($script:WlanNavn -and $script:WlanNavn -ne 'ukjent') {
        $null = Write-Status -Status 'INFO' -Nr 0 -Sjekk 'Wi-Fi-grensesnitt' -Verdi ('{0} ({1})' -f $script:WlanNavn, $script:WlanBeskrivelse)
    } elseif ($script:PaaWindows) {
        $null = Write-Status -Status 'WARN' -Nr 0 -Sjekk 'Wi-Fi-grensesnitt' -Verdi ('ingen Wi-Fi-data fra netsh: {0}' -f $script:WlanFeil)
    } else {
        $null = Write-Status -Status 'SKIP' -Nr 0 -Sjekk 'Wi-Fi-grensesnitt' -Verdi 'netsh wlan finnes ikke (ikke Windows) — Wi-Fi-felt logget som ukjent'
    }
    if ($script:AdapterInfo['Tilgjengelig']) {
        $r = $script:AdapterInfo['Roaming']; if (-not $r) { $r = 'ikke eksponert av driveren' }
        $b = $script:AdapterInfo['Band']; if (-not $b) { $b = 'ikke eksponert av driveren' }
        $null = Write-Status -Status 'INFO' -Nr 0 -Sjekk 'Adapter: Roaming Aggressiveness' -Verdi $r
        $null = Write-Status -Status 'INFO' -Nr 0 -Sjekk 'Adapter: Preferred Band' -Verdi $b
    } else {
        $null = Write-Status -Status 'SKIP' -Nr 0 -Sjekk 'Adapter: Roaming Aggressiveness / Preferred Band' -Verdi $script:AdapterInfo['Feil']
    }

    Write-Overskrift 5
    if ($gwForsokt -gt 0) {
        $tapStatus = 'PASS'
        if ($tapPst -ge $script:T_TapWarn) { $tapStatus = 'FAIL' } elseif ($tapPst -ge $script:T_TapPass) { $tapStatus = 'WARN' }
        $null = Write-Status -Status $tapStatus -Nr 5 -Sjekk ('Pakketap mot gateway {0}' -f $script:GatewayInfo['Ip']) -Verdi ('{0} % ({1} av {2} ping tapt)' -f (Format-Tall $tapPst 1), ($gwForsokt - $gwOk), $gwForsokt) -Terskel ('PASS <{0} %, WARN <{1} %' -f (Format-Tall $script:T_TapPass 0), (Format-Tall $script:T_TapWarn 0))
        if ($null -ne $p50) {
            $null = Write-Status -Status 'INFO' -Nr 5 -Sjekk 'Gateway RTT' -Verdi ('p50 {0} ms, p95 {1} ms, maks {2} ms, snitt {3} ms ({4} svar)' -f (Format-Tall $p50 0), (Format-Tall $p95 0), (Format-Tall $rttMaks 0), (Format-Tall $rttSnitt 1), $gwOk)
        } else {
            $null = Write-Status -Status 'FAIL' -Nr 5 -Sjekk 'Gateway RTT' -Verdi 'ingen svar fra gateway i hele loggperioden'
        }
        if ($avbrudd.Count -eq 0) {
            $null = Write-Status -Status 'PASS' -Nr 5 -Sjekk 'Avbrudd mot gateway (≥2 tapte ping på rad)' -Verdi 'ingen' -Terskel '0 avbrudd'
        } else {
            $lengst = 0
            foreach ($a in $avbrudd) { if ([int]$a['Antall'] -gt $lengst) { $lengst = [int]$a['Antall'] } }
            $null = Write-Status -Status 'WARN' -Nr 5 -Sjekk 'Avbrudd mot gateway (≥2 tapte ping på rad)' -Verdi ('{0} avbrudd, lengste ≈ {1} s' -f $avbrudd.Count, ($lengst * $Intervall)) -Terskel '0 avbrudd'
        }
    } else {
        $null = Write-Status -Status 'SKIP' -Nr 5 -Sjekk 'Pakketap og RTT mot gateway' -Verdi 'ikke målt (ingen gateway)'
    }
    if ($inetForsokt -gt 0) {
        $inetVerdi = '{0} % tap ({1} av {2})' -f (Format-Tall $inetTap 1), ($inetForsokt - $inetOk), $inetForsokt
        if ($null -ne $inetP50) { $inetVerdi += (', p50 {0} ms, p95 {1} ms' -f (Format-Tall $inetP50 0), (Format-Tall $inetP95 0)) }
        $null = Write-Status -Status 'INFO' -Nr 5 -Sjekk 'Internett 1.1.1.1 (hver 5. prøve)' -Verdi $inetVerdi
    } else {
        $null = Write-Status -Status 'SKIP' -Nr 5 -Sjekk 'Internett 1.1.1.1 (hver 5. prøve)' -Verdi 'ingen prøver'
    }

    Write-Overskrift 11
    $null = Write-Status -Status 'INFO' -Nr 11 -Sjekk 'Antall roaming (BSSID-bytte)' -Verdi ('{0} roam, {1} gjentilkobling(er) etter frakobling' -f $roamAntall, $tilkoblAntall)
    if ($script:Roams.Count -eq 0) {
        $null = Write-Status -Status 'INFO' -Nr 11 -Sjekk 'Roaming-gap' -Verdi 'ingen roaming observert i loggperioden' -Terskel ('PASS ≤{0} ms, WARN ≤{1} ms' -f $script:T_GapPass, $script:T_GapWarn)
    } elseif ($gapListe.Count -eq 0) {
        $null = Write-Status -Status 'SKIP' -Nr 11 -Sjekk 'Roaming-gap' -Verdi ('{0} hendelse(r), men gap kunne ikke måles (ingen gateway-ping)' -f $script:Roams.Count)
    } else {
        $null = Write-Status -Status (Get-GapStatus $gapMedian) -Nr 11 -Sjekk 'Roaming-gap median' -Verdi ('{0} ms (oppløsning {1} ms = intervall)' -f (Format-Tall $gapMedian 0), ($Intervall * 1000)) -Terskel ('PASS ≤{0} ms, WARN ≤{1} ms' -f $script:T_GapPass, $script:T_GapWarn)
        $null = Write-Status -Status (Get-GapStatus $gapMaks) -Nr 11 -Sjekk 'Roaming-gap maks' -Verdi ('{0} ms' -f (Format-Tall $gapMaks 0)) -Terskel ('PASS ≤{0} ms, WARN ≤{1} ms' -f $script:T_GapPass, $script:T_GapWarn)
        if ($gapUkjent -gt 0) { $null = Write-Status -Status 'INFO' -Nr 11 -Sjekk 'Roaming-gap ukjent' -Verdi ('{0} hendelse(r) uten gateway-ping' -f $gapUkjent) }
    }
    if ($tilkoblet -gt 0) {
        $bandStatus = 'PASS'
        if ($n24 -gt 0) { $bandStatus = 'WARN' }
        $null = Write-Status -Status $bandStatus -Nr 11 -Sjekk 'Andel prøver på 2,4 GHz' -Verdi ('{0} % ({1} av {2}; 5 GHz: {3}, 6 GHz: {4})' -f (Format-Tall $andel24 1), $n24, $tilkoblet, $n5, $n6) -Terskel '0 % (Adm-nett bør bruke 5/6 GHz)'
        if ($null -ne $dbmMedian) {
            $rssiStatus = 'PASS'
            if ($dbmMedian -lt $script:T_RssiWarn) { $rssiStatus = 'FAIL' } elseif ($dbmMedian -lt $script:T_RssiPass) { $rssiStatus = 'WARN' }
            $null = Write-Status -Status $rssiStatus -Nr 11 -Sjekk 'Signal (omtrentlig dBm, median)' -Verdi ('{0} dBm median, {1} dBm min ({2} prøver; dBm ≈ prosent/2 − 100)' -f (Format-Tall $dbmMedian 0), (Format-Tall $dbmMin 0), $dbmListe.Count) -Terskel ('PASS ≥{0} dBm, WARN ≥{1} dBm' -f $script:T_RssiPass, $script:T_RssiWarn)
        }
    } else {
        $null = Write-Status -Status 'SKIP' -Nr 11 -Sjekk 'Andel prøver på 2,4 GHz' -Verdi 'ingen tilkoblede Wi-Fi-prøver'
    }
    if ($script:Sticky.Count -eq 0) {
        if ($dbmListe.Count -gt 0) {
            $null = Write-Status -Status 'PASS' -Nr 11 -Sjekk 'Sticky client' -Verdi 'ingen episoder' -Terskel ('< {0} dBm i > {1} s uten roam' -f $script:T_StickyDbm, $script:T_StickySek)
        } else {
            $null = Write-Status -Status 'SKIP' -Nr 11 -Sjekk 'Sticky client' -Verdi 'ingen signaldata'
        }
    } else {
        $sum = 0.0
        foreach ($ep in $script:Sticky) { $sum += [double]$ep['Sekunder'] }
        $null = Write-Status -Status 'WARN' -Nr 11 -Sjekk 'sticky client – sjekk min-RSSI / BSS transition (802.11v) på AP-ene' -Verdi ('{0} episode(r), totalt {1} s under {2} dBm' -f $script:Sticky.Count, (Format-Tall $sum 0), $script:T_StickyDbm) -Terskel ('< {0} dBm i > {1} s uten roam' -f $script:T_StickyDbm, $script:T_StickySek)
    }
    if ($script:Frakoblinger.Count -eq 0) {
        if ($wifiData -gt 0) { $null = Write-Status -Status 'PASS' -Nr 11 -Sjekk 'Frakoblinger fra Wi-Fi' -Verdi 'ingen' -Terskel '0' }
    } else {
        $sum = 0.0
        foreach ($f in $script:Frakoblinger) { if ($null -ne $f['Sekunder']) { $sum += [double]$f['Sekunder'] } }
        $null = Write-Status -Status 'WARN' -Nr 11 -Sjekk 'Frakoblinger fra Wi-Fi' -Verdi ('{0} frakobling(er), totalt ≈ {1} s uten forbindelse' -f $script:Frakoblinger.Count, (Format-Tall $sum 0)) -Terskel '0'
    }
    if ($bssider.Count -gt 0) {
        $bTekst = [System.Collections.Generic.List[string]]::new()
        foreach ($k in $bssider.Keys) {
            $e = $bssider[$k]
            $bTekst.Add(('{0} kan {1} {2} {3} s' -f $e['Bssid'], ($e['Kanaler'].ToArray() -join '/'), (Format-Band $e['Band']), ([int]$e['Antall'] * $Intervall)))
        }
        $null = Write-Status -Status 'INFO' -Nr 11 -Sjekk 'Unike BSSID-er (AP-radioer)' -Verdi ('{0}: {1}' -f $bssider.Count, ($bTekst.ToArray() -join '; '))
    }

    Write-Overskrift 13
    $tell = @{ PASS = 0; WARN = 0; FAIL = 0; INFO = 0; SKIP = 0 }
    foreach ($r in $script:Resultater) { $st = [string]$r['Status']; if ($tell.Contains($st)) { $tell[$st] = [int]$tell[$st] + 1 } }
    $totStatus = 'PASS'
    if ([int]$tell['FAIL'] -gt 0) { $totStatus = 'FAIL' } elseif ([int]$tell['WARN'] -gt 0) { $totStatus = 'WARN' }
    $null = Write-Status -Status $totStatus -Nr 13 -Sjekk 'Totalt' -Verdi ('PASS {0}, WARN {1}, FAIL {2}, INFO {3}, SKIP {4}' -f $tell['PASS'], $tell['WARN'], $tell['FAIL'], $tell['INFO'], $tell['SKIP'])

    # --- Markdown ---
    $sb = [System.Text.StringBuilder]::new()
    $nl = $script:NyLinje
    [void]$sb.Append('# nettsjekk roaming-logg — ' + [Environment]::MachineName + ' — ' + (Format-TidFull $script:StartTid) + $nl + $nl)
    [void]$sb.Append('Versjon ' + $script:Versjon + ' — 2026-09-09. Endrer ingenting — kun lesing og målinger.' + $nl + $nl)
    [void]$sb.Append('| Felt | Verdi |' + $nl + '|---|---|' + $nl)
    [void]$sb.Append('| Vert | ' + [Environment]::MachineName + ' |' + $nl)
    [void]$sb.Append('| OS | ' + $osTekst + ' |' + $nl)
    [void]$sb.Append('| PowerShell | ' + $psTekst + ' |' + $nl)
    [void]$sb.Append('| Start | ' + (Format-TidFull $script:StartTid) + ' |' + $nl)
    [void]$sb.Append('| Slutt | ' + (Format-TidFull $slutt) + ' (' + $script:AvsluttetAv + ') |' + $nl)
    [void]$sb.Append('| Varighet | ' + (Format-Tall $varighetSek 0) + ' s, ' + $n + ' prøver, intervall ' + $Intervall + ' s |' + $nl)
    $gwCelle = 'ingen (ikke målt)'
    if ($script:GatewayInfo['Ip']) { $gwCelle = $script:GatewayInfo['Ip'] + ' (' + $script:GatewayInfo['Kilde'] + ')' }
    [void]$sb.Append('| Gateway | ' + $gwCelle + ' |' + $nl)
    $wlanCelle = 'ukjent'
    if ($script:WlanNavn -and $script:WlanNavn -ne 'ukjent') { $wlanCelle = $script:WlanNavn + ' (' + $script:WlanBeskrivelse + ')' } elseif ($script:WlanFeil) { $wlanCelle = $script:WlanFeil }
    [void]$sb.Append('| Wi-Fi-grensesnitt | ' + $wlanCelle + ' |' + $nl)
    [void]$sb.Append('| Parametre | Intervall=' + $Intervall + ', Varighet=' + $Varighet + ', Gateway=' + $Gateway + ', Grensesnitt=' + $Grensesnitt + ', IngenFarger=' + [bool]$IngenFarger + ' |' + $nl)
    [void]$sb.Append('| CSV | ' + $script:CsvSti + ' |' + $nl + $nl)

    [void]$sb.Append('## Statuslinjer' + $nl + $nl + '```' + $nl)
    $sisteNr = -1
    foreach ($r in $script:Resultater) {
        if ([int]$r['Nr'] -ne $sisteNr) { $sisteNr = [int]$r['Nr']; [void]$sb.Append('=== ' + $script:SeksjonNavn[$sisteNr] + ' ===' + $nl) }
        [void]$sb.Append([string]$r['Linje'] + $nl)
    }
    [void]$sb.Append('```' + $nl + $nl)

    [void]$sb.Append('## Roaming-hendelser' + $nl + $nl)
    if ($script:Roams.Count -eq 0) {
        [void]$sb.Append('Ingen roaming eller gjentilkobling observert.' + $nl + $nl)
    } else {
        [void]$sb.Append('| Tid | Type | Fra BSSID (kanal, bånd) | Til BSSID (kanal, bånd) | Signal før → etter | Tapte gw-ping før+etter | Gap (ms) | Første OK-ping etter (ms) | Status |' + $nl)
        [void]$sb.Append('|---|---|---|---|---|---|---|---|---|' + $nl)
        foreach ($ev in $script:Roams) {
            $gap = 'ukjent'; if ($null -ne $ev['GapMs']) { $gap = ([int]$ev['GapMs']).ToString($script:Inv) }
            $ok = 'ingen'; if ($null -ne $ev['TidTilOkMs']) { $ok = ([int]$ev['TidTilOkMs']).ToString($script:Inv) }
            [void]$sb.Append(('| {0} | {1} | {2} (kan {3}, {4}) | {5} (kan {6}, {7}) | {8} → {9} | {10}+{11} | {12} | {13} | {14} |' -f (Format-Tid ([DateTime]$ev['Tid'])), $ev['Type'], $ev['FraBssid'], (Format-Kanal $ev['FraKanal']), (Format-Band $ev['FraBand']), $ev['TilBssid'], (Format-Kanal $ev['TilKanal']), (Format-Band $ev['TilBand']), (Format-Dbm $ev['DbmFor']), (Format-Dbm $ev['DbmEtter']), $ev['TapteFor'], $ev['TapteEtter'], $gap, $ok, $ev['Status']) + $nl)
        }
        [void]$sb.Append($nl + 'Gap = (tapte gateway-ping før + etter hendelsen) × intervall. Oppløsningen er derfor ' + ($Intervall * 1000) + ' ms; «første OK-ping etter» er målt klokketid fra hendelsen til første svar.' + $nl + $nl)
    }

    [void]$sb.Append('## BSSID-er observert (AP-radioer)' + $nl + $nl)
    if ($bssider.Count -eq 0) {
        [void]$sb.Append('Ingen tilkoblede Wi-Fi-prøver (Wi-Fi-data ukjent eller frakoblet hele perioden).' + $nl + $nl)
    } else {
        [void]$sb.Append('| BSSID | SSID | Kanal | Bånd | Radiotype | Prøver | Tid (s) | Andel | Snitt dBm | Min dBm | Maks dBm | Første sett | Sist sett |' + $nl)
        [void]$sb.Append('|---|---|---|---|---|---|---|---|---|---|---|---|---|' + $nl)
        foreach ($k in $bssider.Keys) {
            $e = $bssider[$k]
            $snitt = 'ukjent'; if ([int]$e['AntDbm'] -gt 0) { $snitt = Format-Tall ([double]$e['SumDbm'] / [int]$e['AntDbm']) 1 }
            $minD = 'ukjent'; if ($null -ne $e['MinDbm']) { $minD = [string]$e['MinDbm'] }
            $maksD = 'ukjent'; if ($null -ne $e['MaksDbm']) { $maksD = [string]$e['MaksDbm'] }
            $andel = Format-Tall (100.0 * [int]$e['Antall'] / $tilkoblet) 1
            [void]$sb.Append(('| {0} | {1} | {2} | {3} | {4} | {5} | {6} | {7} % | {8} | {9} | {10} | {11} | {12} |' -f $e['Bssid'], $e['Ssid'], ($e['Kanaler'].ToArray() -join '/'), (Format-Band $e['Band']), $e['Radiotype'], $e['Antall'], ([int]$e['Antall'] * $Intervall), $andel, $snitt, $minD, $maksD, (Format-Tid ([DateTime]$e['Forste'])), (Format-Tid ([DateTime]$e['Siste']))) + $nl)
        }
        [void]$sb.Append($nl)
    }

    [void]$sb.Append('## Sticky client-episoder' + $nl + $nl)
    if ($script:Sticky.Count -eq 0) {
        [void]$sb.Append('Ingen episoder (omtrentlig signal < ' + $script:T_StickyDbm + ' dBm i mer enn ' + $script:T_StickySek + ' s uten roaming).' + $nl + $nl)
    } else {
        [void]$sb.Append('| Start | Slutt | Varighet (s) | BSSID | Kanal | Min dBm | Avsluttet av |' + $nl + '|---|---|---|---|---|---|---|' + $nl)
        foreach ($ep in $script:Sticky) {
            [void]$sb.Append(('| {0} | {1} | {2} | {3} | {4} | {5} | {6} |' -f (Format-Tid ([DateTime]$ep['Start'])), (Format-Tid ([DateTime]$ep['Slutt'])), (Format-Tall ([double]$ep['Sekunder']) 0), $ep['Bssid'], (Format-Kanal $ep['Kanal']), $ep['MinDbm'], $ep['Aarsak']) + $nl)
        }
        [void]$sb.Append($nl + 'Sticky client: klienten henger på en AP med svakt signal uten å roame. Sjekk min-RSSI/«client roaming threshold» og BSS transition (802.11v) i radioprofilen i XIQ, og Roaming Aggressiveness på klientens driver.' + $nl + $nl)
    }

    [void]$sb.Append('## Frakoblinger og avbrudd' + $nl + $nl)
    if ($script:Frakoblinger.Count -eq 0 -and $avbrudd.Count -eq 0) {
        [void]$sb.Append('Ingen frakoblinger fra Wi-Fi og ingen avbrudd (≥2 tapte gateway-ping på rad).' + $nl + $nl)
    } else {
        if ($script:Frakoblinger.Count -gt 0) {
            [void]$sb.Append('| Frakoblet | Tilkoblet igjen | Varighet (s) | Fra BSSID | Til BSSID |' + $nl + '|---|---|---|---|---|' + $nl)
            foreach ($f in $script:Frakoblinger) {
                $st = 'ukjent'; if ($null -ne $f['Start']) { $st = Format-Tid ([DateTime]$f['Start']) }
                $va = 'ukjent'; if ($null -ne $f['Sekunder']) { $va = Format-Tall ([double]$f['Sekunder']) 0 }
                $til = [string]$f['TilBssid']; if (-not $til) { $til = 'ikke tilkoblet igjen' }
                [void]$sb.Append(('| {0} | {1} | {2} | {3} | {4} |' -f $st, (Format-Tid ([DateTime]$f['Slutt'])), $va, $f['FraBssid'], $til) + $nl)
            }
            [void]$sb.Append($nl)
        }
        if ($avbrudd.Count -gt 0) {
            [void]$sb.Append('| Avbrudd start | Tapte ping på rad | Varighet ≈ (s) | Første svar |' + $nl + '|---|---|---|---|' + $nl)
            foreach ($a in $avbrudd) {
                [void]$sb.Append(('| {0} | {1} | {2} | {3} |' -f (Format-Tid ([DateTime]$a['Start'])), $a['Antall'], ([int]$a['Antall'] * $Intervall), (Format-Tid ([DateTime]$a['Slutt']))) + $nl)
            }
            [void]$sb.Append($nl)
        }
    }

    [void]$sb.Append('## Hendelseslogg' + $nl + $nl)
    if ($script:Hendelser.Count -eq 0) {
        [void]$sb.Append('Ingen hendelser.' + $nl + $nl)
    } else {
        [void]$sb.Append('```' + $nl)
        foreach ($h in $script:Hendelser) { [void]$sb.Append($h + $nl) }
        [void]$sb.Append('```' + $nl + $nl)
    }

    [void]$sb.Append('## Terskler' + $nl + $nl)
    [void]$sb.Append('- Roaming-gap (tapte gateway-ping før+etter × intervall): PASS ≤ ' + $script:T_GapPass + ' ms, WARN ≤ ' + $script:T_GapWarn + ' ms, FAIL > ' + $script:T_GapWarn + ' ms.' + $nl)
    [void]$sb.Append('- Pakketap mot gateway: PASS < ' + (Format-Tall $script:T_TapPass 0) + ' %, WARN < ' + (Format-Tall $script:T_TapWarn 0) + ' %, FAIL ≥ ' + (Format-Tall $script:T_TapWarn 0) + ' %.' + $nl)
    [void]$sb.Append('- Sticky client: omtrentlig signal < ' + $script:T_StickyDbm + ' dBm i > ' + $script:T_StickySek + ' s uten roaming → WARN.' + $nl)
    [void]$sb.Append('- Signal (omtrentlig dBm = prosent/2 − 100): PASS ≥ ' + $script:T_RssiPass + ' dBm, WARN ≥ ' + $script:T_RssiWarn + ' dBm, FAIL < ' + $script:T_RssiWarn + ' dBm.' + $nl)
    [void]$sb.Append('- Tilkoblet på 2,4 GHz: WARN (Adm-nett bør bruke 5/6 GHz). Flere default-ruter: WARN.' + $nl)
    [void]$sb.Append('- Roaming-deteksjon: BSSID-bytte; reserve når BSSID mangler: kanalbytte, ellers signalhopp ≥ ' + $script:T_RssiHopp + ' dB.' + $nl)
    [void]$sb.Append('- Gateway RTT p50/p95 og 1.1.1.1 er INFO (referanse fra sjekk-klient: gateway-snitt PASS ≤ 10 ms, WARN ≤ 30 ms).' + $nl + $nl)

    [void]$sb.Append('## Rå utdata' + $nl + $nl)
    foreach ($k in $script:RaaUtdata.Keys) {
        [void]$sb.Append('### ' + $k + $nl + $nl + '```' + $nl + [string]$script:RaaUtdata[$k] + $nl + '```' + $nl + $nl)
    }
    if ($script:AdapterInfo['Raa']) {
        [void]$sb.Append('### Get-NetAdapterAdvancedProperty (' + $script:AdapterInfo['Alias'] + ')' + $nl + $nl + '```' + $nl + $script:AdapterInfo['Raa'] + $nl + '```' + $nl + $nl)
    }
    # Prøver rundt hver hendelse (±5) og de siste 20 prøvene — resten ligger i CSV-filen.
    $inkluder = [System.Collections.Generic.HashSet[int]]::new()
    foreach ($ev in $script:Roams) {
        $c = [int]$ev['Nr']
        for ($i = $c - 5; $i -le $c + 5; $i++) { if ($i -ge 1 -and $i -le $n) { [void]$inkluder.Add($i) } }
    }
    for ($i = [math]::Max(1, $n - 19); $i -le $n; $i++) { [void]$inkluder.Add($i) }
    [void]$sb.Append('### Prøver rundt hendelser (±5) og de siste 20 prøvene (CSV-format)' + $nl + $nl + '```' + $nl + (Get-CsvHode) + $nl)
    $forrigeNr = 0
    foreach ($s in $prover) {
        $nr = [int]$s['Nr']
        if (-not $inkluder.Contains($nr)) { continue }
        if ($forrigeNr -gt 0 -and $nr -ne $forrigeNr + 1) { [void]$sb.Append('...' + $nl) }
        [void]$sb.Append((ConvertTo-CsvLinje $s) + $nl)
        $forrigeNr = $nr
    }
    [void]$sb.Append('```' + $nl)

    try {
        [System.IO.File]::WriteAllText($script:MdSti, $sb.ToString(), $script:Utf8)
        Write-Linje -Tekst ''
        Write-Linje -Tekst ('Oppsummering skrevet: {0}' -f $script:MdSti) -Farge 'White'
        Write-Linje -Tekst ('CSV skrevet:          {0}' -f $script:CsvSti) -Farge 'White'
        Write-Linje -Tekst 'Lim inn innholdet i .md-filen i chatten for analyse.'
    } catch {
        Write-Linje -Tekst ('[FAIL] 13 Oppsummering: kunne ikke skrive {0} — {1}' -f $script:MdSti, (Get-Feilmelding $_)) -Farge 'Red'
    }
}

# ------------------------------------------------------------------------------------
# Oppstart
# ------------------------------------------------------------------------------------
if (-not $Rapportmappe) {
    try { $Rapportmappe = (Get-Location).Path } catch { $Rapportmappe = [System.IO.Directory]::GetCurrentDirectory() }
} elseif (-not [System.IO.Path]::IsPathRooted($Rapportmappe)) {
    try { $Rapportmappe = [System.IO.Path]::Combine((Get-Location).Path, $Rapportmappe) } catch { }
}
if (-not [System.IO.Directory]::Exists($Rapportmappe)) {
    try { [void][System.IO.Directory]::CreateDirectory($Rapportmappe) } catch {
        Write-Linje -Tekst ('[WARN] 0 System og verktøy: Rapportmappe — kunne ikke opprette {0} ({1}); bruker gjeldende mappe' -f $Rapportmappe, (Get-Feilmelding $_)) -Farge 'Yellow'
        try { $Rapportmappe = (Get-Location).Path } catch { $Rapportmappe = [System.IO.Directory]::GetCurrentDirectory() }
    }
}
$vertRen = ([Environment]::MachineName -replace '[^A-Za-z0-9_-]', '_')
$stempel = $script:StartTid.ToString('yyyyMMdd-HHmmss', $script:Inv)
$script:CsvSti = [System.IO.Path]::Combine($Rapportmappe, ('roaming-logg-{0}-{1}.csv' -f $vertRen, $stempel))
$script:MdSti = [System.IO.Path]::Combine($Rapportmappe, ('roaming-logg-{0}-{1}.md' -f $vertRen, $stempel))

if ($script:PaaWindows) {
    $script:NetshSti = Get-ExeSti @('netsh.exe', 'netsh')
    $script:PingSti = Get-ExeSti @('ping.exe', 'ping')
}

Write-Linje -Tekst ('nettsjekk roaming-logg {0} — {1} — start {2}' -f $script:Versjon, [Environment]::MachineName, (Format-TidFull $script:StartTid)) -Farge 'White'
Write-Linje -Tekst 'Endrer ingenting — kun lesing og målinger. Ctrl-C avslutter og skriver oppsummeringen.'
$varTekst = 'til Ctrl-C'
if ($Varighet -gt 0) { $varTekst = ('{0} s' -f $Varighet) }
Write-Linje -Tekst ('Intervall {0} s, varighet {1}. Gateway-ping hver prøve, 1.1.1.1 hver 5. prøve.' -f $Intervall, $varTekst)

Write-Overskrift 0
$script:GatewayInfo = Get-StandardGateway
if ($script:GatewayInfo['Ip']) {
    $null = Write-Status -Status 'INFO' -Nr 0 -Sjekk 'Gateway' -Verdi ('{0} ({1})' -f $script:GatewayInfo['Ip'], $script:GatewayInfo['Kilde']) -IkkeLagre
} else {
    $null = Write-Status -Status 'SKIP' -Nr 0 -Sjekk 'Gateway' -Verdi 'ingen standard gateway funnet — gateway-ping måles ikke (oppgi -Gateway <IP>)' -IkkeLagre
}
if ($script:PaaWindows) {
    if (-not $script:NetshSti) { $null = Write-Status -Status 'SKIP' -Nr 0 -Sjekk 'netsh' -Verdi 'netsh.exe ikke funnet (innebygd i Windows, C:\Windows\System32) — Wi-Fi-felt blir ukjent' -IkkeLagre }
    if (-not $script:PingSti) { $null = Write-Status -Status 'SKIP' -Nr 0 -Sjekk 'ping.exe' -Verdi 'ping.exe ikke funnet (innebygd i Windows, C:\Windows\System32) — bruker .NET Ping' -IkkeLagre }
} else {
    $null = Write-Status -Status 'SKIP' -Nr 0 -Sjekk 'Wi-Fi-data' -Verdi 'netsh wlan finnes bare på Windows — Wi-Fi-felt logges som ukjent, gateway-ping via .NET' -IkkeLagre
}

# Første Wi-Fi-prøve for å finne grensesnittets navn (til adapteregenskaper) og rå utdata til rapporten.
$forsteWlan = Get-WlanProve
if ($forsteWlan['Tilgjengelig']) {
    $script:WlanNavn = [string]$forsteWlan['Navn']; $script:WlanBeskrivelse = [string]$forsteWlan['Beskrivelse']
    $null = Write-Status -Status 'INFO' -Nr 0 -Sjekk 'Wi-Fi-grensesnitt' -Verdi ('{0} ({1}), tilstand: {2}' -f $script:WlanNavn, $script:WlanBeskrivelse, $forsteWlan['Tilstand']) -IkkeLagre
} else {
    $script:WlanFeil = [string]$forsteWlan['Feil']
    if ($script:PaaWindows) { $null = Write-Status -Status 'WARN' -Nr 0 -Sjekk 'Wi-Fi-grensesnitt' -Verdi $script:WlanFeil -IkkeLagre }
}
if ($forsteWlan['Raa']) { $script:RaaUtdata['netsh wlan show interfaces (ved start)'] = [string]$forsteWlan['Raa'] }

$alias = ''
if ($script:WlanNavn -and $script:WlanNavn -ne 'ukjent') { $alias = $script:WlanNavn } elseif ($Grensesnitt) { $alias = '*' + $Grensesnitt + '*' }
$script:AdapterInfo = Get-AdapterEgenskaper -Alias $alias
if ($script:AdapterInfo['Tilgjengelig']) {
    $r = $script:AdapterInfo['Roaming']; if (-not $r) { $r = 'ikke eksponert av driveren' }
    $b = $script:AdapterInfo['Band']; if (-not $b) { $b = 'ikke eksponert av driveren' }
    $null = Write-Status -Status 'INFO' -Nr 0 -Sjekk 'Adapter: Roaming Aggressiveness' -Verdi $r -IkkeLagre
    $null = Write-Status -Status 'INFO' -Nr 0 -Sjekk 'Adapter: Preferred Band' -Verdi $b -IkkeLagre
} else {
    $null = Write-Status -Status 'SKIP' -Nr 0 -Sjekk 'Adapter: Roaming Aggressiveness / Preferred Band' -Verdi $script:AdapterInfo['Feil'] -IkkeLagre
}

try {
    [System.IO.File]::WriteAllText($script:CsvSti, (Get-CsvHode) + $script:NyLinje, $script:Utf8Bom)
} catch {
    Write-Linje -Tekst ('[FAIL] 0 System og verktøy: CSV — kunne ikke skrive {0} ({1})' -f $script:CsvSti, (Get-Feilmelding $_)) -Farge 'Red'
}
Write-Linje -Tekst ('CSV: {0}' -f $script:CsvSti)

Write-Overskrift 11
Write-Linje -Tekst 'tid  ssid  bssid  kanal  bånd  radiotype  signal (~dBm)  rx/tx  gateway-ping  [1.1.1.1]' -Farge 'DarkGray'

# ------------------------------------------------------------------------------------
# Hovedløkke — try/finally slik at oppsummeringen alltid skrives (også ved Ctrl-C)
# ------------------------------------------------------------------------------------
$script:LoopFerdig = $false
$script:AvsluttetAv = 'Ctrl-C'
try {
    $klokke = [System.Diagnostics.Stopwatch]::StartNew()
    $nr = 0
    while ($true) {
        if ($Varighet -gt 0 -and $klokke.Elapsed.TotalSeconds -ge $Varighet) { break }
        $nr++
        $proveStart = $klokke.ElapsedMilliseconds
        try {
            Invoke-Prove -Nr $nr
        } catch {
            if ($_.Exception -is [System.Management.Automation.PipelineStoppedException]) { throw }
            Write-Linje -Tekst ('[WARN] 11 Roaming: prøve {0} feilet — {1}' -f $nr, (Get-Feilmelding $_)) -Farge 'Yellow'
        }
        if ($Varighet -gt 0 -and $klokke.Elapsed.TotalSeconds -ge $Varighet) { break }
        $brukt = $klokke.ElapsedMilliseconds - $proveStart
        $sov = [int]($Intervall * 1000 - $brukt)
        if ($sov -gt 0) { Start-Sleep -Milliseconds $sov }
    }
    $script:LoopFerdig = $true
    $script:AvsluttetAv = 'varighet nådd'
} finally {
    if (-not $script:LoopFerdig) { $script:KonsollModus = $true }
    try {
        Write-Oppsummering
    } catch {
        try { [Console]::Error.WriteLine('[FAIL] 13 Oppsummering: uventet feil — ' + (Get-Feilmelding $_)) } catch { }
    }
}
