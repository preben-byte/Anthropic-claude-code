# =====================================================================================
# sjekk-klient.ps1 — nettsjekk: ende-til-ende klientsjekk for Windows (PowerShell)
#
# Formål : Måler og dokumenterer hele kjeden fiber – brannmur – svitsj – AP – klient fra en
#          Windows-PC på Adm-nett (Marivold Camping): system, lenke/Wi-Fi, IP, DHCP, DNS,
#          gateway/brannmur, fiber/WAN, TCP, hastighet, bufferbloat, video, roaming og hygiene.
#          Skriver en rapport (.md + .json) som limes inn i chatten for analyse.
# Kjøring: powershell.exe -ExecutionPolicy Bypass -File .\sjekk-klient.ps1
#          powershell.exe -ExecutionPolicy Bypass -File .\sjekk-klient.ps1 -Hurtig -Rapportmappe C:\Temp
#          pwsh -File .\sjekk-klient.ps1 -ForventetNed 300 -ForventetOpp 300 -InterneNavn nas.local,xiq.local
# Krav   : Windows PowerShell 5.1 eller PowerShell 7.x på Windows. Ingen adminrettigheter nødvendig
#          (admin gir i tillegg wlanreport). Valgfritt: iperf3.exe i PATH eller ved siden av skriptet.
#          Kjører også under PowerShell 7 på Linux/macOS, men da blir Windows-spesifikke sjekker [SKIP].
# Versjon 1.0 — 2026-09-09
# Endrer ingenting — kun lesing og målinger.
# =====================================================================================

<#
.SYNOPSIS
    nettsjekk — full ende-til-ende klientsjekk (fiber – brannmur – svitsj – AP – klient) fra en Windows-PC.

.DESCRIPTION
    Skriptet kjører 14 seksjoner (0–13) med lesende sjekker og målinger: system og verktøy, lenke og Wi-Fi,
    IP/TCP/IP, DHCP, DNS, gateway og brannmur, fiber og WAN, TCP-ytelse, hastighet, bufferbloat og jitter
    under last, video og strømming, roaming, hygiene og oppsummering.

    Hver sjekk gir en statuslinje på formen
        [PASS] <seksjon>: <sjekk> — <verdi> (terskel <t>)
    med statusene PASS, WARN, FAIL, INFO og SKIP. Til slutt skrives to rapportfiler i rapportmappen:
        nettsjekk-rapport-<host>-<YYYYMMDD-HHMMSS>.md   (statuslinjer + rå kommandoutdata i kodeblokker)
        nettsjekk-rapport-<host>-<YYYYMMDD-HHMMSS>.json (strukturert resultat)
    Lim inn innholdet i .md-filen i chatten for analyse.

    Skriptet er READ-ONLY: det endrer aldri nettverksinnstillinger, fornyer/slipper ikke DHCP-lease,
    tømmer ikke DNS-cache, slår ikke av/på adaptere og krever aldri administratorrettigheter.
    Wi-Fi-passord/PSK leses aldri. Alle nettverksoperasjoner har tidsavbrudd.

.PARAMETER Rapportmappe
    Mappe der rapportfilene (.md og .json) skrives. Standard: gjeldende mappe.

.PARAMETER Hurtig
    Hurtigmodus: hopper over seksjon 8 (Hastighet), 9 (Bufferbloat) og 10 (Video). Mål: under 2 minutter.

.PARAMETER ForventetNed
    Forventet nedlastingshastighet i Mbit/s (standard 100). PASS ≥ 80 %, WARN ≥ 50 %, FAIL < 50 % av dette.

.PARAMETER ForventetOpp
    Forventet opplastingshastighet i Mbit/s (standard 50). Samme terskler som for nedlasting.

.PARAMETER IperfServer
    IP-adresse/vertsnavn til en iperf3-server på LAN (valgfritt). Krever iperf3.exe i PATH eller ved siden av skriptet.

.PARAMETER InterneNavn
    Liste med interne DNS-navn som skal kunne slås opp (f.eks. nas.local,xiq.local). Kommaseparert eller flere verdier.

.PARAMETER Gateway
    Overstyr standard gateway (IPv4). Standard: leses fra rutetabellen.

.PARAMETER Grensesnitt
    Navn (eller del av beskrivelsen) på nettverksgrensesnittet som skal brukes. Standard: grensesnittet med standardruten.

.PARAMETER IngenFarger
    Skriv statuslinjer uten farger (for logging/omdirigering).

.EXAMPLE
    .\sjekk-klient.ps1
    Full kjøring med standardverdier, rapport i gjeldende mappe.

.EXAMPLE
    .\sjekk-klient.ps1 -Hurtig -Rapportmappe C:\Temp -IngenFarger
    Hurtigmodus (uten hastighet/bufferbloat/video), rapport i C:\Temp, uten farger.

.EXAMPLE
    .\sjekk-klient.ps1 -ForventetNed 500 -ForventetOpp 500 -IperfServer 10.0.0.5 -InterneNavn nas.local,skriver.local
    Full kjøring med egne hastighetsforventninger, iperf3 mot LAN-server og oppslag av interne navn.

.NOTES
    Versjon 1.0 — 2026-09-09. Endrer ingenting — kun lesing og målinger.
    Kompatibel med Windows PowerShell 5.1 og PowerShell 7.x.
#>

[CmdletBinding()]
param(
    [Parameter()][string]$Rapportmappe = '',
    [Parameter()][switch]$Hurtig,
    [Parameter()][ValidateRange(1, 100000)][int]$ForventetNed = 100,
    [Parameter()][ValidateRange(1, 100000)][int]$ForventetOpp = 50,
    [Parameter()][string]$IperfServer = '',
    [Parameter()][string[]]$InterneNavn = @(),
    [Parameter()][string]$Gateway = '',
    [Parameter()][string]$Grensesnitt = '',
    [Parameter()][switch]$IngenFarger
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Continue'
$ProgressPreference = 'SilentlyContinue'   # fremdriftslinjen i Invoke-WebRequest gjør 5.1 svært treg

# ------------------------------------------------------------------------------------
# Globale variabler
# ------------------------------------------------------------------------------------
$script:Versjon = '1.0'
$script:PaaWindows = ($env:OS -eq 'Windows_NT')
$script:PaaLinux = (-not $script:PaaWindows) -and (Test-Path -LiteralPath '/proc/version')
$script:Farger = -not $IngenFarger
$script:StartTid = Get-Date
$script:Inv = [System.Globalization.CultureInfo]::InvariantCulture
$script:Resultater = New-Object System.Collections.Generic.List[object]
$script:RaaUtdata = @{}
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
$script:Verktoy = @{}
$script:Primaer = $null
$script:ErWifi = $false
$script:Wlan = $null
$script:NaboBssid = @()
$script:AvanserteEgenskaper = @()
$script:GatewayIp = ''
$script:AntallDefaultRuter = 0
$script:Resolvere = @()
$script:TcpTellereFoer = $null
$script:Hastighet8Kjort = $false
$script:ErAdmin = $false
$script:OffentligIp = ''
$script:CgnatHopp = ''
$script:OsTekst = ''
$script:Ipv4Adresser = @()
$script:Ipv6Adresser = @()
$script:DhcpServer = ''
$script:MaalDns = @('nrk.no', 'vg.no', 'cloudflare.com', 'extremecloudiq.com', 'redirector.aerohive.com')
$script:UrlNed = 'https://speed.cloudflare.com/__down?bytes=100000000'
$script:UrlNedReserve = 'https://speed.cloudflare.com/__down?bytes=25000000'
$script:UrlOpp = 'https://speed.cloudflare.com/__up'
$script:UrlHls = 'https://test-streams.mux.dev/x36xhzz/x36xhzz.m3u8'
$script:UrlHlsReserve = 'https://devstreaming-cdn.apple.com/videos/streaming/examples/img_bipbop_adv_example_hevc/master.m3u8'

if (-not $Rapportmappe) { $Rapportmappe = (Get-Location).Path }
$InterneNavn = @($InterneNavn | ForEach-Object { $_ -split ',' } | ForEach-Object { $_.Trim() } | Where-Object { $_ })

# TLS 1.2 for Windows PowerShell 5.1 (eldre .NET Framework starter med SSL3/TLS1.0)
$script:PsUtgave = 'Desktop'
if ($PSVersionTable.ContainsKey('PSEdition')) { $script:PsUtgave = [string]$PSVersionTable['PSEdition'] }
if ($script:PsUtgave -eq 'Desktop') {
    try { [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12 } catch { }
}
$script:HarHttpClient = $false
try { Add-Type -AssemblyName System.Net.Http -ErrorAction Stop; $script:HarHttpClient = $true } catch { }
if (-not $script:HarHttpClient) {
    try { $null = [System.Net.Http.HttpClient]; $script:HarHttpClient = $true } catch { }
}

# ------------------------------------------------------------------------------------
# Hjelpefunksjoner: format, statistikk, egenskaper
# ------------------------------------------------------------------------------------
function Format-Tall {
    param([double]$Verdi, [int]$Desimaler = 1)
    return $Verdi.ToString('F' + $Desimaler, $script:Inv)
}

function ConvertTo-Tall {
    # Tolker tall med både punktum og komma som desimaltegn (norsk/engelsk utdata).
    param([string]$Tekst)
    if ($null -eq $Tekst) { return $null }
    $t = $Tekst.Trim().Replace(',', '.')
    $d = 0.0
    if ([double]::TryParse($t, [System.Globalization.NumberStyles]::Float, $script:Inv, [ref]$d)) { return $d }
    return $null
}

function Get-Median {
    param([double[]]$Verdier)
    $v = @($Verdier | Where-Object { $null -ne $_ } | Sort-Object)
    if ($v.Count -eq 0) { return $null }
    $m = [int][math]::Floor($v.Count / 2)
    if ($v.Count % 2 -eq 1) { return [double]$v[$m] }
    return ([double]$v[$m - 1] + [double]$v[$m]) / 2.0
}

function Get-Snitt {
    param([double[]]$Verdier)
    $v = @($Verdier | Where-Object { $null -ne $_ })
    if ($v.Count -eq 0) { return $null }
    $sum = 0.0
    foreach ($x in $v) { $sum += [double]$x }
    return $sum / $v.Count
}

function Get-StdAvvik {
    # Populasjons-standardavvik (tilsvarer "mdev" i ping).
    param([double[]]$Verdier)
    $v = @($Verdier | Where-Object { $null -ne $_ })
    if ($v.Count -eq 0) { return $null }
    $snitt = Get-Snitt -Verdier $v
    $sum = 0.0
    foreach ($x in $v) { $sum += ([double]$x - $snitt) * ([double]$x - $snitt) }
    return [math]::Sqrt($sum / $v.Count)
}

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
             $e -is [System.Management.Automation.MethodInvocationException] -or $e.GetType().Name -eq 'HttpRequestException')) {
            $e = $e.InnerException
            $n++
        }
        if ($null -eq $e) { return '' }
        return ($e.GetType().Name + ': ' + $e.Message)
    } catch {
        return [string]$Feil
    }
}

function Test-Kommando {
    param([string]$Navn)
    if ($script:Verktoy.ContainsKey($Navn)) { return [bool]$script:Verktoy[$Navn] }
    $finnes = $false
    try { $finnes = ($null -ne (Get-Command -Name $Navn -ErrorAction SilentlyContinue)) } catch { $finnes = $false }
    $script:Verktoy[$Navn] = $finnes
    return $finnes
}

function Test-Ipv4Adresse {
    param([string]$Tekst)
    if (-not $Tekst) { return $false }
    return [bool]([regex]::IsMatch($Tekst.Trim(), '^\d{1,3}(\.\d{1,3}){3}$'))
}

function Test-Ipv4IOmraade {
    # Sjekker om en IPv4-adresse ligger i et CIDR-område (f.eks. 100.64.0.0/10 for CGNAT).
    param([string]$Adresse, [string]$Cidr)
    if (-not (Test-Ipv4Adresse $Adresse)) { return $false }
    $deler = $Cidr.Split('/')
    $nett = [System.Net.IPAddress]::Parse($deler[0]).GetAddressBytes()
    $adr = [System.Net.IPAddress]::Parse($Adresse.Trim()).GetAddressBytes()
    $bits = [int]$deler[1]
    $nettInt = [uint64]$nett[0] * 16777216 + [uint64]$nett[1] * 65536 + [uint64]$nett[2] * 256 + [uint64]$nett[3]
    $adrInt = [uint64]$adr[0] * 16777216 + [uint64]$adr[1] * 65536 + [uint64]$adr[2] * 256 + [uint64]$adr[3]
    if ($bits -le 0) { return $true }
    $blokk = [uint64][math]::Pow(2, 32 - $bits)
    return (([math]::Floor($nettInt / $blokk)) -eq ([math]::Floor($adrInt / $blokk)))
}

function Get-TerskelStatus {
    # Lavere er bedre: PASS <= $Pass, WARN <= $Warn, ellers FAIL.
    param([double]$Verdi, [double]$Pass, [double]$Warn)
    if ($Verdi -le $Pass) { return 'PASS' }
    if ($Verdi -le $Warn) { return 'WARN' }
    return 'FAIL'
}

function Get-TerskelStatusHoy {
    # Høyere er bedre: PASS >= $Pass, WARN >= $Warn, ellers FAIL.
    param([double]$Verdi, [double]$Pass, [double]$Warn)
    if ($Verdi -ge $Pass) { return 'PASS' }
    if ($Verdi -ge $Warn) { return 'WARN' }
    return 'FAIL'
}

# ------------------------------------------------------------------------------------
# Statuslinjer, resultater og rå utdata
# ------------------------------------------------------------------------------------
function Write-Status {
    param([string]$Status, [string]$Seksjon, [string]$Sjekk, [string]$Verdi = '', [string]$Terskel = '')
    $linje = "[$Status] ${Seksjon}: $Sjekk"
    if ($Verdi) { $linje += " — $Verdi" }
    if ($Terskel) { $linje += " (terskel $Terskel)" }
    $farge = 'Cyan'
    switch ($Status) {
        'PASS' { $farge = 'Green' }
        'WARN' { $farge = 'Yellow' }
        'FAIL' { $farge = 'Red' }
        'SKIP' { $farge = 'DarkGray' }
        default { $farge = 'Cyan' }
    }
    if ($script:Farger) {
        try { Write-Host $linje -ForegroundColor $farge } catch { Write-Host $linje }
    } else {
        Write-Host $linje
    }
}

function Write-Overskrift {
    param([int]$Nr)
    $tekst = ''
    $tekst = "`n=== $($script:SeksjonNavn[$Nr]) ==="
    if ($script:Farger) {
        try { Write-Host $tekst -ForegroundColor White } catch { Write-Host $tekst }
    } else {
        Write-Host $tekst
    }
}

function Add-Resultat {
    param(
        [Parameter(Mandatory = $true)][int]$Nr,
        [Parameter(Mandatory = $true)][string]$Sjekk,
        [Parameter(Mandatory = $true)][ValidateSet('PASS', 'WARN', 'FAIL', 'INFO', 'SKIP')][string]$Status,
        [string]$Verdi = '',
        [string]$Terskel = '',
        [string]$Detaljer = ''
    )
    $seksjon = $script:SeksjonNavn[$Nr]
    if ($null -eq $Verdi) { $Verdi = '' }
    if ($null -eq $Terskel) { $Terskel = '' }
    if ($null -eq $Detaljer) { $Detaljer = '' }
    $script:Resultater.Add([pscustomobject]@{
        seksjon  = $seksjon
        sjekk    = $Sjekk
        status   = $Status
        verdi    = $Verdi
        terskel  = $Terskel
        detaljer = $Detaljer
    })
    Write-Status -Status $Status -Seksjon $seksjon -Sjekk $Sjekk -Verdi $Verdi -Terskel $Terskel
}

function Add-RaaUtdata {
    param([int]$Nr, [string]$Tittel, [string]$Tekst)
    $seksjon = $script:SeksjonNavn[$Nr]
    if (-not $script:RaaUtdata.ContainsKey($seksjon)) {
        $script:RaaUtdata[$seksjon] = New-Object System.Collections.Generic.List[object]
    }
    if ($null -eq $Tekst) { $Tekst = '' }
    $Tekst = $Tekst.TrimEnd()
    if (-not $Tekst) { $Tekst = '(ingen utdata)' }
    $script:RaaUtdata[$seksjon].Add([pscustomobject]@{ tittel = $Tittel; tekst = $Tekst })
}

function ConvertTo-Tekst {
    # Gjør objekter om til tekst for rapporten (tabellformat, bred nok til at ingenting kuttes).
    param($Objekt, [int]$Bredde = 200)
    try {
        if ($null -eq $Objekt) { return '' }
        return (($Objekt | Format-Table -AutoSize -Wrap | Out-String -Width $Bredde).TrimEnd())
    } catch {
        try { return (($Objekt | Out-String -Width $Bredde).TrimEnd()) } catch { return [string]$Objekt }
    }
}

function Invoke-SeksjonTrygt {
    # Kjører en seksjon; en uventet feil gir [FAIL] "uventet feil" i stedet for at hele skriptet stopper.
    param([int]$Nr, [scriptblock]$Kode)
    Write-Overskrift -Nr $Nr
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    try {
        & $Kode
    } catch {
        $melding = Get-Feilmelding $_
        $spor = ''
        try { $spor = [string]$_.ScriptStackTrace } catch { }
        Add-Resultat -Nr $Nr -Sjekk 'uventet feil' -Status FAIL -Verdi $melding -Detaljer $spor
    }
    $sw.Stop()
    if ($script:Farger) {
        try { Write-Host ("    (seksjon {0} ferdig på {1} s)" -f $Nr, (Format-Tall ($sw.Elapsed.TotalSeconds) 1)) -ForegroundColor DarkGray } catch { }
    } else {
        Write-Host ("    (seksjon {0} ferdig på {1} s)" -f $Nr, (Format-Tall ($sw.Elapsed.TotalSeconds) 1))
    }
}

# ------------------------------------------------------------------------------------
# Eksterne kommandoer med tidsavbrudd (aldri heng)
# ------------------------------------------------------------------------------------
function Invoke-Ekstern {
    param([string]$Exe, [string[]]$Argumenter = @(), [int]$TimeoutSek = 60)
    $res = [pscustomobject]@{
        Kjort = $false; Kommando = ("{0} {1}" -f $Exe, ($Argumenter -join ' ')); Utdata = ''; Feil = ''
        ExitCode = -1; TidsAvbrutt = $false
    }
    $cmd = $null
    try { $cmd = Get-Command -Name $Exe -ErrorAction SilentlyContinue | Select-Object -First 1 } catch { $cmd = $null }
    if ($null -eq $cmd) { $res.Feil = "kommandoen '$Exe' finnes ikke"; return $res }
    $sti = Get-Egenskap $cmd 'Path' ''
    if (-not $sti) { $sti = Get-Egenskap $cmd 'Source' $Exe }
    if (-not $sti) { $sti = $Exe }
    $argTekst = ($Argumenter | ForEach-Object { if ($_ -match '\s') { '"' + $_ + '"' } else { $_ } }) -join ' '
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $sti
    $psi.Arguments = $argTekst
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.RedirectStandardInput = $true
    $psi.CreateNoWindow = $true
    try {
        # Konsollens (OEM-)koding gir riktig dekoding av æøå i ping/netsh/ipconfig på norsk Windows.
        $psi.StandardOutputEncoding = [Console]::OutputEncoding
        $psi.StandardErrorEncoding = [Console]::OutputEncoding
    } catch { }
    $p = New-Object System.Diagnostics.Process
    $p.StartInfo = $psi
    try {
        $null = $p.Start()
    } catch {
        $res.Feil = Get-Feilmelding $_
        return $res
    }
    $res.Kjort = $true
    try { $p.StandardInput.Close() } catch { }
    $utTask = $p.StandardOutput.ReadToEndAsync()
    $feilTask = $p.StandardError.ReadToEndAsync()
    $ferdig = $false
    try { $ferdig = $p.WaitForExit($TimeoutSek * 1000) } catch { $ferdig = $false }
    if (-not $ferdig) {
        $res.TidsAvbrutt = $true
        try { $p.Kill() } catch { }
        try { $null = $p.WaitForExit(3000) } catch { }
    } else {
        try { $res.ExitCode = $p.ExitCode } catch { }
    }
    try { if ($utTask.Wait(5000)) { $res.Utdata = [string]$utTask.Result } } catch { }
    try { if ($feilTask.Wait(2000)) { $res.Feil = [string]$feilTask.Result } } catch { }
    if ($res.TidsAvbrutt) { $res.Feil = ("tidsavbrudd etter {0} s. {1}" -f $TimeoutSek, $res.Feil).Trim() }
    try { $p.Dispose() } catch { }
    return $res
}

function Get-PingStotte {
    # 'windows' = ping.exe, 'linux' = iputils ping, '' = ikke støttet/ikke funnet.
    if (-not (Test-Kommando 'ping')) { return '' }
    if ($script:PaaWindows) { return 'windows' }
    if ($script:PaaLinux) { return 'linux' }
    return ''
}

function Invoke-Ping {
    # Kjører ping med tidsavbrudd og tolker svarene lokalt-uavhengig (time=/tid=, '<1ms' regnes som 1 ms).
    param([string]$Maal, [int]$Antall = 4, [int]$TimeoutMs = 1000, [int]$Nyttelast = 0, [switch]$IkkeFragmenter)
    $res = [pscustomobject]@{
        Kjort = $false; Kommando = ''; Utdata = ''; Feil = ''; Sendt = $Antall; Mottatt = 0; TapProsent = 100.0
        Tider = @(); Snitt = $null; Min = $null; Maks = $null; Jitter = $null; Median = $null; TidsAvbrutt = $false
    }
    $stotte = Get-PingStotte
    if (-not $stotte) { $res.Feil = 'ping ikke tilgjengelig'; return $res }
    $arg = @()
    if ($stotte -eq 'windows') {
        $arg = @('-n', "$Antall", '-w', "$TimeoutMs")
        if ($IkkeFragmenter) { $arg += '-f' }
        if ($Nyttelast -gt 0) { $arg += @('-l', "$Nyttelast") }
        $arg += @('-4', $Maal)
    } else {
        $sek = [int][math]::Max(1, [math]::Ceiling($TimeoutMs / 1000.0))
        $arg = @('-c', "$Antall", '-W', "$sek", '-n')
        if ($IkkeFragmenter) { $arg += @('-M', 'do') }
        if ($Nyttelast -gt 0) { $arg += @('-s', "$Nyttelast") }
        $arg += $Maal
    }
    $tid = [int]($Antall * ([math]::Ceiling($TimeoutMs / 1000.0) + 1) + 10)
    $ut = Invoke-Ekstern -Exe 'ping' -Argumenter $arg -TimeoutSek $tid
    $res.Kjort = $ut.Kjort
    $res.Kommando = $ut.Kommando
    $res.Utdata = $ut.Utdata
    $res.Feil = $ut.Feil
    $res.TidsAvbrutt = $ut.TidsAvbrutt
    if (-not $ut.Kjort) { return $res }
    $tekst = [string]$ut.Utdata
    $m = [regex]::Matches($tekst, '(?i)(?:time|tid)\s*[=<]\s*(\d+(?:[.,]\d+)?)\s*ms')
    if ($m.Count -eq 0) { $m = [regex]::Matches($tekst, '(?im)^.*\b(?:bytes|byte)\b.*[=<]\s*(\d+(?:[.,]\d+)?)\s*ms') }
    $tider = New-Object System.Collections.Generic.List[double]
    foreach ($x in $m) {
        $v = ConvertTo-Tall $x.Groups[1].Value
        if ($null -ne $v) { $tider.Add([double]$v) }
    }
    $res.Tider = @($tider.ToArray())
    $res.Mottatt = $tider.Count
    if ($res.Mottatt -gt $res.Sendt) { $res.Mottatt = $res.Sendt }
    if ($Antall -gt 0) { $res.TapProsent = [math]::Round((($Antall - $res.Mottatt) / [double]$Antall) * 100.0, 1) }
    if ($tider.Count -gt 0) {
        $res.Snitt = Get-Snitt -Verdier $res.Tider
        $res.Min = ($res.Tider | Measure-Object -Minimum).Minimum
        $res.Maks = ($res.Tider | Measure-Object -Maximum).Maximum
        $res.Jitter = Get-StdAvvik -Verdier $res.Tider
        $res.Median = Get-Median -Verdier $res.Tider
    }
    return $res
}

function Invoke-Traceroute {
    # tracert.exe (Windows) eller traceroute (Linux). Hopp med tider; '*' = tidsavbrudd.
    param([string]$Maal, [int]$MaksHopp = 15, [int]$TimeoutMs = 1500)
    $res = [pscustomobject]@{ Kjort = $false; Kommando = ''; Utdata = ''; Feil = ''; Hopp = @(); TidsAvbrutt = $false }
    $exe = ''
    $arg = @()
    if ($script:PaaWindows -and (Test-Kommando 'tracert')) {
        $exe = 'tracert'
        $arg = @('-d', '-h', "$MaksHopp", '-w', "$TimeoutMs", '-4', $Maal)
    } elseif ((-not $script:PaaWindows) -and (Test-Kommando 'traceroute')) {
        $exe = 'traceroute'
        $arg = @('-n', '-m', "$MaksHopp", '-w', (Format-Tall ($TimeoutMs / 1000.0) 1), $Maal)
    } else {
        $res.Feil = 'tracert/traceroute ikke tilgjengelig'
        return $res
    }
    $tid = [int]([math]::Ceiling($MaksHopp * 3 * $TimeoutMs / 1000.0) + 15)
    $ut = Invoke-Ekstern -Exe $exe -Argumenter $arg -TimeoutSek $tid
    $res.Kjort = $ut.Kjort
    $res.Kommando = $ut.Kommando
    $res.Utdata = $ut.Utdata
    $res.Feil = $ut.Feil
    $res.TidsAvbrutt = $ut.TidsAvbrutt
    if (-not $ut.Kjort) { return $res }
    $hopp = New-Object System.Collections.Generic.List[object]
    foreach ($linje in ([string]$ut.Utdata -split "`r?`n")) {
        $lm = [regex]::Match($linje, '^\s*(\d{1,2})\s+(.*)$')
        if (-not $lm.Success) { continue }
        $rest = $lm.Groups[2].Value
        $tider = New-Object System.Collections.Generic.List[object]
        foreach ($tm in [regex]::Matches($rest, '(?:<\s*)?(\d+(?:[.,]\d+)?)\s*ms|(\*)')) {
            if ($tider.Count -ge 3) { break }
            if ($tm.Groups[2].Success) { $tider.Add($null) } else { $tider.Add((ConvertTo-Tall $tm.Groups[1].Value)) }
        }
        if ($tider.Count -eq 0) { continue }
        $adr = ''
        $am = [regex]::Match($rest, '\b(\d{1,3}(?:\.\d{1,3}){3})\b')
        if ($am.Success) { $adr = $am.Groups[1].Value }
        $gyldige = @($tider | Where-Object { $null -ne $_ })
        $snitt = $null
        if ($gyldige.Count -gt 0) { $snitt = Get-Snitt -Verdier ([double[]]$gyldige) }
        $hopp.Add([pscustomobject]@{
            Nr = [int]$lm.Groups[1].Value; Adresse = $adr; Tider = @($tider.ToArray()); Snitt = $snitt
            Tap = ($tider.Count - $gyldige.Count)
        })
    }
    $res.Hopp = @($hopp.ToArray())
    return $res
}

# ------------------------------------------------------------------------------------
# TCP/TLS, DNS og HTTP-hjelpere med tidsavbrudd
# ------------------------------------------------------------------------------------
function Test-TcpTilkobling {
    # TCP-connect (BeginConnect + WaitOne) og valgfri TLS-handshake (SslStream) med tidsmåling.
    param([string]$Vert, [int]$Port = 443, [int]$TimeoutMs = 3000, [switch]$Tls)
    $res = [pscustomobject]@{
        Ok = $false; ConnectMs = $null; TlsOk = $false; TlsMs = $null; Protokoll = ''; Chiffer = ''; Feil = ''; Tidsavbrudd = $false
    }
    $tc = $null
    $ssl = $null
    try {
        $tc = New-Object System.Net.Sockets.TcpClient
        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        $ar = $tc.BeginConnect($Vert, $Port, $null, $null)
        if (-not $ar.AsyncWaitHandle.WaitOne($TimeoutMs)) {
            $res.Tidsavbrudd = $true
            $res.Feil = "tidsavbrudd etter $TimeoutMs ms"
            try { $tc.Close() } catch { }
            return $res
        }
        $tc.EndConnect($ar)
        $sw.Stop()
        $res.ConnectMs = [math]::Round($sw.Elapsed.TotalMilliseconds, 1)
        $res.Ok = $true
        if ($Tls) {
            $tc.ReceiveTimeout = 6000
            $tc.SendTimeout = 6000
            $ssl = New-Object System.Net.Security.SslStream($tc.GetStream(), $false)
            $prot = [System.Security.Authentication.SslProtocols]::Tls12
            try {
                if ([enum]::GetNames([System.Security.Authentication.SslProtocols]) -contains 'Tls13') {
                    $prot = [System.Security.Authentication.SslProtocols]([int][System.Security.Authentication.SslProtocols]::Tls12 -bor [int][enum]::Parse([System.Security.Authentication.SslProtocols], 'Tls13'))
                }
            } catch { $prot = [System.Security.Authentication.SslProtocols]::Tls12 }
            $sw2 = [System.Diagnostics.Stopwatch]::StartNew()
            try {
                $ssl.AuthenticateAsClient($Vert, $null, $prot, $false)
                $sw2.Stop()
                $res.TlsOk = $true
                $res.TlsMs = [math]::Round($sw2.Elapsed.TotalMilliseconds, 1)
                try { $res.Protokoll = [string]$ssl.SslProtocol } catch { }
                try {
                    $suite = Get-Egenskap $ssl 'NegotiatedCipherSuite' $null
                    if ($null -ne $suite) { $res.Chiffer = [string]$suite }
                    else { $res.Chiffer = ('{0} {1} bit' -f [string]$ssl.CipherAlgorithm, [int]$ssl.CipherStrength) }
                } catch { }
            } catch {
                $sw2.Stop()
                $res.TlsMs = [math]::Round($sw2.Elapsed.TotalMilliseconds, 1)
                $res.Feil = 'TLS: ' + (Get-Feilmelding $_)
            }
        }
    } catch {
        $res.Feil = Get-Feilmelding $_
    } finally {
        if ($null -ne $ssl) { try { $ssl.Dispose() } catch { } }
        if ($null -ne $tc) { try { $tc.Close() } catch { } }
    }
    return $res
}

function Invoke-DnsUdp {
    # Minimal DNS-klient over UDP (A-oppslag) for plattformer uten Resolve-DnsName. Gir også NXDOMAIN (rcode 3).
    param([string]$Navn, [string]$Server, [int]$TimeoutMs = 3000)
    $res = [pscustomobject]@{ Ok = $false; Rcode = -1; Adresser = @(); Ms = $null; Feil = ''; Nxdomain = $false; Tidsavbrudd = $false; Metode = 'UDP' }
    $u = $null
    try {
        $id = Get-Random -Minimum 1 -Maximum 65535
        $pk = New-Object System.Collections.Generic.List[byte]
        $pk.Add([byte](($id -shr 8) -band 0xFF)); $pk.Add([byte]($id -band 0xFF))
        $pk.Add([byte]1); $pk.Add([byte]0)            # flagg: RD
        $pk.Add([byte]0); $pk.Add([byte]1)            # QDCOUNT = 1
        $pk.Add([byte]0); $pk.Add([byte]0); $pk.Add([byte]0); $pk.Add([byte]0); $pk.Add([byte]0); $pk.Add([byte]0)
        foreach ($etikett in $Navn.TrimEnd('.').Split('.')) {
            $b = [System.Text.Encoding]::ASCII.GetBytes($etikett)
            $pk.Add([byte]$b.Length)
            foreach ($x in $b) { $pk.Add([byte]$x) }
        }
        $pk.Add([byte]0)
        $pk.Add([byte]0); $pk.Add([byte]1)            # QTYPE A
        $pk.Add([byte]0); $pk.Add([byte]1)            # QCLASS IN
        $bytes = $pk.ToArray()
        $ip = [System.Net.IPAddress]::Parse($Server)
        $u = New-Object System.Net.Sockets.UdpClient($ip.AddressFamily)
        $u.Client.ReceiveTimeout = $TimeoutMs
        $u.Client.SendTimeout = $TimeoutMs
        $ep = New-Object System.Net.IPEndPoint($ip, 53)
        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        $null = $u.Send($bytes, $bytes.Length, $ep)
        $fra = New-Object System.Net.IPEndPoint([System.Net.IPAddress]::Any, 0)
        if ($ip.AddressFamily -eq [System.Net.Sockets.AddressFamily]::InterNetworkV6) { $fra = New-Object System.Net.IPEndPoint([System.Net.IPAddress]::IPv6Any, 0) }
        $svar = $u.Receive([ref]$fra)
        $sw.Stop()
        $res.Ms = [math]::Round($sw.Elapsed.TotalMilliseconds, 1)
        if ($svar.Length -lt 12) { $res.Feil = 'for kort svar'; return $res }
        $res.Rcode = [int]($svar[3] -band 0x0F)
        $ancount = ([int]$svar[6] -shl 8) + [int]$svar[7]
        $pos = 12
        while ($pos -lt $svar.Length -and $svar[$pos] -ne 0) { $pos += [int]$svar[$pos] + 1 }
        $pos += 5
        $adresser = New-Object System.Collections.Generic.List[string]
        for ($i = 0; $i -lt $ancount -and $pos -lt $svar.Length; $i++) {
            if (($svar[$pos] -band 0xC0) -eq 0xC0) { $pos += 2 }
            else {
                while ($pos -lt $svar.Length -and $svar[$pos] -ne 0) { $pos += [int]$svar[$pos] + 1 }
                $pos += 1
            }
            if ($pos + 10 -gt $svar.Length) { break }
            $type = ([int]$svar[$pos] -shl 8) + [int]$svar[$pos + 1]
            $rdlen = ([int]$svar[$pos + 8] -shl 8) + [int]$svar[$pos + 9]
            $pos += 10
            if ($type -eq 1 -and $rdlen -eq 4 -and ($pos + 4) -le $svar.Length) {
                $adresser.Add(('{0}.{1}.{2}.{3}' -f [int]$svar[$pos], [int]$svar[$pos + 1], [int]$svar[$pos + 2], [int]$svar[$pos + 3]))
            }
            $pos += $rdlen
        }
        $res.Adresser = @($adresser.ToArray())
        if ($res.Rcode -eq 3) { $res.Nxdomain = $true; $res.Feil = 'NXDOMAIN' }
        elseif ($res.Rcode -eq 0) { $res.Ok = $true }
        else { $res.Feil = "rcode $($res.Rcode)" }
    } catch {
        $res.Feil = Get-Feilmelding $_
        if ($res.Feil -match 'timed out|tidsavbrudd|TimedOut|Tidsavbrudd') { $res.Tidsavbrudd = $true }
    } finally {
        if ($null -ne $u) { try { $u.Close() } catch { } }
    }
    return $res
}

function Resolve-Navn {
    # A-oppslag mot valgfri resolver. Resolve-DnsName på Windows, ellers UDP-klient (med server) eller .NET (systemresolver).
    param([string]$Navn, [string]$Server = '', [int]$TimeoutMs = 4000)
    $res = [pscustomobject]@{ Ok = $false; Adresser = @(); Ms = $null; Feil = ''; Nxdomain = $false; Tidsavbrudd = $false; Metode = '' }
    if (Test-Kommando 'Resolve-DnsName') {
        $res.Metode = 'Resolve-DnsName'
        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        try {
            $p = @{ Name = $Navn; Type = 'A'; DnsOnly = $true; NoHostsFile = $true; ErrorAction = 'Stop' }
            if ($Server) { $p['Server'] = $Server }
            $svar = @(Resolve-DnsName @p)
            $sw.Stop()
            $res.Ms = [math]::Round($sw.Elapsed.TotalMilliseconds, 1)
            $res.Ok = $true
            $adr = New-Object System.Collections.Generic.List[string]
            foreach ($rec in $svar) {
                $t = [string](Get-Egenskap $rec 'Type' '')
                if ($t -eq 'A') {
                    $ipv = Get-Egenskap $rec 'IPAddress' $null
                    if ($null -eq $ipv) { $ipv = Get-Egenskap $rec 'IP4Address' $null }
                    if ($null -ne $ipv) { $adr.Add([string]$ipv) }
                }
            }
            $res.Adresser = @($adr.ToArray())
        } catch {
            $sw.Stop()
            $res.Ms = [math]::Round($sw.Elapsed.TotalMilliseconds, 1)
            $res.Feil = Get-Feilmelding $_
            $fqid = ''
            try { $fqid = [string]$_.FullyQualifiedErrorId } catch { }
            $kode = -1
            try { $kode = [int](Get-Egenskap $_.Exception 'NativeErrorCode' -1) } catch { }
            if ($kode -eq 9003 -or $fqid -match 'DNS_ERROR_RCODE_NAME_ERROR' -or $res.Feil -match 'does not exist|finnes ikke|NXDOMAIN') { $res.Nxdomain = $true }
            elseif ($kode -eq 1460 -or $fqid -match 'ERROR_TIMEOUT' -or $res.Feil -match 'timed out|tidsavbr') { $res.Tidsavbrudd = $true }
            elseif ($kode -eq 9501 -or $fqid -match 'DNS_INFO_NO_RECORDS') { $res.Ok = $true; $res.Feil = 'ingen A-poster (NODATA)' }
        }
        return $res
    }
    if ($Server) {
        return (Invoke-DnsUdp -Navn $Navn -Server $Server -TimeoutMs $TimeoutMs)
    }
    $res.Metode = '.NET systemresolver'
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    try {
        $task = [System.Net.Dns]::GetHostAddressesAsync($Navn)
        if (-not $task.Wait($TimeoutMs)) {
            $sw.Stop()
            $res.Ms = [math]::Round($sw.Elapsed.TotalMilliseconds, 1)
            $res.Tidsavbrudd = $true
            $res.Feil = "tidsavbrudd etter $TimeoutMs ms"
            return $res
        }
        $sw.Stop()
        $res.Ms = [math]::Round($sw.Elapsed.TotalMilliseconds, 1)
        $res.Ok = $true
        $res.Adresser = @($task.Result | Where-Object { $_.AddressFamily -eq [System.Net.Sockets.AddressFamily]::InterNetwork } | ForEach-Object { $_.ToString() })
    } catch {
        $sw.Stop()
        $res.Ms = [math]::Round($sw.Elapsed.TotalMilliseconds, 1)
        $res.Feil = Get-Feilmelding $_
        if ($res.Feil -match 'NoData|HostNotFound|No such host|not known|finnes ikke|does not exist') { $res.Nxdomain = $true }
    }
    return $res
}

function Invoke-HttpEnkel {
    # Invoke-WebRequest med tidsavbrudd; returnerer status også ved feil/omdirigering (captive portal-deteksjon).
    param([string]$Url, [int]$TimeoutSek = 10, [int]$MaksRedirect = 5, [hashtable]$Hoder = @{})
    $res = [pscustomobject]@{ Ok = $false; Status = 0; Innhold = ''; Hoder = @{}; Feil = ''; Ms = $null; Location = '' }
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    try {
        $p = @{ Uri = $Url; UseBasicParsing = $true; TimeoutSec = $TimeoutSek; MaximumRedirection = $MaksRedirect; ErrorAction = 'Stop' }
        if ($Hoder.Count -gt 0) { $p['Headers'] = $Hoder }
        $w = Invoke-WebRequest @p
        $sw.Stop()
        $res.Status = [int]$w.StatusCode
        $res.Ok = $true
        $innhold = Get-Egenskap $w 'Content' ''
        if ($innhold -is [byte[]]) { $innhold = [System.Text.Encoding]::UTF8.GetString($innhold) }
        $res.Innhold = [string]$innhold
        $hd = Get-Egenskap $w 'Headers' $null
        if ($null -ne $hd) {
            foreach ($k in @($hd.Keys)) { $res.Hoder[[string]$k] = (@($hd[$k]) -join ', ') }
        }
        if ($res.Hoder.ContainsKey('Location')) { $res.Location = $res.Hoder['Location'] }
    } catch {
        $sw.Stop()
        $res.Feil = Get-Feilmelding $_
        $svar = $null
        try { $svar = Get-Egenskap $_.Exception 'Response' $null } catch { }
        if ($null -ne $svar) {
            try { $res.Status = [int]$svar.StatusCode } catch { }
            try {
                $hd = Get-Egenskap $svar 'Headers' $null
                if ($null -ne $hd) {
                    $loc = $null
                    try { $loc = Get-Egenskap $hd 'Location' $null } catch { }
                    if ($null -eq $loc) { try { $loc = $hd['Location'] } catch { } }
                    if ($null -ne $loc) { $res.Location = [string]$loc }
                }
            } catch { }
        }
    }
    $res.Ms = [math]::Round($sw.Elapsed.TotalMilliseconds, 1)
    return $res
}

function New-HttpKlient {
    param([int]$TimeoutSek = 30)
    if (-not $script:HarHttpClient) { return $null }
    $k = New-Object System.Net.Http.HttpClient
    $k.Timeout = [TimeSpan]::FromSeconds($TimeoutSek)
    try { $k.DefaultRequestHeaders.ExpectContinue = $false } catch { }
    try { $null = $k.DefaultRequestHeaders.UserAgent.TryParseAdd('nettsjekk/1.0') } catch { }
    return $k
}

function Measure-HttpNedlasting {
    # Laster ned en URL med HttpClient (ResponseHeadersRead), 1 MB-biter, stopper ved EOF eller maks sekunder.
    param([string]$Url, [int]$MaksSek = 25, [int]$TimeoutSek = 30)
    $res = [pscustomobject]@{ Ok = $false; Bytes = [long]0; Sekunder = 0.0; MbitPerSek = $null; Status = 0; Feil = ''; Ferdig = $false; Ttfb = $null }
    $k = $null
    $strom = $null
    $svar = $null
    try {
        $k = New-HttpKlient -TimeoutSek $TimeoutSek
        if ($null -eq $k) { $res.Feil = 'HttpClient ikke tilgjengelig'; return $res }
        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        $t = $k.GetAsync($Url, [System.Net.Http.HttpCompletionOption]::ResponseHeadersRead)
        $svar = $t.Result
        $res.Status = [int]$svar.StatusCode
        $res.Ttfb = [math]::Round($sw.Elapsed.TotalMilliseconds, 0)
        if (-not $svar.IsSuccessStatusCode) { $res.Feil = "HTTP $($res.Status)"; return $res }
        $strom = $svar.Content.ReadAsStreamAsync().Result
        $buf = New-Object byte[] (1048576)
        $tot = [long]0
        while ($sw.Elapsed.TotalSeconds -lt $MaksSek) {
            $rt = $strom.ReadAsync($buf, 0, $buf.Length)
            if (-not $rt.Wait(15000)) { $res.Feil = 'lesing stoppet (15 s uten data)'; break }
            $n = [int]$rt.Result
            if ($n -le 0) { $res.Ferdig = $true; break }
            $tot += $n
        }
        $sw.Stop()
        $res.Bytes = $tot
        $res.Sekunder = [math]::Round($sw.Elapsed.TotalSeconds, 2)
        if ($res.Sekunder -gt 0 -and $tot -gt 0) {
            $res.MbitPerSek = [math]::Round(($tot * 8.0) / $res.Sekunder / 1000000.0, 1)
            $res.Ok = $true
        }
    } catch {
        $res.Feil = Get-Feilmelding $_
    } finally {
        if ($null -ne $strom) { try { $strom.Dispose() } catch { } }
        if ($null -ne $svar) { try { $svar.Dispose() } catch { } }
        if ($null -ne $k) { try { $k.Dispose() } catch { } }
    }
    return $res
}

function Get-HttpTekst {
    # Henter en tekstressurs (m3u8 o.l.) med HttpClient og tidsavbrudd.
    param([string]$Url, [int]$TimeoutSek = 15)
    $res = [pscustomobject]@{ Ok = $false; Tekst = ''; Status = 0; Feil = ''; Ms = $null }
    $k = $null
    try {
        $k = New-HttpKlient -TimeoutSek $TimeoutSek
        if ($null -eq $k) { $res.Feil = 'HttpClient ikke tilgjengelig'; return $res }
        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        $svar = $k.GetAsync($Url).Result
        $res.Status = [int]$svar.StatusCode
        $res.Tekst = [string]$svar.Content.ReadAsStringAsync().Result
        $sw.Stop()
        $res.Ms = [math]::Round($sw.Elapsed.TotalMilliseconds, 0)
        $res.Ok = $svar.IsSuccessStatusCode
        if (-not $res.Ok) { $res.Feil = "HTTP $($res.Status)" }
        try { $svar.Dispose() } catch { }
    } catch {
        $res.Feil = Get-Feilmelding $_
    } finally {
        if ($null -ne $k) { try { $k.Dispose() } catch { } }
    }
    return $res
}

# ------------------------------------------------------------------------------------
# Grensesnitt og gateway (Get-NetAdapter der det finnes, ellers .NET NetworkInterface)
# ------------------------------------------------------------------------------------
function Get-NetworkInterfaceInfo {
    # Leser alle aktive grensesnitt via .NET (fungerer på alle plattformer).
    $liste = New-Object System.Collections.Generic.List[object]
    try {
        $alle = [System.Net.NetworkInformation.NetworkInterface]::GetAllNetworkInterfaces()
    } catch { return @() }
    foreach ($nic in $alle) {
        $o = [pscustomobject]@{
            Navn = ''; Beskrivelse = ''; Id = ''; Type = ''; Status = ''; Mac = ''; HastighetBps = [long]-1
            Ipv4 = @(); Ipv6 = @(); Gateways = @(); Dns = @(); DhcpServer = @(); Mtu = $null; ErWifi = $false
        }
        try { $o.Navn = [string]$nic.Name } catch { }
        try { $o.Beskrivelse = [string]$nic.Description } catch { }
        try { $o.Id = [string]$nic.Id } catch { }
        try { $o.Type = [string]$nic.NetworkInterfaceType } catch { }
        try { $o.Status = [string]$nic.OperationalStatus } catch { }
        try { $o.Mac = [string]$nic.GetPhysicalAddress().ToString() } catch { }
        try { $o.HastighetBps = [long]$nic.Speed } catch { }
        $o.ErWifi = ($o.Type -eq 'Wireless80211')
        try {
            $ipp = $nic.GetIPProperties()
            $v4 = New-Object System.Collections.Generic.List[string]
            $v6 = New-Object System.Collections.Generic.List[string]
            foreach ($ua in $ipp.UnicastAddresses) {
                $a = $ua.Address
                if ($a.AddressFamily -eq [System.Net.Sockets.AddressFamily]::InterNetwork) {
                    $pre = ''
                    try { $pl = Get-Egenskap $ua 'PrefixLength' $null; if ($null -ne $pl) { $pre = "/$pl" } } catch { }
                    if (-not $pre) { try { $mask = Get-Egenskap $ua 'IPv4Mask' $null; if ($null -ne $mask) { $pre = ' maske ' + $mask.ToString() } } catch { } }
                    $v4.Add($a.ToString() + $pre)
                } elseif ($a.AddressFamily -eq [System.Net.Sockets.AddressFamily]::InterNetworkV6) {
                    $v6.Add($a.ToString())
                }
            }
            $o.Ipv4 = @($v4.ToArray())
            $o.Ipv6 = @($v6.ToArray())
            $o.Gateways = @($ipp.GatewayAddresses | ForEach-Object { $_.Address.ToString() })
            $o.Dns = @($ipp.DnsAddresses | ForEach-Object { $_.ToString() })
            try { $o.DhcpServer = @($ipp.DhcpServerAddresses | ForEach-Object { $_.ToString() }) } catch { }
            try { $o.Mtu = [int]$ipp.GetIPv4Properties().Mtu } catch { }
        } catch { }
        $liste.Add($o)
    }
    return @($liste.ToArray())
}

function Get-PrimaertGrensesnitt {
    # Velger grensesnittet: -Grensesnitt, ellers det med standardruten, ellers første fysiske "Up".
    $res = [pscustomobject]@{
        Navn = ''; Beskrivelse = ''; Indeks = -1; Guid = ''; Mac = ''; PermanentMac = ''; LinkSpeed = ''; ErWifi = $false
        Kilde = ''; Status = ''; Ipv4 = @(); Ipv6 = @(); Gateways = @(); Dns = @(); DhcpServer = @(); Mtu = $null
        Adapter = $null; NetInfo = $null; MediaType = ''; PhysicalMediaType = ''; Virtuell = $false
    }
    $funnet = $false
    if (Test-Kommando 'Get-NetAdapter') {
        try {
            $alle = @(Get-NetAdapter -ErrorAction Stop | Where-Object { [string](Get-Egenskap $_ 'Status' '') -eq 'Up' })
            $valgt = $null
            if ($Grensesnitt) {
                $valgt = $alle | Where-Object {
                    (Get-Egenskap $_ 'Name' '') -eq $Grensesnitt -or
                    [string](Get-Egenskap $_ 'InterfaceDescription' '') -like "*$Grensesnitt*" -or
                    (Get-Egenskap $_ 'InterfaceAlias' '') -eq $Grensesnitt
                } | Select-Object -First 1
            }
            if ($null -eq $valgt -and (Test-Kommando 'Get-NetRoute')) {
                $ruter = @(Get-NetRoute -DestinationPrefix '0.0.0.0/0' -ErrorAction SilentlyContinue | Sort-Object -Property RouteMetric, InterfaceMetric)
                foreach ($r in $ruter) {
                    $idx = Get-Egenskap $r 'ifIndex' -1
                    $kand = $alle | Where-Object { (Get-Egenskap $_ 'ifIndex' -2) -eq $idx } | Select-Object -First 1
                    if ($null -ne $kand) { $valgt = $kand; break }
                }
            }
            if ($null -eq $valgt) {
                $valgt = $alle | Where-Object { -not [bool](Get-Egenskap $_ 'Virtual' $false) } | Sort-Object -Property ifIndex | Select-Object -First 1
            }
            if ($null -eq $valgt -and $alle.Count -gt 0) { $valgt = $alle[0] }
            if ($null -ne $valgt) {
                $res.Navn = [string](Get-Egenskap $valgt 'Name' '')
                $res.Beskrivelse = [string](Get-Egenskap $valgt 'InterfaceDescription' '')
                $res.Indeks = [int](Get-Egenskap $valgt 'ifIndex' -1)
                $res.Guid = [string](Get-Egenskap $valgt 'InterfaceGuid' '')
                $res.Mac = [string](Get-Egenskap $valgt 'MacAddress' '')
                $res.PermanentMac = [string](Get-Egenskap $valgt 'PermanentAddress' '')
                $res.LinkSpeed = [string](Get-Egenskap $valgt 'LinkSpeed' '')
                $res.Status = [string](Get-Egenskap $valgt 'Status' '')
                $res.MediaType = [string](Get-Egenskap $valgt 'MediaType' '')
                $res.PhysicalMediaType = [string](Get-Egenskap $valgt 'PhysicalMediaType' '')
                $res.Virtuell = [bool](Get-Egenskap $valgt 'Virtual' $false)
                $res.ErWifi = ($res.PhysicalMediaType -match '802\.11' -or $res.MediaType -match '802\.11' -or
                    $res.Beskrivelse -match 'Wi-?Fi|Wireless|WLAN|802\.11' -or $res.Navn -match '^Wi-?Fi|WLAN|Tr.dl.s')
                $res.Adapter = $valgt
                $res.Kilde = 'Get-NetAdapter'
                $funnet = $true
            }
        } catch { }
    }
    $nettinfo = @(Get-NetworkInterfaceInfo)
    if ($funnet) {
        $ni = $nettinfo | Where-Object { $res.Guid -and $_.Id -eq $res.Guid } | Select-Object -First 1
        if ($null -eq $ni) { $ni = $nettinfo | Where-Object { $_.Navn -eq $res.Navn } | Select-Object -First 1 }
        if ($null -ne $ni) { $res.NetInfo = $ni }
    } else {
        $aktive = @($nettinfo | Where-Object { $_.Status -eq 'Up' -and $_.Type -ne 'Loopback' -and $_.Type -ne 'Tunnel' })
        $ni = $null
        if ($Grensesnitt) { $ni = $aktive | Where-Object { $_.Navn -eq $Grensesnitt -or $_.Beskrivelse -like "*$Grensesnitt*" } | Select-Object -First 1 }
        if ($null -eq $ni) { $ni = $aktive | Where-Object { @($_.Gateways | Where-Object { Test-Ipv4Adresse $_ }).Count -gt 0 } | Select-Object -First 1 }
        if ($null -eq $ni) { $ni = $aktive | Where-Object { $_.Ipv4.Count -gt 0 } | Select-Object -First 1 }
        if ($null -ne $ni) {
            $res.Navn = $ni.Navn
            $res.Beskrivelse = $ni.Beskrivelse
            $res.Guid = $ni.Id
            $res.Mac = $ni.Mac
            $res.Status = $ni.Status
            $res.ErWifi = $ni.ErWifi
            if ($ni.HastighetBps -gt 0 -and $ni.HastighetBps -lt 1000000000000) { $res.LinkSpeed = (Format-Tall ($ni.HastighetBps / 1000000.0) 0) + ' Mbit/s' }
            $res.NetInfo = $ni
            $res.Kilde = '.NET NetworkInterface'
            $funnet = $true
        }
    }
    if ($null -ne $res.NetInfo) {
        $res.Ipv4 = @($res.NetInfo.Ipv4)
        $res.Ipv6 = @($res.NetInfo.Ipv6)
        $res.Gateways = @($res.NetInfo.Gateways)
        $res.Dns = @($res.NetInfo.Dns)
        $res.DhcpServer = @($res.NetInfo.DhcpServer)
        $res.Mtu = $res.NetInfo.Mtu
    }
    if (-not $funnet) { return $null }
    return $res
}

function Find-Gateway {
    # Standard gateway: -Gateway, ellers Get-NetRoute 0.0.0.0/0, ellers .NET GatewayAddresses. Teller også antall default-ruter.
    if ($Gateway) { $script:GatewayIp = $Gateway.Trim(); $script:AntallDefaultRuter = 1; return }
    $gw = ''
    if (Test-Kommando 'Get-NetRoute') {
        try {
            $ruter = @(Get-NetRoute -DestinationPrefix '0.0.0.0/0' -ErrorAction Stop | Sort-Object -Property RouteMetric, InterfaceMetric)
            $script:AntallDefaultRuter = $ruter.Count
            if ($null -ne $script:Primaer -and $script:Primaer.Indeks -ge 0) {
                $r = $ruter | Where-Object { (Get-Egenskap $_ 'ifIndex' -1) -eq $script:Primaer.Indeks } | Select-Object -First 1
                if ($null -ne $r) { $gw = [string](Get-Egenskap $r 'NextHop' '') }
            }
            if (-not $gw -and $ruter.Count -gt 0) { $gw = [string](Get-Egenskap $ruter[0] 'NextHop' '') }
        } catch { }
    }
    if (-not $gw -and $null -ne $script:Primaer) {
        $g = @($script:Primaer.Gateways | Where-Object { Test-Ipv4Adresse $_ })
        if ($g.Count -gt 0) { $gw = $g[0] }
        if ($script:AntallDefaultRuter -eq 0) {
            $alleGw = @()
            foreach ($n in @(Get-NetworkInterfaceInfo)) { if ($n.Status -eq 'Up') { $alleGw += @($n.Gateways | Where-Object { Test-Ipv4Adresse $_ }) } }
            $script:AntallDefaultRuter = @($alleGw | Select-Object -Unique).Count
        }
    }
    if ($gw -eq '0.0.0.0') { $gw = '' }
    $script:GatewayIp = $gw
}

# ------------------------------------------------------------------------------------
# netsh wlan-tolking (lokalt-uavhengig: "nøkkel : verdi", nøkler matches med EN|NO-regex)
# ------------------------------------------------------------------------------------
function ConvertFrom-NokkelVerdi {
    # Deler "  Nøkkel   : verdi" i en ordnet ordbok. Første forekomst av en nøkkel vinner.
    param([string[]]$Linjer)
    $d = New-Object System.Collections.Specialized.OrderedDictionary
    foreach ($l in $Linjer) {
        $m = [regex]::Match($l, '^\s*([^:]+?)\s*:\s*(.*)$')
        if (-not $m.Success) { continue }
        $k = $m.Groups[1].Value.Trim()
        if (-not $k) { continue }
        if (-not $d.Contains($k)) { $d.Add($k, $m.Groups[2].Value.Trim()) }
    }
    return $d
}

function Find-Nokkel {
    # Finner verdien for første nøkkel som matcher regex-mønsteret (ufølsom for store/små bokstaver).
    param($Ordbok, [string]$Monster, $Standard = $null)
    if ($null -eq $Ordbok) { return $Standard }
    foreach ($k in @($Ordbok.Keys)) {
        if ([regex]::IsMatch([string]$k, $Monster, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)) { return $Ordbok[$k] }
    }
    return $Standard
}

function ConvertFrom-NetshInterfaces {
    # 'netsh wlan show interfaces' -> liste av ordbøker (én per WLAN-grensesnitt).
    param([string]$Tekst)
    $blokker = New-Object System.Collections.Generic.List[object]
    $gjeldende = $null
    foreach ($l in ($Tekst -split "`r?`n")) {
        $m = [regex]::Match($l, '^\s*([^:]+?)\s*:\s*(.*)$')
        if (-not $m.Success) { continue }
        $k = $m.Groups[1].Value.Trim()
        $v = $m.Groups[2].Value.Trim()
        if ([regex]::IsMatch($k, '^(name|navn)$', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)) {
            $gjeldende = New-Object System.Collections.Specialized.OrderedDictionary
            $blokker.Add($gjeldende)
        }
        if ($null -eq $gjeldende) {
            $gjeldende = New-Object System.Collections.Specialized.OrderedDictionary
            $blokker.Add($gjeldende)
        }
        if (-not $gjeldende.Contains($k)) { $gjeldende.Add($k, $v) }
    }
    return @($blokker.ToArray())
}

function ConvertFrom-NetshNetworks {
    # 'netsh wlan show networks mode=bssid' -> liste av BSSID-objekter (SSID, BSSID, Signal %, Kanal, Bånd, Radiotype).
    param([string]$Tekst)
    $liste = New-Object System.Collections.Generic.List[object]
    $ssid = ''
    $auth = ''
    $gjeldende = $null
    foreach ($l in ($Tekst -split "`r?`n")) {
        $m = [regex]::Match($l, '^\s*([^:]+?)\s*:\s*(.*)$')
        if (-not $m.Success) { continue }
        $k = $m.Groups[1].Value.Trim()
        $v = $m.Groups[2].Value.Trim()
        if ([regex]::IsMatch($k, '^SSID\s+\d+$', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)) {
            $ssid = $v; $auth = ''; $gjeldende = $null; continue
        }
        if ([regex]::IsMatch($k, '^BSSID\s+\d+$', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)) {
            $gjeldende = [pscustomobject]@{ SSID = $ssid; BSSID = $v.ToLower(); SignalProsent = $null; Kanal = $null; Band = ''; Radiotype = ''; Autentisering = $auth }
            $liste.Add($gjeldende)
            continue
        }
        if ($null -eq $gjeldende) {
            if ([regex]::IsMatch($k, '^(authentication|godkjenning|autentisering)$', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)) { $auth = $v }
            continue
        }
        if ([regex]::IsMatch($k, '^signal$', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)) {
            $pm = [regex]::Match($v, '(\d+)')
            if ($pm.Success) { $gjeldende.SignalProsent = [int]$pm.Groups[1].Value }
        } elseif ([regex]::IsMatch($k, '^(channel|kanal)$', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)) {
            $cm = [regex]::Match($v, '(\d+)')
            if ($cm.Success) { $gjeldende.Kanal = [int]$cm.Groups[1].Value }
        } elseif ([regex]::IsMatch($k, '^b.{1,2}nd$', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)) {
            $gjeldende.Band = $v
        } elseif ([regex]::IsMatch($k, '^radio\s*type$', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)) {
            $gjeldende.Radiotype = $v
        }
    }
    return @($liste.ToArray())
}

function ConvertTo-Dbm {
    # netsh gir signal i prosent; tilnærming: dBm ≈ (prosent / 2) - 100.
    param($Prosent)
    if ($null -eq $Prosent) { return $null }
    return [int][math]::Round(([double]$Prosent / 2.0) - 100.0)
}

function Get-BandFraKanal {
    param($Kanal, [string]$BandTekst = '')
    if ($BandTekst) {
        if ($BandTekst -match '2[.,]4') { return '2,4 GHz' }
        if ($BandTekst -match '^\s*5') { return '5 GHz' }
        if ($BandTekst -match '^\s*6') { return '6 GHz' }
        return $BandTekst
    }
    if ($null -eq $Kanal) { return 'ukjent' }
    if ([int]$Kanal -le 14) { return '2,4 GHz' }
    return '5/6 GHz'
}

# ------------------------------------------------------------------------------------
# Seksjon 0 — System og verktøy
# ------------------------------------------------------------------------------------
function Invoke-Seksjon0 {
    $os = ''
    $oppstart = $null
    if ($script:PaaWindows -and (Test-Kommando 'Get-CimInstance')) {
        try {
            $o = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop
            $os = ('{0} {1} (build {2})' -f (Get-Egenskap $o 'Caption' ''), (Get-Egenskap $o 'Version' ''), (Get-Egenskap $o 'BuildNumber' ''))
            $oppstart = Get-Egenskap $o 'LastBootUpTime' $null
        } catch { }
    }
    if (-not $os) {
        $os = [Environment]::OSVersion.VersionString
        if ($PSVersionTable.ContainsKey('OS') -and $PSVersionTable['OS']) { $os = [string]$PSVersionTable['OS'] }
    }
    $script:OsTekst = $os
    Add-Resultat -Nr 0 -Sjekk 'Operativsystem' -Status INFO -Verdi $os
    Add-Resultat -Nr 0 -Sjekk 'PowerShell' -Status INFO -Verdi ('{0} ({1})' -f $PSVersionTable.PSVersion.ToString(), $script:PsUtgave)
    $vert = [Environment]::MachineName
    $bruker = ''
    try { $bruker = [Environment]::UserName } catch { }
    Add-Resultat -Nr 0 -Sjekk 'Vertsnavn og bruker' -Status INFO -Verdi ('{0} / {1}' -f $vert, $bruker)

    # Adminrettigheter (kun opportunistisk — aldri påkrevd)
    $script:ErAdmin = $false
    if ($script:PaaWindows) {
        try {
            $id = [Security.Principal.WindowsIdentity]::GetCurrent()
            $pr = New-Object Security.Principal.WindowsPrincipal($id)
            $script:ErAdmin = $pr.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
        } catch { $script:ErAdmin = $false }
    }
    if ($script:ErAdmin) { Add-Resultat -Nr 0 -Sjekk 'Administratorrettigheter' -Status INFO -Verdi 'ja (wlanreport blir generert i seksjon 12)' }
    else { Add-Resultat -Nr 0 -Sjekk 'Administratorrettigheter' -Status INFO -Verdi 'nei (ikke nødvendig; wlanreport hoppes over)' }

    if ($null -ne $oppstart) {
        try {
            $opp = (Get-Date) - [datetime]$oppstart
            Add-Resultat -Nr 0 -Sjekk 'Oppetid' -Status INFO -Verdi ('{0} d {1} t {2} min (oppstart {3})' -f $opp.Days, $opp.Hours, $opp.Minutes, ([datetime]$oppstart).ToString('yyyy-MM-dd HH:mm'))
        } catch { }
    } elseif (Test-Path -LiteralPath '/proc/uptime') {
        try {
            $sek = ConvertTo-Tall ((Get-Content -LiteralPath '/proc/uptime' -ErrorAction Stop | Select-Object -First 1) -split '\s+')[0]
            if ($null -ne $sek) { $ts = [TimeSpan]::FromSeconds($sek); Add-Resultat -Nr 0 -Sjekk 'Oppetid' -Status INFO -Verdi ('{0} d {1} t {2} min' -f $ts.Days, $ts.Hours, $ts.Minutes) }
        } catch { }
    }
    $tz = ''
    try { $tz = [TimeZoneInfo]::Local.Id } catch { }
    Add-Resultat -Nr 0 -Sjekk 'Lokal tid og tidssone' -Status INFO -Verdi ('{0} ({1}, UTC{2})' -f $script:StartTid.ToString('yyyy-MM-dd HH:mm:ss'), $tz, $script:StartTid.ToString('zzz'))
    $modus = 'normal'
    if ($Hurtig) { $modus = 'hurtig (-Hurtig: hopper over seksjon 8, 9 og 10)' }
    Add-Resultat -Nr 0 -Sjekk 'Kjøremodus' -Status INFO -Verdi $modus
    Add-Resultat -Nr 0 -Sjekk 'Parametre' -Status INFO -Verdi ('ForventetNed={0} Mbit/s, ForventetOpp={1} Mbit/s, IperfServer={2}, InterneNavn={3}, Gateway={4}, Grensesnitt={5}' -f $ForventetNed, $ForventetOpp, $IperfServer, ($InterneNavn -join ','), $Gateway, $Grensesnitt)

    # Verktøy
    $verktoyListe = @(
        @{ Navn = 'ping'; Type = 'exe'; Viktig = $true; Hint = 'Innebygd i Windows (C:\Windows\System32). På Linux: sudo apt install iputils-ping' },
        @{ Navn = 'tracert'; Type = 'exe'; Viktig = $script:PaaWindows; Hint = 'Innebygd i Windows (C:\Windows\System32)' },
        @{ Navn = 'traceroute'; Type = 'exe'; Viktig = (-not $script:PaaWindows); Hint = 'Linux: sudo apt install traceroute' },
        @{ Navn = 'netsh'; Type = 'exe'; Viktig = $script:PaaWindows; Hint = 'Innebygd i Windows (C:\Windows\System32)' },
        @{ Navn = 'netstat'; Type = 'exe'; Viktig = $script:PaaWindows; Hint = 'Innebygd i Windows (C:\Windows\System32)' },
        @{ Navn = 'ipconfig'; Type = 'exe'; Viktig = $script:PaaWindows; Hint = 'Innebygd i Windows (C:\Windows\System32)' },
        @{ Navn = 'w32tm'; Type = 'exe'; Viktig = $script:PaaWindows; Hint = 'Innebygd i Windows (C:\Windows\System32)' },
        @{ Navn = 'iperf3'; Type = 'exe'; Viktig = $false; Hint = 'Last ned iperf3 fra https://iperf.fr/iperf-download.php og legg iperf3.exe ved siden av skriptet (Linux: sudo apt install iperf3)' },
        @{ Navn = 'Resolve-DnsName'; Type = 'cmdlet'; Viktig = $true; Hint = 'Windows-modulen DnsClient (innebygd fra Windows 8/2012). På Linux/macOS: bruk sjekk-klient.sh (dig)' },
        @{ Navn = 'Get-NetAdapter'; Type = 'cmdlet'; Viktig = $true; Hint = 'Windows-modulen NetAdapter (innebygd). På Linux/macOS: bruk sjekk-klient.sh' },
        @{ Navn = 'Get-NetIPConfiguration'; Type = 'cmdlet'; Viktig = $false; Hint = 'Windows-modulen NetTCPIP (innebygd)' },
        @{ Navn = 'Get-NetRoute'; Type = 'cmdlet'; Viktig = $false; Hint = 'Windows-modulen NetTCPIP (innebygd)' },
        @{ Navn = 'Get-NetTCPSetting'; Type = 'cmdlet'; Viktig = $false; Hint = 'Windows-modulen NetTCPIP (innebygd)' },
        @{ Navn = 'Get-NetNeighbor'; Type = 'cmdlet'; Viktig = $false; Hint = 'Windows-modulen NetTCPIP (innebygd)' },
        @{ Navn = 'Get-NetConnectionProfile'; Type = 'cmdlet'; Viktig = $false; Hint = 'Windows-modulen NetConnection (innebygd)' },
        @{ Navn = 'Get-DnsClientServerAddress'; Type = 'cmdlet'; Viktig = $false; Hint = 'Windows-modulen DnsClient (innebygd)' },
        @{ Navn = 'Get-DnsClientDohServerAddress'; Type = 'cmdlet'; Viktig = $false; Hint = 'Finnes bare på Windows 11 / Server 2022 (DoH-innstillinger)' },
        @{ Navn = 'Get-CimInstance'; Type = 'cmdlet'; Viktig = $false; Hint = 'Innebygd i Windows PowerShell 3+ / PowerShell 7 på Windows' },
        @{ Navn = 'Get-VpnConnection'; Type = 'cmdlet'; Viktig = $false; Hint = 'Windows-modulen VpnClient (innebygd)' },
        @{ Navn = 'Get-NetFirewallProfile'; Type = 'cmdlet'; Viktig = $false; Hint = 'Windows-modulen NetSecurity (innebygd)' }
    )
    $tabell = New-Object System.Collections.Generic.List[object]
    foreach ($v in $verktoyListe) {
        $finnes = Test-Kommando $v['Navn']
        $status = 'mangler'
        if ($finnes) { $status = 'ok' }
        $tabell.Add([pscustomobject]@{ Verktoy = $v['Navn']; Type = $v['Type']; Status = $status; Installasjon = $v['Hint'] })
        if (-not $finnes -and $v['Viktig']) {
            Add-Resultat -Nr 0 -Sjekk ('Verktøy: ' + $v['Navn']) -Status SKIP -Verdi 'mangler' -Detaljer ('Installasjon: ' + $v['Hint'])
        }
    }
    $antallOk = @($tabell | Where-Object { $_.Status -eq 'ok' }).Count
    Add-Resultat -Nr 0 -Sjekk 'Verktøy funnet' -Status INFO -Verdi ('{0} av {1} (se rå tabell)' -f $antallOk, $tabell.Count)
    if ($script:HarHttpClient) { Add-Resultat -Nr 0 -Sjekk 'HttpClient (.NET)' -Status INFO -Verdi 'tilgjengelig (hastighet/video)' }
    else { Add-Resultat -Nr 0 -Sjekk 'HttpClient (.NET)' -Status SKIP -Verdi 'ikke tilgjengelig' -Detaljer 'Installasjon: .NET Framework 4.5+ (System.Net.Http) — innebygd i Windows 8+/Server 2012+' }
    if (-not $script:PaaWindows) {
        Add-Resultat -Nr 0 -Sjekk 'Plattform' -Status INFO -Verdi 'ikke Windows — Windows-spesifikke sjekker (netsh, ipconfig, ping.exe, Net*-cmdlets) gir SKIP. Bruk sjekk-klient.sh på Linux/macOS.'
    }
    Add-RaaUtdata -Nr 0 -Tittel 'Verktøy' -Tekst (ConvertTo-Tekst $tabell)
    Add-RaaUtdata -Nr 0 -Tittel '$PSVersionTable' -Tekst (($PSVersionTable.GetEnumerator() | Sort-Object -Property Key | ForEach-Object { '{0} = {1}' -f $_.Key, ($_.Value -join ', ') }) -join "`n")
}

# ------------------------------------------------------------------------------------
# Seksjon 1 — Lenke og Wi-Fi
# ------------------------------------------------------------------------------------
function Invoke-Seksjon1 {
    $script:Primaer = Get-PrimaertGrensesnitt
    if ($null -eq $script:Primaer) {
        Add-Resultat -Nr 1 -Sjekk 'Aktivt grensesnitt' -Status FAIL -Verdi 'ingen aktiv nettverkstilkobling funnet'
        return
    }
    $p = $script:Primaer
    $script:ErWifi = [bool]$p.ErWifi
    Find-Gateway
    Add-Resultat -Nr 1 -Sjekk 'Aktivt grensesnitt' -Status INFO -Verdi ('{0} — {1} (kilde: {2})' -f $p.Navn, $p.Beskrivelse, $p.Kilde)
    $medie = 'kablet/annet'
    if ($script:ErWifi) { $medie = 'Wi-Fi (Native 802.11)' }
    elseif ($p.PhysicalMediaType -or $p.MediaType) { $medie = ('{0} / {1}' -f $p.MediaType, $p.PhysicalMediaType).Trim(' /') }
    Add-Resultat -Nr 1 -Sjekk 'Medietype' -Status INFO -Verdi $medie
    if ($p.LinkSpeed) { Add-Resultat -Nr 1 -Sjekk 'Lenkehastighet' -Status INFO -Verdi $p.LinkSpeed }
    else { Add-Resultat -Nr 1 -Sjekk 'Lenkehastighet' -Status INFO -Verdi 'ukjent' }
    if ($p.Mac) {
        $macRen = ($p.Mac -replace '[^0-9A-Fa-f]', '').ToUpper()
        $permRen = ($p.PermanentMac -replace '[^0-9A-Fa-f]', '').ToUpper()
        $lokal = $false
        if ($macRen.Length -ge 2) { $lokal = ('2', '6', 'A', 'E') -contains $macRen.Substring(1, 1) }
        if ($permRen -and $macRen -ne $permRen) {
            Add-Resultat -Nr 1 -Sjekk 'MAC-adresse' -Status INFO -Verdi ('{0} (tilfeldig/privat MAC — fysisk adresse {1})' -f $p.Mac, $p.PermanentMac) -Detaljer 'Tilfeldig MAC gir ny DHCP-lease og nytt klientnavn i XIQ per nettverk.'
        } elseif ($lokal) {
            Add-Resultat -Nr 1 -Sjekk 'MAC-adresse' -Status INFO -Verdi ('{0} (lokalt administrert bit satt — trolig tilfeldig MAC)' -f $p.Mac)
        } else {
            Add-Resultat -Nr 1 -Sjekk 'MAC-adresse' -Status INFO -Verdi $p.Mac
        }
    }

    if (-not $script:PaaWindows) {
        Add-Resultat -Nr 1 -Sjekk 'Wi-Fi-detaljer' -Status SKIP -Verdi 'krever Windows (netsh wlan)' -Detaljer 'Installasjon: kjør sjekk-klient.ps1 på Windows-PC-en, eller sjekk-klient.sh (iw/wdutil) på Linux/macOS'
        Add-RaaUtdata -Nr 1 -Tittel 'Grensesnitt (.NET NetworkInterface)' -Tekst (ConvertTo-Tekst (@(Get-NetworkInterfaceInfo) | Select-Object Navn, Type, Status, Mac, @{ n = 'Ipv4'; e = { $_.Ipv4 -join ' ' } }, @{ n = 'Gateways'; e = { $_.Gateways -join ' ' } }, Mtu))
        return
    }
    if (-not (Test-Kommando 'netsh')) {
        Add-Resultat -Nr 1 -Sjekk 'Wi-Fi-detaljer' -Status SKIP -Verdi 'netsh mangler' -Detaljer 'Installasjon: innebygd i Windows (C:\Windows\System32\netsh.exe)'
        return
    }

    # netsh wlan show interfaces
    $ut = Invoke-Ekstern -Exe 'netsh' -Argumenter @('wlan', 'show', 'interfaces') -TimeoutSek 20
    Add-RaaUtdata -Nr 1 -Tittel 'netsh wlan show interfaces' -Tekst ($ut.Utdata + "`n" + $ut.Feil)
    $blokker = @()
    if ($ut.Kjort) { $blokker = @(ConvertFrom-NetshInterfaces -Tekst $ut.Utdata) }
    $wlan = $null
    foreach ($b in $blokker) {
        $ssidTest = Find-Nokkel $b '^SSID$' ''
        if ($ssidTest) { $wlan = $b; break }
    }
    if ($null -eq $wlan -and $blokker.Count -gt 0) { $wlan = $blokker[0] }
    $script:Wlan = $wlan
    $ssid = ''
    if ($null -ne $wlan) { $ssid = [string](Find-Nokkel $wlan '^SSID$' '') }
    if ($null -eq $wlan -or -not $ssid) {
        if ($script:ErWifi) {
            Add-Resultat -Nr 1 -Sjekk 'Wi-Fi-tilkobling' -Status SKIP -Verdi 'netsh wlan viste ingen tilkoblet WLAN-profil' -Detaljer 'Sjekk at tjenesten WLAN AutoConfig (wlansvc) kjører, eller at du faktisk er tilkoblet Wi-Fi.'
        } else {
            Add-Resultat -Nr 1 -Sjekk 'Wi-Fi-tilkobling' -Status INFO -Verdi 'ikke tilkoblet via Wi-Fi (kablet). Wi-Fi-sjekkene hoppes over.'
        }
    } else {
        $script:ErWifi = $true
        $bssid = [string](Find-Nokkel $wlan '^BSSID$' '')
        $profil = [string](Find-Nokkel $wlan '^(profile|profil)$' '')
        $radio = [string](Find-Nokkel $wlan '^radio\s*type$' '')
        $bandTekst = [string](Find-Nokkel $wlan '^b.{1,2}nd$' '')
        $kanalTekst = [string](Find-Nokkel $wlan '^(channel|kanal)$' '')
        $signalTekst = [string](Find-Nokkel $wlan '^signal$' '')
        $rx = [string](Find-Nokkel $wlan '^(receive\s*rate|mottakshastighet)' '')
        $tx = [string](Find-Nokkel $wlan '^(transmit\s*rate|overf.{1,2}ringshastighet|sendehastighet)' '')
        $auth = [string](Find-Nokkel $wlan '^(authentication|godkjenning|autentisering)$' '')
        $chiffer = [string](Find-Nokkel $wlan '^(cipher|kryptering|chiffer)$' '')
        $tilstand = [string](Find-Nokkel $wlan '^(state|tilstand|status)$' '')
        $kanal = $null
        $km = [regex]::Match($kanalTekst, '(\d+)')
        if ($km.Success) { $kanal = [int]$km.Groups[1].Value }
        $signalPct = $null
        $sm = [regex]::Match($signalTekst, '(\d+)')
        if ($sm.Success) { $signalPct = [int]$sm.Groups[1].Value }
        $dbm = ConvertTo-Dbm $signalPct
        $band = Get-BandFraKanal -Kanal $kanal -BandTekst $bandTekst
        Add-Resultat -Nr 1 -Sjekk 'Tilkoblet SSID' -Status INFO -Verdi ('{0} (BSSID {1}, profil {2}, tilstand {3})' -f $ssid, $bssid, $profil, $tilstand)
        if ($ssid -ne 'Adm-nett') { Add-Resultat -Nr 1 -Sjekk 'SSID er Adm-nett' -Status INFO -Verdi ('nei — tilkoblet «{0}». Kjør sjekken fra Adm-nett for å teste admin-nettet.' -f $ssid) }
        Add-Resultat -Nr 1 -Sjekk 'Radiotype/PHY' -Status INFO -Verdi $radio
        Add-Resultat -Nr 1 -Sjekk 'Bånd og kanal' -Status INFO -Verdi ('{0}, kanal {1}' -f $band, $kanalTekst)
        if ($band -match '2,4') {
            Add-Resultat -Nr 1 -Sjekk 'Tilkoblet på 2,4 GHz' -Status WARN -Verdi ('ja (kanal {0})' -f $kanalTekst) -Terskel 'Adm-nett bør bruke 5/6 GHz' -Detaljer 'Sjekk «Preferred Band»/«Foretrukket bånd» i adapteregenskapene og båndstyring i XIQ-radioprofilen.'
        } else {
            Add-Resultat -Nr 1 -Sjekk 'Tilkoblet på 2,4 GHz' -Status PASS -Verdi ('nei ({0})' -f $band) -Terskel 'Adm-nett bør bruke 5/6 GHz'
        }
        if ($null -ne $dbm) {
            $st = 'FAIL'
            if ($dbm -ge -65) { $st = 'PASS' } elseif ($dbm -ge -72) { $st = 'WARN' }
            Add-Resultat -Nr 1 -Sjekk 'RSSI (signalstyrke)' -Status $st -Verdi ('ca. {0} dBm (netsh: {1} %)' -f $dbm, $signalPct) -Terskel 'PASS ≥ -65 dBm, WARN ≥ -72 dBm, FAIL < -72 dBm' -Detaljer 'Tilnærming: dBm ≈ (prosent / 2) − 100. netsh gir bare prosent.'
        } else {
            Add-Resultat -Nr 1 -Sjekk 'RSSI (signalstyrke)' -Status SKIP -Verdi 'signalprosent ikke funnet i netsh-utdata'
        }
        Add-Resultat -Nr 1 -Sjekk 'SNR' -Status SKIP -Verdi 'støygulv er ikke tilgjengelig via netsh' -Terskel 'PASS ≥ 25 dB, WARN ≥ 15 dB, FAIL < 15 dB' -Detaljer 'Bruk klientvisningen i ExtremeCloudIQ (RSSI/SNR per klient) eller wlanreport (admin).'
        Add-Resultat -Nr 1 -Sjekk 'Tx/Rx-rate (PHY)' -Status INFO -Verdi ('mottak {0} Mbit/s, sending {1} Mbit/s' -f $rx, $tx)
        $sikkerhetStatus = 'INFO'
        if ($auth -match 'Open|Åpen|WEP' -or $chiffer -match 'TKIP|WEP|None|Ingen') { $sikkerhetStatus = 'WARN' }
        Add-Resultat -Nr 1 -Sjekk 'Autentisering og chiffer' -Status $sikkerhetStatus -Verdi ('{0} / {1}' -f $auth, $chiffer) -Terskel 'WPA2/WPA3 med CCMP/GCMP forventet'
    }

    # Nabo-BSSID-er (samme SSID)
    $utN = Invoke-Ekstern -Exe 'netsh' -Argumenter @('wlan', 'show', 'networks', 'mode=bssid') -TimeoutSek 30
    Add-RaaUtdata -Nr 1 -Tittel 'netsh wlan show networks mode=bssid' -Tekst ($utN.Utdata + "`n" + $utN.Feil)
    $naboer = @()
    if ($utN.Kjort) { $naboer = @(ConvertFrom-NetshNetworks -Tekst $utN.Utdata) }
    $script:NaboBssid = $naboer
    if ($naboer.Count -eq 0) {
        Add-Resultat -Nr 1 -Sjekk 'Synlige BSSID-er' -Status SKIP -Verdi 'ingen BSSID-er i netsh-utdata' -Detaljer 'Windows 11 24H2+ krever plasseringstillatelse for BSSID-lister: Innstillinger > Personvern og sikkerhet > Plassering (slå på for skrivebordsapper/terminal). Alternativt: kjør fra roaming-logg.ps1 etter at tillatelsen er gitt.'
    } else {
        $sammeSsid = @()
        if ($ssid) { $sammeSsid = @($naboer | Where-Object { $_.SSID -eq $ssid }) }
        $antallSsid = @($naboer | ForEach-Object { $_.SSID } | Select-Object -Unique).Count
        Add-Resultat -Nr 1 -Sjekk 'Synlige BSSID-er' -Status INFO -Verdi ('{0} BSSID-er fordelt på {1} SSID-er; {2} på «{3}»' -f $naboer.Count, $antallSsid, $sammeSsid.Count, $ssid)
        if ($sammeSsid.Count -gt 0) {
            $tab = $sammeSsid | ForEach-Object {
                [pscustomobject]@{ BSSID = $_.BSSID; SignalProsent = $_.SignalProsent; caDbm = (ConvertTo-Dbm $_.SignalProsent); Kanal = $_.Kanal; Band = (Get-BandFraKanal -Kanal $_.Kanal -BandTekst $_.Band); Radiotype = $_.Radiotype }
            } | Sort-Object -Property SignalProsent -Descending
            Add-RaaUtdata -Nr 1 -Tittel ('BSSID-er for «' + $ssid + '» (dBm ≈ prosent/2 − 100)') -Tekst (ConvertTo-Tekst $tab)
            if ($null -ne $wlan) {
                $kanalNaa = $null
                $km2 = [regex]::Match([string](Find-Nokkel $wlan '^(channel|kanal)$' ''), '(\d+)')
                if ($km2.Success) { $kanalNaa = [int]$km2.Groups[1].Value }
                if ($null -ne $kanalNaa) {
                    $bssidNaa = ([string](Find-Nokkel $wlan '^BSSID$' '')).ToLower()
                    $samkanal = @($naboer | Where-Object { $_.Kanal -eq $kanalNaa -and $_.BSSID -ne $bssidNaa })
                    Add-Resultat -Nr 1 -Sjekk 'Andre BSSID-er på samme kanal' -Status INFO -Verdi ('{0} (kanal {1})' -f $samkanal.Count, $kanalNaa) -Detaljer 'Mange BSSID-er på samme kanal = samkanalinterferens (co-channel). Se ACSP/kanalplan i XIQ.'
                }
            }
        }
    }

    # Driver
    $utD = Invoke-Ekstern -Exe 'netsh' -Argumenter @('wlan', 'show', 'drivers') -TimeoutSek 20
    Add-RaaUtdata -Nr 1 -Tittel 'netsh wlan show drivers' -Tekst ($utD.Utdata + "`n" + $utD.Feil)
    if ($utD.Kjort -and $utD.Utdata) {
        $dr = ConvertFrom-NokkelVerdi -Linjer ($utD.Utdata -split "`r?`n")
        $radioer = [string](Find-Nokkel $dr '^radio\s*types\s*supported|^radiotyper' '')
        $drvVer = [string](Find-Nokkel $dr '^(version|versjon)$' '')
        $drvDato = [string](Find-Nokkel $dr '^(date|dato)$' '')
        $drvNavn = [string](Find-Nokkel $dr '^(driver|driver\s*name|drivernavn)' '')
        Add-Resultat -Nr 1 -Sjekk 'Wi-Fi-driver' -Status INFO -Verdi ('{0} versjon {1} ({2}); radiotyper: {3}' -f $drvNavn, $drvVer, $drvDato, $radioer)
        if ($script:ErWifi -and $radioer -and $radioer -notmatch '802\.11ax|802\.11be') {
            Add-Resultat -Nr 1 -Sjekk 'Wi-Fi 6 (802.11ax) støtte' -Status INFO -Verdi 'driveren oppgir ikke 802.11ax — AP-ene (AP305C/AP460C) kjører 11ax-profil; klienten vil bruke 11ac/11n'
        }
    }

    # Avanserte adapteregenskaper (roaming-aggressivitet, foretrukket bånd, kanalbredde m.m.)
    if ($script:ErWifi -and $p.Navn -and (Test-Kommando 'Get-NetAdapterAdvancedProperty')) {
        try {
            $avans = @(Get-NetAdapterAdvancedProperty -Name $p.Navn -ErrorAction Stop | Where-Object {
                [string](Get-Egenskap $_ 'DisplayName' '') -match 'Roam|Band|Wireless Mode|Channel Width|MIMO|Power|U-APSD|Throughput|B.nd|Kanalbredde|Str.m|Tr.dl.s'
            } | Select-Object @{ n = 'Egenskap'; e = { Get-Egenskap $_ 'DisplayName' '' } }, @{ n = 'Verdi'; e = { Get-Egenskap $_ 'DisplayValue' '' } }, @{ n = 'Registernokkel'; e = { Get-Egenskap $_ 'RegistryKeyword' '' } })
            $script:AvanserteEgenskaper = $avans
            if ($avans.Count -gt 0) {
                Add-RaaUtdata -Nr 1 -Tittel 'Get-NetAdapterAdvancedProperty (utvalg)' -Tekst (ConvertTo-Tekst $avans)
                $roam = $avans | Where-Object { $_.Egenskap -match 'Roam' } | Select-Object -First 1
                $band = $avans | Where-Object { $_.Egenskap -match 'Band|B.nd' } | Select-Object -First 1
                $tekst = @()
                if ($null -ne $roam) { $tekst += ('{0} = {1}' -f $roam.Egenskap, $roam.Verdi) }
                if ($null -ne $band) { $tekst += ('{0} = {1}' -f $band.Egenskap, $band.Verdi) }
                if ($tekst.Count -eq 0) { $tekst += ('{0} egenskaper (se rå tabell)' -f $avans.Count) }
                Add-Resultat -Nr 1 -Sjekk 'Adapteregenskaper (roaming/bånd)' -Status INFO -Verdi ($tekst -join '; ') -Detaljer 'Roaming-aggressivitet og foretrukket bånd påvirker roaming mellom AP-ene (seksjon 11).'
            } else {
                Add-Resultat -Nr 1 -Sjekk 'Adapteregenskaper (roaming/bånd)' -Status INFO -Verdi 'ingen relevante egenskaper eksponert av driveren'
            }
        } catch {
            Add-Resultat -Nr 1 -Sjekk 'Adapteregenskaper (roaming/bånd)' -Status SKIP -Verdi (Get-Feilmelding $_)
        }
    } elseif ($script:ErWifi) {
        Add-Resultat -Nr 1 -Sjekk 'Adapteregenskaper (roaming/bånd)' -Status SKIP -Verdi 'Get-NetAdapterAdvancedProperty mangler'
    }

    # Strømstyring på Wi-Fi-adapteret
    if ($script:ErWifi -and $p.Navn -and (Test-Kommando 'Get-NetAdapterPowerManagement')) {
        try {
            $pm = Get-NetAdapterPowerManagement -Name $p.Navn -ErrorAction Stop
            $tillat = [string](Get-Egenskap $pm 'AllowComputerToTurnOffDevice' '')
            Add-RaaUtdata -Nr 1 -Tittel 'Get-NetAdapterPowerManagement' -Tekst (ConvertTo-Tekst ($pm | Select-Object Name, AllowComputerToTurnOffDevice, SelectiveSuspend, DeviceSleepOnDisconnect, WakeOnMagicPacket, WakeOnPattern))
            if ($tillat -eq 'Enabled') {
                Add-Resultat -Nr 1 -Sjekk 'Strømstyring: PC-en kan slå av Wi-Fi-adapteret' -Status WARN -Verdi 'aktivert' -Terskel 'bør være deaktivert på admin-PC' -Detaljer 'Enhetsbehandling > adapter > Strømstyring > fjern «La datamaskinen slå av denne enheten for å spare strøm». (Skriptet endrer ikke dette.)'
            } else {
                Add-Resultat -Nr 1 -Sjekk 'Strømstyring: PC-en kan slå av Wi-Fi-adapteret' -Status INFO -Verdi $tillat
            }
        } catch {
            Add-Resultat -Nr 1 -Sjekk 'Strømstyring på Wi-Fi-adapteret' -Status SKIP -Verdi (Get-Feilmelding $_)
        }
    }

    # Rå adapterliste
    if (Test-Kommando 'Get-NetAdapter') {
        try {
            $alle = Get-NetAdapter -ErrorAction Stop | Sort-Object -Property ifIndex | Select-Object ifIndex, Name, InterfaceDescription, Status, LinkSpeed, MacAddress, MediaType, PhysicalMediaType, Virtual, DriverVersion, DriverDate
            Add-RaaUtdata -Nr 1 -Tittel 'Get-NetAdapter' -Tekst (ConvertTo-Tekst $alle)
        } catch { }
    }
}

# ------------------------------------------------------------------------------------
# Seksjon 2 — IP og TCP/IP
# ------------------------------------------------------------------------------------
function Invoke-Seksjon2 {
    $p = $script:Primaer
    if ($null -eq $p) {
        Add-Resultat -Nr 2 -Sjekk 'IPv4-konfigurasjon' -Status SKIP -Verdi 'ingen aktivt grensesnitt (se seksjon 1)'
        return
    }
    $ipv4 = @($p.Ipv4)
    $opprinnelse = ''
    if (Test-Kommando 'Get-NetIPAddress') {
        try {
            $adr = @(Get-NetIPAddress -InterfaceIndex $p.Indeks -AddressFamily IPv4 -ErrorAction Stop)
            if ($adr.Count -gt 0) {
                $ipv4 = @($adr | ForEach-Object { '{0}/{1}' -f (Get-Egenskap $_ 'IPAddress' ''), (Get-Egenskap $_ 'PrefixLength' '') })
                $opprinnelse = [string](Get-Egenskap $adr[0] 'PrefixOrigin' '')
            }
        } catch { }
    }
    $script:Ipv4Adresser = $ipv4
    if ($ipv4.Count -eq 0) {
        Add-Resultat -Nr 2 -Sjekk 'IPv4-adresse' -Status FAIL -Verdi 'ingen IPv4-adresse på grensesnittet'
    } else {
        $tekst = ($ipv4 -join ', ')
        if ($opprinnelse) { $tekst += " (opprinnelse: $opprinnelse)" }
        Add-Resultat -Nr 2 -Sjekk 'IPv4-adresse' -Status INFO -Verdi $tekst
        if ($opprinnelse -and $opprinnelse -ne 'Dhcp') { Add-Resultat -Nr 2 -Sjekk 'Statisk IPv4' -Status INFO -Verdi ('adressen er ikke fra DHCP (PrefixOrigin={0})' -f $opprinnelse) }
    }
    if ($script:GatewayIp) {
        Add-Resultat -Nr 2 -Sjekk 'Standard gateway' -Status INFO -Verdi $script:GatewayIp
    } else {
        Add-Resultat -Nr 2 -Sjekk 'Standard gateway' -Status FAIL -Verdi 'ingen standard gateway funnet' -Detaljer 'Uten gateway er det ikke internett-tilgang. Angi eventuelt -Gateway <IP>.'
    }
    if ($script:AntallDefaultRuter -gt 1) {
        Add-Resultat -Nr 2 -Sjekk 'Antall default-ruter (0.0.0.0/0)' -Status WARN -Verdi ('{0}' -f $script:AntallDefaultRuter) -Terskel '1' -Detaljer 'Flere default-ruter (VPN, flere adaptere, dockingstasjon) gir uforutsigbar trafikkvei.'
    } elseif ($script:AntallDefaultRuter -eq 1) {
        Add-Resultat -Nr 2 -Sjekk 'Antall default-ruter (0.0.0.0/0)' -Status PASS -Verdi '1' -Terskel '1'
    } else {
        Add-Resultat -Nr 2 -Sjekk 'Antall default-ruter (0.0.0.0/0)' -Status INFO -Verdi 'ukjent (rutetabell ikke lesbar)'
    }
    # MTU
    $mtu = $p.Mtu
    if (Test-Kommando 'Get-NetIPInterface') {
        try {
            $ii = Get-NetIPInterface -InterfaceIndex $p.Indeks -AddressFamily IPv4 -ErrorAction Stop | Select-Object -First 1
            $m = Get-Egenskap $ii 'NlMtu' $null
            if ($null -ne $m) { $mtu = [int]$m }
        } catch { }
    }
    if ($null -ne $mtu) {
        $st = 'INFO'
        if ([int]$mtu -lt 1500) { $st = 'WARN' }
        Add-Resultat -Nr 2 -Sjekk 'MTU på grensesnittet (NlMtu)' -Status $st -Verdi ('{0} byte' -f $mtu) -Terskel '1500 normalt for Ethernet/Wi-Fi' -Detaljer 'Ende-til-ende PMTU måles i seksjon 5.'
    } else {
        Add-Resultat -Nr 2 -Sjekk 'MTU på grensesnittet (NlMtu)' -Status SKIP -Verdi 'ikke tilgjengelig'
    }
    # Nettverksprofil og tilkoblingsstatus
    if (Test-Kommando 'Get-NetConnectionProfile') {
        try {
            $prof = @(Get-NetConnectionProfile -ErrorAction Stop)
            Add-RaaUtdata -Nr 2 -Tittel 'Get-NetConnectionProfile' -Tekst (ConvertTo-Tekst ($prof | Select-Object Name, InterfaceAlias, InterfaceIndex, NetworkCategory, IPv4Connectivity, IPv6Connectivity))
            $pp = $prof | Where-Object { (Get-Egenskap $_ 'InterfaceIndex' -1) -eq $p.Indeks } | Select-Object -First 1
            if ($null -eq $pp -and $prof.Count -gt 0) { $pp = $prof[0] }
            if ($null -ne $pp) {
                $kat = [string](Get-Egenskap $pp 'NetworkCategory' '')
                $v4c = [string](Get-Egenskap $pp 'IPv4Connectivity' '')
                $v6c = [string](Get-Egenskap $pp 'IPv6Connectivity' '')
                Add-Resultat -Nr 2 -Sjekk 'Nettverksprofil (NetworkCategory)' -Status INFO -Verdi ('{0} — {1}' -f (Get-Egenskap $pp 'Name' ''), $kat) -Detaljer 'Offentlig profil = strengere Windows-brannmur (mDNS/deling blokkert). Privat er vanlig på admin-nett.'
                if ($v4c -eq 'Internet') { Add-Resultat -Nr 2 -Sjekk 'IPv4-tilkobling (NCSI)' -Status PASS -Verdi $v4c -Terskel 'Internet' }
                else { Add-Resultat -Nr 2 -Sjekk 'IPv4-tilkobling (NCSI)' -Status WARN -Verdi $v4c -Terskel 'Internet' }
                Add-Resultat -Nr 2 -Sjekk 'IPv6-tilkobling (NCSI)' -Status INFO -Verdi $v6c
            }
        } catch {
            Add-Resultat -Nr 2 -Sjekk 'Nettverksprofil' -Status SKIP -Verdi (Get-Feilmelding $_)
        }
    } else {
        Add-Resultat -Nr 2 -Sjekk 'Nettverksprofil (NetworkCategory/NCSI)' -Status SKIP -Verdi 'Get-NetConnectionProfile mangler (ikke Windows)'
    }
    # IPv6 (kun INFO)
    $ipv6 = @($p.Ipv6 | Where-Object { $_ -notmatch '^fe80' })
    if (Test-Kommando 'Get-NetIPAddress') {
        try {
            $a6 = @(Get-NetIPAddress -AddressFamily IPv6 -ErrorAction Stop | Where-Object { [string](Get-Egenskap $_ 'IPAddress' '') -notmatch '^(fe80|::1)' -and [string](Get-Egenskap $_ 'AddressState' '') -ne 'Deprecated' })
            $ipv6 = @($a6 | ForEach-Object { '{0}/{1} ({2}, ifIndex {3})' -f (Get-Egenskap $_ 'IPAddress' ''), (Get-Egenskap $_ 'PrefixLength' ''), (Get-Egenskap $_ 'PrefixOrigin' ''), (Get-Egenskap $_ 'InterfaceIndex' '') })
        } catch { }
    }
    $script:Ipv6Adresser = $ipv6
    if ($ipv6.Count -gt 0) { Add-Resultat -Nr 2 -Sjekk 'IPv6-adresser (globale/ULA)' -Status INFO -Verdi ($ipv6 -join '; ') }
    else { Add-Resultat -Nr 2 -Sjekk 'IPv6-adresser (globale/ULA)' -Status INFO -Verdi 'ingen (kun link-local eller IPv6 av)' }

    # Rå utdata
    if (Test-Kommando 'Get-NetIPConfiguration') {
        try { Add-RaaUtdata -Nr 2 -Tittel 'Get-NetIPConfiguration -Detailed' -Tekst ((Get-NetIPConfiguration -Detailed -ErrorAction Stop | Out-String -Width 200).TrimEnd()) } catch { }
    }
    if (Test-Kommando 'Get-NetRoute') {
        try { Add-RaaUtdata -Nr 2 -Tittel 'Get-NetRoute (default-ruter)' -Tekst (ConvertTo-Tekst (Get-NetRoute -DestinationPrefix '0.0.0.0/0' -ErrorAction Stop | Select-Object ifIndex, InterfaceAlias, DestinationPrefix, NextHop, RouteMetric, InterfaceMetric, Protocol)) } catch { }
    }
    if (Test-Kommando 'Get-NetIPInterface') {
        try { Add-RaaUtdata -Nr 2 -Tittel 'Get-NetIPInterface (IPv4)' -Tekst (ConvertTo-Tekst (Get-NetIPInterface -AddressFamily IPv4 -ErrorAction Stop | Where-Object { [string](Get-Egenskap $_ 'ConnectionState' '') -eq 'Connected' } | Select-Object ifIndex, InterfaceAlias, NlMtu, InterfaceMetric, Dhcp, ConnectionState, AutomaticMetric)) } catch { }
    }
    if ($null -ne $p.NetInfo) {
        Add-RaaUtdata -Nr 2 -Tittel 'Primært grensesnitt (.NET NetworkInterface)' -Tekst (($p.NetInfo | Select-Object Navn, Beskrivelse, Type, Status, Mac, Mtu, @{ n = 'Ipv4'; e = { $_.Ipv4 -join ' ' } }, @{ n = 'Ipv6'; e = { $_.Ipv6 -join ' ' } }, @{ n = 'Gateways'; e = { $_.Gateways -join ' ' } }, @{ n = 'Dns'; e = { $_.Dns -join ' ' } } | Format-List | Out-String -Width 200).TrimEnd())
    }
}

# ------------------------------------------------------------------------------------
# Seksjon 3 — DHCP
# ------------------------------------------------------------------------------------
function Invoke-Seksjon3 {
    $p = $script:Primaer
    # APIPA (169.254.x.x) = DHCP feilet
    $apipa = @($script:Ipv4Adresser | Where-Object { $_ -match '^169\.254\.' })
    if ($apipa.Count -gt 0) {
        Add-Resultat -Nr 3 -Sjekk 'APIPA-adresse (169.254.x.x)' -Status FAIL -Verdi ($apipa -join ', ') -Terskel 'ingen' -Detaljer 'Klienten fikk ikke svar fra DHCP-server. Sjekk VLAN på SSID/AP-port, DHCP-scope og DHCP-relay i brannmuren.'
    } elseif ($script:Ipv4Adresser.Count -gt 0) {
        Add-Resultat -Nr 3 -Sjekk 'APIPA-adresse (169.254.x.x)' -Status PASS -Verdi 'nei' -Terskel 'ingen'
    }
    if (-not $script:PaaWindows -or -not (Test-Kommando 'Get-CimInstance')) {
        $dh = @()
        if ($null -ne $p) { $dh = @($p.DhcpServer) }
        if ($dh.Count -gt 0) { Add-Resultat -Nr 3 -Sjekk 'DHCP-server' -Status INFO -Verdi ($dh -join ', ') }
        Add-Resultat -Nr 3 -Sjekk 'DHCP-lease (Win32_NetworkAdapterConfiguration)' -Status SKIP -Verdi 'krever Windows (CIM)' -Detaljer 'Installasjon: kjør på Windows, eller bruk sjekk-klient.sh på Linux/macOS'
        return
    }
    try {
        $konf = @(Get-CimInstance -ClassName Win32_NetworkAdapterConfiguration -Filter 'IPEnabled=TRUE' -ErrorAction Stop)
        $raa = $konf | Select-Object InterfaceIndex, Description, @{ n = 'IPAddress'; e = { (Get-Egenskap $_ 'IPAddress' @()) -join ' ' } }, DHCPEnabled, DHCPServer, DHCPLeaseObtained, DHCPLeaseExpires, @{ n = 'DNSServerSearchOrder'; e = { (Get-Egenskap $_ 'DNSServerSearchOrder' @()) -join ' ' } }, @{ n = 'DNSDomainSuffixSearchOrder'; e = { (Get-Egenskap $_ 'DNSDomainSuffixSearchOrder' @()) -join ' ' } }, DNSDomain, WINSPrimaryServer, MACAddress
        Add-RaaUtdata -Nr 3 -Tittel 'Win32_NetworkAdapterConfiguration (IPEnabled=TRUE)' -Tekst (($raa | Format-List | Out-String -Width 200).TrimEnd())
        $k = $null
        if ($null -ne $p -and $p.Indeks -ge 0) { $k = $konf | Where-Object { (Get-Egenskap $_ 'InterfaceIndex' -1) -eq $p.Indeks } | Select-Object -First 1 }
        if ($null -eq $k -and $konf.Count -gt 0) { $k = $konf | Where-Object { [bool](Get-Egenskap $_ 'DHCPEnabled' $false) } | Select-Object -First 1 }
        if ($null -eq $k -and $konf.Count -gt 0) { $k = $konf[0] }
        if ($null -eq $k) {
            Add-Resultat -Nr 3 -Sjekk 'DHCP-konfigurasjon' -Status SKIP -Verdi 'ingen IP-aktiverte adaptere i CIM'
            return
        }
        $dhcpPaa = [bool](Get-Egenskap $k 'DHCPEnabled' $false)
        $server = [string](Get-Egenskap $k 'DHCPServer' '')
        $script:DhcpServer = $server
        if (-not $dhcpPaa) {
            Add-Resultat -Nr 3 -Sjekk 'DHCP aktivert' -Status INFO -Verdi 'nei — statisk IP-konfigurasjon på grensesnittet'
        } else {
            Add-Resultat -Nr 3 -Sjekk 'DHCP aktivert' -Status PASS -Verdi 'ja'
            if ($server) {
                if ($script:GatewayIp -and $server -ne $script:GatewayIp) {
                    Add-Resultat -Nr 3 -Sjekk 'DHCP-server' -Status INFO -Verdi ('{0} (ulik gateway {1} — egen DHCP-server eller relay)' -f $server, $script:GatewayIp)
                } else {
                    Add-Resultat -Nr 3 -Sjekk 'DHCP-server' -Status INFO -Verdi ('{0} (samme som gateway)' -f $server)
                }
            } else {
                Add-Resultat -Nr 3 -Sjekk 'DHCP-server' -Status WARN -Verdi 'ukjent (ingen DHCP-server registrert på grensesnittet)'
            }
            $hentet = Get-Egenskap $k 'DHCPLeaseObtained' $null
            $utloper = Get-Egenskap $k 'DHCPLeaseExpires' $null
            if ($null -ne $hentet -and $null -ne $utloper) {
                try {
                    $h = [datetime]$hentet
                    $u = [datetime]$utloper
                    $lengde = $u - $h
                    $rest = $u - (Get-Date)
                    $st = 'PASS'
                    if ($lengde.TotalMinutes -lt 10) { $st = 'WARN' }
                    Add-Resultat -Nr 3 -Sjekk 'Lease-tid' -Status $st -Verdi ('{0} (hentet {1}, utløper {2}, {3} min igjen)' -f (Format-Varighet $lengde), $h.ToString('yyyy-MM-dd HH:mm:ss'), $u.ToString('yyyy-MM-dd HH:mm:ss'), [int][math]::Round($rest.TotalMinutes)) -Terskel 'WARN < 10 min' -Detaljer 'Svært kort lease gir hyppige fornyelser og kan tømme DHCP-scope ved tilfeldige MAC-adresser.'
                } catch {
                    Add-Resultat -Nr 3 -Sjekk 'Lease-tid' -Status SKIP -Verdi (Get-Feilmelding $_)
                }
            } else {
                Add-Resultat -Nr 3 -Sjekk 'Lease-tid' -Status SKIP -Verdi 'lease-tidspunkter ikke tilgjengelig'
            }
        }
        $dnsListe = @(Get-Egenskap $k 'DNSServerSearchOrder' @())
        if ($dnsListe.Count -gt 0) { Add-Resultat -Nr 3 -Sjekk 'DNS-servere fra konfigurasjon' -Status INFO -Verdi ($dnsListe -join ', ') }
        $suffiks = @(Get-Egenskap $k 'DNSDomainSuffixSearchOrder' @())
        $domene = [string](Get-Egenskap $k 'DNSDomain' '')
        if ($suffiks.Count -gt 0 -or $domene) { Add-Resultat -Nr 3 -Sjekk 'DNS-domene og søkesuffikser' -Status INFO -Verdi (('domene: {0}; suffikser: {1}' -f $domene, ($suffiks -join ', ')).Trim()) }
        $wins = [string](Get-Egenskap $k 'WINSPrimaryServer' '')
        if ($wins) { Add-Resultat -Nr 3 -Sjekk 'WINS-server' -Status INFO -Verdi $wins -Detaljer 'WINS er utdatert; vurder å fjerne fra DHCP-alternativene.' }
    } catch {
        Add-Resultat -Nr 3 -Sjekk 'DHCP-konfigurasjon (CIM)' -Status SKIP -Verdi (Get-Feilmelding $_)
    }
    if (Test-Kommando 'ipconfig') {
        $ut = Invoke-Ekstern -Exe 'ipconfig' -Argumenter @('/all') -TimeoutSek 20
        Add-RaaUtdata -Nr 3 -Tittel 'ipconfig /all' -Tekst ($ut.Utdata + "`n" + $ut.Feil)
    }
}

function Format-Varighet {
    param([TimeSpan]$T)
    if ($T.TotalDays -ge 1) { return ('{0} d {1} t {2} min' -f [int][math]::Floor($T.TotalDays), $T.Hours, $T.Minutes) }
    if ($T.TotalHours -ge 1) { return ('{0} t {1} min' -f $T.Hours, $T.Minutes) }
    return ('{0} min {1} s' -f $T.Minutes, $T.Seconds)
}

# ------------------------------------------------------------------------------------
# Seksjon 4 — DNS
# ------------------------------------------------------------------------------------
function Get-KonfigurerteResolvere {
    $p = $script:Primaer
    $liste = New-Object System.Collections.Generic.List[string]
    if (Test-Kommando 'Get-DnsClientServerAddress') {
        try {
            $alle = @(Get-DnsClientServerAddress -AddressFamily IPv4 -ErrorAction Stop)
            Add-RaaUtdata -Nr 4 -Tittel 'Get-DnsClientServerAddress -AddressFamily IPv4' -Tekst (ConvertTo-Tekst ($alle | Where-Object { @(Get-Egenskap $_ 'ServerAddresses' @()).Count -gt 0 } | Select-Object InterfaceAlias, InterfaceIndex, @{ n = 'ServerAddresses'; e = { (Get-Egenskap $_ 'ServerAddresses' @()) -join ' ' } }))
            if ($null -ne $p -and $p.Indeks -ge 0) {
                $mine = $alle | Where-Object { (Get-Egenskap $_ 'InterfaceIndex' -1) -eq $p.Indeks } | Select-Object -First 1
                if ($null -ne $mine) { foreach ($s in @(Get-Egenskap $mine 'ServerAddresses' @())) { if ($s -and -not $liste.Contains([string]$s)) { $liste.Add([string]$s) } } }
            }
            if ($liste.Count -eq 0) {
                foreach ($a in $alle) { foreach ($s in @(Get-Egenskap $a 'ServerAddresses' @())) { if ($s -and -not $liste.Contains([string]$s)) { $liste.Add([string]$s) } } }
            }
        } catch { }
    }
    if ($liste.Count -eq 0 -and $null -ne $p) {
        foreach ($s in @($p.Dns)) { if ((Test-Ipv4Adresse $s) -and -not $liste.Contains([string]$s)) { $liste.Add([string]$s) } }
    }
    if ($liste.Count -eq 0 -and (Test-Path -LiteralPath '/etc/resolv.conf')) {
        try {
            foreach ($l in (Get-Content -LiteralPath '/etc/resolv.conf' -ErrorAction Stop)) {
                $m = [regex]::Match($l, '^\s*nameserver\s+(\S+)')
                if ($m.Success -and (Test-Ipv4Adresse $m.Groups[1].Value) -and -not $liste.Contains($m.Groups[1].Value)) { $liste.Add($m.Groups[1].Value) }
            }
        } catch { }
    }
    return @($liste.ToArray())
}

function Invoke-Seksjon4 {
    $script:Resolvere = @(Get-KonfigurerteResolvere)
    $resolvere = $script:Resolvere
    if ($resolvere.Count -eq 0) {
        Add-Resultat -Nr 4 -Sjekk 'Konfigurerte resolvere' -Status FAIL -Verdi 'ingen IPv4 DNS-servere konfigurert' -Terskel 'minst én'
    } else {
        Add-Resultat -Nr 4 -Sjekk 'Konfigurerte resolvere' -Status INFO -Verdi ($resolvere -join ', ')
        if ($script:GatewayIp -and ($resolvere -contains $script:GatewayIp)) {
            Add-Resultat -Nr 4 -Sjekk 'Resolver er gateway/brannmur' -Status INFO -Verdi ('{0} videresender trolig til ISP/ekstern DNS' -f $script:GatewayIp)
        }
    }
    # Søkesuffikser og tilkoblingsspesifikt suffiks
    if (Test-Kommando 'Get-DnsClientGlobalSetting') {
        try {
            $g = Get-DnsClientGlobalSetting -ErrorAction Stop
            $sl = @(Get-Egenskap $g 'SuffixSearchList' @())
            Add-RaaUtdata -Nr 4 -Tittel 'Get-DnsClientGlobalSetting' -Tekst (($g | Format-List | Out-String -Width 200).TrimEnd())
            if ($sl.Count -gt 0) { Add-Resultat -Nr 4 -Sjekk 'Globale søkesuffikser' -Status INFO -Verdi ($sl -join ', ') }
            else { Add-Resultat -Nr 4 -Sjekk 'Globale søkesuffikser' -Status INFO -Verdi 'ingen' }
        } catch { }
    }
    if ((Test-Kommando 'Get-DnsClient') -and ($null -ne $script:Primaer) -and ($script:Primaer.Indeks -ge 0)) {
        try {
            $dc = Get-DnsClient -InterfaceIndex $script:Primaer.Indeks -ErrorAction Stop | Select-Object -First 1
            $suf = [string](Get-Egenskap $dc 'ConnectionSpecificSuffix' '')
            $reg = [string](Get-Egenskap $dc 'RegisterThisConnectionsAddress' '')
            Add-Resultat -Nr 4 -Sjekk 'Tilkoblingsspesifikt DNS-suffiks' -Status INFO -Verdi ('«{0}» (registrer adresse i DNS: {1})' -f $suf, $reg)
        } catch { }
    }
    # DoH i Windows (Windows 11)
    if (Test-Kommando 'Get-DnsClientDohServerAddress') {
        try {
            $doh = @(Get-DnsClientDohServerAddress -ErrorAction Stop)
            if ($doh.Count -gt 0) {
                Add-RaaUtdata -Nr 4 -Tittel 'Get-DnsClientDohServerAddress' -Tekst (ConvertTo-Tekst ($doh | Select-Object ServerAddress, DohTemplate, AllowFallbackToUdp, AutoUpgrade))
                $aktive = @($doh | Where-Object { $resolvere -contains [string](Get-Egenskap $_ 'ServerAddress' '') })
                if ($aktive.Count -gt 0) {
                    Add-Resultat -Nr 4 -Sjekk 'DNS over HTTPS (Windows)' -Status INFO -Verdi ('DoH-mal finnes for konfigurert resolver: {0}' -f (($aktive | ForEach-Object { Get-Egenskap $_ 'ServerAddress' '' }) -join ', ')) -Detaljer 'Windows kan bruke DoH og gå utenom lokal DNS/brannmur-filtrering. Interne navn må da løses via suffiks/NRPT.'
                } else {
                    Add-Resultat -Nr 4 -Sjekk 'DNS over HTTPS (Windows)' -Status INFO -Verdi ('{0} kjente DoH-maler, ingen for de konfigurerte resolverne (klassisk DNS i bruk)' -f $doh.Count)
                }
            } else {
                Add-Resultat -Nr 4 -Sjekk 'DNS over HTTPS (Windows)' -Status INFO -Verdi 'ingen DoH-servere konfigurert'
            }
        } catch { Add-Resultat -Nr 4 -Sjekk 'DNS over HTTPS (Windows)' -Status SKIP -Verdi (Get-Feilmelding $_) }
    } else {
        Add-Resultat -Nr 4 -Sjekk 'DNS over HTTPS (Windows)' -Status SKIP -Verdi 'Get-DnsClientDohServerAddress finnes ikke (Windows 10 eller ikke Windows)'
    }
    Add-Resultat -Nr 4 -Sjekk 'DoH i nettleser' -Status INFO -Verdi 'Chrome/Edge/Firefox kan bruke egen DoH (går utenom lokal DNS). Sjekk nettleserinnstillingene hvis interne navn feiler bare i nettleseren.'

    # Oppslagstid per resolver (median av 5 navn)
    $nrkSvar = @{}
    $raa = New-Object System.Collections.Generic.List[string]
    $raa.Add(('{0,-18} {1,-26} {2,10}  {3}' -f 'Resolver', 'Navn', 'ms', 'Svar'))
    $antallResolvere = 0
    foreach ($r in $resolvere) {
        $antallResolvere++
        if ($antallResolvere -gt 4) { Add-Resultat -Nr 4 -Sjekk ('Oppslag via ' + $r) -Status SKIP -Verdi 'maks 4 resolvere testes'; continue }
        $tider = New-Object System.Collections.Generic.List[double]
        $feil = 0
        $tidsavbrudd = 0
        $metode = ''
        foreach ($n in $script:MaalDns) {
            $s = Resolve-Navn -Navn $n -Server $r -TimeoutMs 3000
            $metode = $s.Metode
            $svarTekst = ''
            if ($s.Ok) {
                $tider.Add([double]$s.Ms)
                $svarTekst = ($s.Adresser -join ' ')
                if (-not $svarTekst) { $svarTekst = '(NOERROR, ingen A)' }
                if ($n -eq 'nrk.no') { $nrkSvar[$r] = @($s.Adresser | Sort-Object) }
            } else {
                $feil++
                $svarTekst = 'FEIL: ' + $s.Feil
                if ($s.Tidsavbrudd) { $tidsavbrudd++ }
            }
            $msTekst = ''
            if ($null -ne $s.Ms) { $msTekst = Format-Tall ([double]$s.Ms) 0 }
            $raa.Add(('{0,-18} {1,-26} {2,10}  {3}' -f $r, $n, $msTekst, $svarTekst))
            if ($tidsavbrudd -ge 2 -and $tider.Count -eq 0) { $raa.Add(('{0,-18} {1}' -f $r, '(avbrutt: resolveren svarer ikke)')); break }
        }
        $median = Get-Median -Verdier $tider.ToArray()
        if ($feil -gt 0 -or $null -eq $median) {
            $verdi = ('{0} av {1} oppslag feilet' -f $feil, $script:MaalDns.Count)
            if ($null -ne $median) { $verdi += (', median {0} ms' -f (Format-Tall $median 0)) }
            Add-Resultat -Nr 4 -Sjekk ('Oppslag via ' + $r) -Status FAIL -Verdi ($verdi + " [$metode]") -Terskel 'PASS < 50 ms, WARN < 150 ms, FAIL ≥ 150 ms eller feil'
        } else {
            $st = 'FAIL'
            if ($median -lt 50) { $st = 'PASS' } elseif ($median -lt 150) { $st = 'WARN' }
            Add-Resultat -Nr 4 -Sjekk ('Oppslag via ' + $r) -Status $st -Verdi ('median {0} ms (min {1}, maks {2}) [{3}]' -f (Format-Tall $median 0), (Format-Tall (($tider | Measure-Object -Minimum).Minimum) 0), (Format-Tall (($tider | Measure-Object -Maximum).Maximum) 0), $metode) -Terskel 'PASS < 50 ms, WARN < 150 ms, FAIL ≥ 150 ms eller feil'
        }
    }
    Add-RaaUtdata -Nr 4 -Tittel 'DNS-oppslag per resolver (A-poster)' -Tekst ($raa -join "`n")

    # Sammenligning av A-svar for nrk.no
    if ($nrkSvar.Count -ge 2) {
        $sett = @($nrkSvar.Values | ForEach-Object { $_ -join ',' } | Select-Object -Unique)
        if ($sett.Count -eq 1) { Add-Resultat -Nr 4 -Sjekk 'A-svar for nrk.no like på tvers av resolvere' -Status INFO -Verdi ('ja: ' + $sett[0]) }
        else { Add-Resultat -Nr 4 -Sjekk 'A-svar for nrk.no like på tvers av resolvere' -Status WARN -Verdi ('nei: ' + (($nrkSvar.GetEnumerator() | ForEach-Object { '{0}={1}' -f $_.Key, ($_.Value -join ',') }) -join '; ')) -Detaljer 'Ulike svar kan være CDN/GeoDNS, men også DNS-kapring eller feil videresending i brannmuren.' }
    }

    # NXDOMAIN-test (DNS-kapring/portal)
    $tilfeldig = -join ((1..8) | ForEach-Object { [char](Get-Random -Minimum 97 -Maximum 123) })
    $nxNavn = @(("nettsjekk-{0}.invalid" -f $tilfeldig), ("nettsjekk-{0}.marivold.no" -f $tilfeldig))
    $nxResolvere = @($resolvere | Select-Object -First 3)
    if ($nxResolvere.Count -eq 0 -and -not (Test-Kommando 'Resolve-DnsName')) { $nxResolvere = @('') }
    foreach ($r in $nxResolvere) {
        foreach ($n in $nxNavn) {
            $s = Resolve-Navn -Navn $n -Server $r -TimeoutMs 3000
            $etikett = $r
            if (-not $etikett) { $etikett = 'systemresolver' }
            if ($s.Ok -and $s.Adresser.Count -gt 0) {
                Add-Resultat -Nr 4 -Sjekk ('NXDOMAIN-test ' + $n + ' via ' + $etikett) -Status FAIL -Verdi ('fikk svar: ' + ($s.Adresser -join ' ')) -Terskel 'må feile (NXDOMAIN)' -Detaljer 'Et ikke-eksisterende navn ga en adresse: DNS-kapring, captive portal eller «søkehjelp»-tjeneste hos ISP/brannmur.'
            } elseif ($s.Nxdomain -or ($s.Ok -and $s.Adresser.Count -eq 0) -or (-not $s.Ok -and -not $s.Tidsavbrudd)) {
                $v = 'NXDOMAIN/feil som forventet'
                if ($s.Ok) { $v = 'NOERROR uten A-post (akseptert)' }
                Add-Resultat -Nr 4 -Sjekk ('NXDOMAIN-test ' + $n + ' via ' + $etikett) -Status PASS -Verdi $v -Terskel 'må feile (NXDOMAIN)'
            } else {
                Add-Resultat -Nr 4 -Sjekk ('NXDOMAIN-test ' + $n + ' via ' + $etikett) -Status WARN -Verdi ('ingen svar: ' + $s.Feil) -Terskel 'må feile (NXDOMAIN)'
            }
        }
    }

    # DoH-tilgjengelighet (Cloudflare)
    $dohUrl = 'https://cloudflare-dns.com/dns-query?name=nrk.no&type=A'
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    try {
        $svar = Invoke-RestMethod -Uri $dohUrl -Headers @{ Accept = 'application/dns-json' } -UseBasicParsing -TimeoutSec 8 -ErrorAction Stop
        $sw.Stop()
        $st = [int](Get-Egenskap $svar 'Status' -1)
        $ans = @(Get-Egenskap $svar 'Answer' @())
        $adr = @($ans | ForEach-Object { Get-Egenskap $_ 'data' '' } | Where-Object { $_ })
        if ($st -eq 0 -and $adr.Count -gt 0) {
            Add-Resultat -Nr 4 -Sjekk 'DoH mot cloudflare-dns.com' -Status PASS -Verdi ('{0} ms, nrk.no = {1}' -f (Format-Tall $sw.Elapsed.TotalMilliseconds 0), ($adr -join ' ')) -Terskel 'svar med A-post'
            if ($nrkSvar.Count -gt 0) {
                $lokale = @($nrkSvar.Values | ForEach-Object { $_ } | Select-Object -Unique | Sort-Object)
                $dohSort = @($adr | Sort-Object)
                if ((($lokale -join ',') -ne ($dohSort -join ',')) -and $lokale.Count -gt 0) {
                    Add-Resultat -Nr 4 -Sjekk 'Lokal DNS vs DoH for nrk.no' -Status INFO -Verdi ('lokal: {0} | DoH: {1}' -f ($lokale -join ' '), ($dohSort -join ' ')) -Detaljer 'Forskjell kan skyldes CDN/GeoDNS; stor forskjell kan tyde på DNS-filtrering.'
                }
            }
        } else {
            Add-Resultat -Nr 4 -Sjekk 'DoH mot cloudflare-dns.com' -Status WARN -Verdi ('status {0}, {1} svar' -f $st, $adr.Count)
        }
    } catch {
        $sw.Stop()
        Add-Resultat -Nr 4 -Sjekk 'DoH mot cloudflare-dns.com' -Status FAIL -Verdi (Get-Feilmelding $_) -Terskel 'svar med A-post' -Detaljer 'DoH blokkert eller HTTPS mot cloudflare-dns.com feiler.'
    }

    # Interne navn
    if ($InterneNavn.Count -gt 0) {
        foreach ($n in $InterneNavn) {
            $s = Resolve-Navn -Navn $n -TimeoutMs 4000
            if ($s.Ok -and $s.Adresser.Count -gt 0) { Add-Resultat -Nr 4 -Sjekk ('Internt navn ' + $n) -Status PASS -Verdi (($s.Adresser -join ' ') + (' ({0} ms)' -f (Format-Tall ([double]$s.Ms) 0))) -Terskel 'må gi adresse' }
            else { Add-Resultat -Nr 4 -Sjekk ('Internt navn ' + $n) -Status FAIL -Verdi ('ingen adresse: ' + $s.Feil) -Terskel 'må gi adresse' }
        }
    } else {
        Add-Resultat -Nr 4 -Sjekk 'Interne navn' -Status INFO -Verdi 'ingen oppgitt (bruk -InterneNavn a,b,c for å teste interne DNS-navn)'
    }

    # Omvendt oppslag av gateway
    if ($script:GatewayIp) {
        $ptr = ''
        try {
            if (Test-Kommando 'Resolve-DnsName') {
                $pt = @(Resolve-DnsName -Name $script:GatewayIp -Type PTR -DnsOnly -ErrorAction Stop)
                $ptr = (($pt | ForEach-Object { Get-Egenskap $_ 'NameHost' '' } | Where-Object { $_ }) -join ', ')
            } else {
                $t = [System.Net.Dns]::GetHostEntryAsync($script:GatewayIp)
                if ($t.Wait(4000)) { $ptr = [string]$t.Result.HostName }
            }
        } catch { $ptr = '' }
        if ($ptr -and $ptr -ne $script:GatewayIp) { Add-Resultat -Nr 4 -Sjekk 'Omvendt oppslag (PTR) av gateway' -Status INFO -Verdi ('{0} → {1}' -f $script:GatewayIp, $ptr) }
        else { Add-Resultat -Nr 4 -Sjekk 'Omvendt oppslag (PTR) av gateway' -Status INFO -Verdi ('{0} → ingen PTR-post' -f $script:GatewayIp) }
    }
}

# ------------------------------------------------------------------------------------
# Seksjon 5 — Gateway og brannmur
# ------------------------------------------------------------------------------------
function Add-PingResultat {
    # Felles terskelsetting for RTT/tap/jitter mot gateway.
    param([int]$Nr, [string]$Etikett, $Ping, [double]$RttPass, [double]$RttWarn, [switch]$MedJitter, [switch]$MedTap)
    if (-not $Ping.Kjort) {
        Add-Resultat -Nr $Nr -Sjekk ('RTT ' + $Etikett) -Status SKIP -Verdi ('ping ikke tilgjengelig: ' + $Ping.Feil) -Detaljer 'Installasjon: ping er innebygd i Windows; Linux: sudo apt install iputils-ping'
        return
    }
    if ($Ping.Mottatt -eq 0) {
        Add-Resultat -Nr $Nr -Sjekk ('RTT ' + $Etikett) -Status FAIL -Verdi ('ingen svar på {0} pakker' -f $Ping.Sendt) -Terskel ('PASS ≤ {0} ms, WARN ≤ {1} ms' -f $RttPass, $RttWarn) -Detaljer 'Målet svarer ikke på ICMP (blokkert?) eller er nede.'
        if ($MedTap) { Add-Resultat -Nr $Nr -Sjekk ('Pakketap ' + $Etikett) -Status FAIL -Verdi '100 %' -Terskel 'PASS 0 %, WARN ≤ 1 %, FAIL > 1 %' }
        return
    }
    $st = Get-TerskelStatus -Verdi $Ping.Snitt -Pass $RttPass -Warn $RttWarn
    Add-Resultat -Nr $Nr -Sjekk ('RTT ' + $Etikett) -Status $st -Verdi ('snitt {0} ms (min {1}, maks {2}, median {3}, {4} pakker)' -f (Format-Tall $Ping.Snitt 1), (Format-Tall $Ping.Min 1), (Format-Tall $Ping.Maks 1), (Format-Tall $Ping.Median 1), $Ping.Sendt) -Terskel ('PASS ≤ {0} ms, WARN ≤ {1} ms, FAIL > {1} ms' -f $RttPass, $RttWarn)
    if ($MedTap) {
        $tap = [double]$Ping.TapProsent
        $stT = 'FAIL'
        if ($tap -le 0) { $stT = 'PASS' } elseif ($tap -le 1) { $stT = 'WARN' }
        Add-Resultat -Nr $Nr -Sjekk ('Pakketap ' + $Etikett) -Status $stT -Verdi ('{0} % ({1} av {2} svar)' -f (Format-Tall $tap 1), $Ping.Mottatt, $Ping.Sendt) -Terskel 'PASS 0 %, WARN ≤ 1 %, FAIL > 1 %'
    }
    if ($MedJitter -and $null -ne $Ping.Jitter) {
        $j = [double]$Ping.Jitter
        $stJ = 'FAIL'
        if ($j -lt 5) { $stJ = 'PASS' } elseif ($j -lt 20) { $stJ = 'WARN' }
        Add-Resultat -Nr $Nr -Sjekk ('Jitter ' + $Etikett) -Status $stJ -Verdi ('{0} ms (std.avvik)' -f (Format-Tall $j 1)) -Terskel 'PASS < 5 ms, WARN < 20 ms, FAIL ≥ 20 ms'
    }
}

function Test-Pmtu {
    # DF-ping med 1472/1452/1400 byte nyttelast. Gir høyeste nyttelast som gikk gjennom (0 = ingen).
    param([string]$Maal)
    $res = [pscustomobject]@{ Kjort = $false; Nyttelast = 0; Raa = ''; Feil = '' }
    foreach ($n in @(1472, 1452, 1400)) {
        $pg = Invoke-Ping -Maal $Maal -Antall 2 -TimeoutMs 1500 -Nyttelast $n -IkkeFragmenter
        $res.Raa += ("`n$ " + $pg.Kommando + "`n" + $pg.Utdata + $pg.Feil)
        if (-not $pg.Kjort) { $res.Feil = $pg.Feil; return $res }
        $res.Kjort = $true
        if ($pg.Mottatt -gt 0) { $res.Nyttelast = $n; return $res }
    }
    return $res
}

function Add-PmtuResultat {
    param([string]$Maal, [string]$Etikett)
    $r = Test-Pmtu -Maal $Maal
    Add-RaaUtdata -Nr 5 -Tittel ('PMTU (DF-ping) mot ' + $Etikett) -Tekst $r.Raa
    if (-not $r.Kjort) {
        Add-Resultat -Nr 5 -Sjekk ('PMTU mot ' + $Etikett) -Status SKIP -Verdi ('ping ikke tilgjengelig: ' + $r.Feil)
        return
    }
    $terskel = 'PASS 1500 (1472 byte DF), WARN ≤ 1452, FAIL < 1400 / svart hull'
    if ($r.Nyttelast -eq 1472) { Add-Resultat -Nr 5 -Sjekk ('PMTU mot ' + $Etikett) -Status PASS -Verdi '1500 byte ende-til-ende (1472 byte DF gikk gjennom)' -Terskel $terskel }
    elseif ($r.Nyttelast -eq 1452) { Add-Resultat -Nr 5 -Sjekk ('PMTU mot ' + $Etikett) -Status WARN -Verdi '1480 byte (bare 1452 byte DF gikk gjennom — PPPoE/tunnel?)' -Terskel $terskel }
    elseif ($r.Nyttelast -eq 1400) { Add-Resultat -Nr 5 -Sjekk ('PMTU mot ' + $Etikett) -Status WARN -Verdi 'mellom 1428 og 1479 byte (bare 1400 byte DF gikk gjennom)' -Terskel $terskel -Detaljer 'Uvanlig MTU — sjekk tunnel/VPN/PPPoE-innstillinger i brannmuren.' }
    else { Add-Resultat -Nr 5 -Sjekk ('PMTU mot ' + $Etikett) -Status FAIL -Verdi 'ingen DF-ping gikk gjennom (< 1400 byte eller PMTUD-svart hull / ICMP blokkert)' -Terskel $terskel -Detaljer 'Hvis vanlig ping virker men DF-ping feiler for alle størrelser: ICMP «fragmentation needed» blokkeres — klassisk svart hull.' }
}

function Invoke-Seksjon5 {
    $gw = $script:GatewayIp
    Add-Resultat -Nr 5 -Sjekk 'Brannmur-/gateway-modell' -Status INFO -Verdi 'ukjent leverandør — fyll inn: ____________ (modell/firmware) i trafokiosken' -Detaljer 'Fiber fra ISP terminerer i brannmuren; svitsjen står også i trafokiosken.'
    if (-not $gw) {
        Add-Resultat -Nr 5 -Sjekk 'Gateway' -Status FAIL -Verdi 'ingen gateway kjent — sjekkene mot gateway hoppes over'
    } else {
        # ARP/nabo
        $mac = ''
        if (Test-Kommando 'Get-NetNeighbor') {
            try {
                $nb = @(Get-NetNeighbor -IPAddress $gw -AddressFamily IPv4 -ErrorAction Stop | Where-Object { [string](Get-Egenskap $_ 'LinkLayerAddress' '') -notmatch '^(00-00-00-00-00-00|)$' } | Select-Object -First 1)
                if ($nb.Count -gt 0) { $mac = ('{0} (tilstand {1})' -f (Get-Egenskap $nb[0] 'LinkLayerAddress' ''), (Get-Egenskap $nb[0] 'State' '')) }
            } catch { }
        } elseif (Test-Path -LiteralPath '/proc/net/arp') {
            try {
                foreach ($l in (Get-Content -LiteralPath '/proc/net/arp' -ErrorAction Stop)) {
                    $d = $l -split '\s+'
                    if ($d.Count -ge 4 -and $d[0] -eq $gw) { $mac = $d[3]; break }
                }
            } catch { }
        }
        if ($mac) { Add-Resultat -Nr 5 -Sjekk 'ARP/nabo-oppføring for gateway' -Status INFO -Verdi ('{0} → {1}' -f $gw, $mac) -Detaljer 'MAC-prefikset (OUI) kan identifisere brannmurleverandøren.' }
        else { Add-Resultat -Nr 5 -Sjekk 'ARP/nabo-oppføring for gateway' -Status INFO -Verdi ('{0} → ingen oppføring funnet' -f $gw) }

        # RTT / tap / jitter (20 pakker)
        $pg = Invoke-Ping -Maal $gw -Antall 20 -TimeoutMs 1000
        Add-RaaUtdata -Nr 5 -Tittel ('ping gateway ' + $gw + ' (20 pakker)') -Tekst ('$ ' + $pg.Kommando + "`n" + $pg.Utdata + $pg.Feil)
        Add-PingResultat -Nr 5 -Etikett ('mot gateway ' + $gw) -Ping $pg -RttPass 10 -RttWarn 30 -MedJitter -MedTap
        if ($pg.Kjort -and $pg.Mottatt -gt 0 -and $script:ErWifi -and $pg.Maks -gt 100) {
            Add-Resultat -Nr 5 -Sjekk 'Enkeltpakker med høy RTT mot gateway' -Status INFO -Verdi ('maks {0} ms' -f (Format-Tall $pg.Maks 0)) -Detaljer 'Spikes på Wi-Fi: strømsparing på klient, kanalskifte (ACSP/DFS) eller retransmisjoner.'
        }

        # PMTU
        Add-PmtuResultat -Maal $gw -Etikett ('gateway ' + $gw)

        # TCP 443/22 mot gateway (INFO — typisk admin-grensesnitt)
        foreach ($port in @(443, 22)) {
            $t = Test-TcpTilkobling -Vert $gw -Port $port -TimeoutMs 2000
            if ($t.Ok) { Add-Resultat -Nr 5 -Sjekk ('TCP ' + $port + ' mot gateway') -Status INFO -Verdi ('åpen ({0} ms)' -f (Format-Tall $t.ConnectMs 0)) -Detaljer 'Åpen adminport fra klient-VLAN — vurder å begrense til admin-nett.' }
            else { Add-Resultat -Nr 5 -Sjekk ('TCP ' + $port + ' mot gateway') -Status INFO -Verdi ('lukket/filtrert (' + $t.Feil + ')') }
        }
    }
    Add-PmtuResultat -Maal '1.1.1.1' -Etikett '1.1.1.1'

    # Traceroute
    $maal = @('1.1.1.1', 'nrk.no')
    if ($Hurtig) { $maal = @('1.1.1.1'); Add-Resultat -Nr 5 -Sjekk 'Traceroute mot nrk.no' -Status SKIP -Verdi 'hoppet over i hurtigmodus' }
    $forste = $true
    foreach ($m in $maal) {
        $tr = Invoke-Traceroute -Maal $m -MaksHopp 15 -TimeoutMs 1500
        Add-RaaUtdata -Nr 5 -Tittel ('traceroute mot ' + $m) -Tekst ('$ ' + $tr.Kommando + "`n" + $tr.Utdata + $tr.Feil)
        if (-not $tr.Kjort) {
            Add-Resultat -Nr 5 -Sjekk ('Traceroute mot ' + $m) -Status SKIP -Verdi ('ikke tilgjengelig: ' + $tr.Feil) -Detaljer 'Installasjon: tracert er innebygd i Windows; Linux: sudo apt install traceroute'
            continue
        }
        $hopp = @($tr.Hopp)
        if ($hopp.Count -eq 0) {
            Add-Resultat -Nr 5 -Sjekk ('Traceroute mot ' + $m) -Status WARN -Verdi 'ingen hopp tolket (se rå utdata)'
            continue
        }
        $sisteSvar = @($hopp | Where-Object { $null -ne $_.Snitt })
        $naadd = $false
        if ($sisteSvar.Count -gt 0 -and (Test-Ipv4Adresse $m) -and $sisteSvar[-1].Adresse -eq $m) { $naadd = $true }
        Add-Resultat -Nr 5 -Sjekk ('Traceroute mot ' + $m) -Status INFO -Verdi ('{0} hopp registrert, {1} svarte; siste svar fra {2} ({3} ms)' -f $hopp.Count, $sisteSvar.Count, $(if ($sisteSvar.Count -gt 0) { $sisteSvar[-1].Adresse } else { '-' }), $(if ($sisteSvar.Count -gt 0) { Format-Tall $sisteSvar[-1].Snitt 0 } else { '-' }))
        if ($forste) {
            $h1 = $hopp | Where-Object { $_.Nr -eq 1 } | Select-Object -First 1
            $h2 = $hopp | Where-Object { $_.Nr -eq 2 } | Select-Object -First 1
            if ($null -ne $h1 -and $null -ne $h1.Snitt) { Add-Resultat -Nr 5 -Sjekk 'Hopp 1 (brannmur/gateway, LAN-side)' -Status INFO -Verdi ('{0}: {1} ms' -f $h1.Adresse, (Format-Tall $h1.Snitt 1)) }
            elseif ($null -ne $h1) { Add-Resultat -Nr 5 -Sjekk 'Hopp 1 (brannmur/gateway, LAN-side)' -Status INFO -Verdi 'svarer ikke på traceroute (ICMP TTL-exceeded filtrert)' }
            if ($null -ne $h2 -and $null -ne $h2.Snitt) {
                $st = 'FAIL'
                if ($h2.Snitt -lt 10) { $st = 'PASS' } elseif ($h2.Snitt -lt 25) { $st = 'WARN' }
                Add-Resultat -Nr 5 -Sjekk 'Hopp 2 (første hopp utenfor brannmuren — fiber/ISP-side)' -Status $st -Verdi ('{0}: {1} ms' -f $h2.Adresse, (Format-Tall $h2.Snitt 1)) -Terskel 'PASS < 10 ms, WARN < 25 ms, FAIL ≥ 25 ms'
                if (Test-Ipv4IOmraade $h2.Adresse '100.64.0.0/10') { $script:CgnatHopp = $h2.Adresse }
                elseif ((Test-Ipv4IOmraade $h2.Adresse '10.0.0.0/8') -or (Test-Ipv4IOmraade $h2.Adresse '192.168.0.0/16') -or (Test-Ipv4IOmraade $h2.Adresse '172.16.0.0/12')) {
                    Add-Resultat -Nr 5 -Sjekk 'Hopp 2 er privat adresse' -Status INFO -Verdi $h2.Adresse -Detaljer 'Privat adresse etter brannmuren: ISP-ruter/ONT i ruter-modus eller ekstra NAT-lag (dobbel NAT).'
                }
            } elseif ($null -ne $h2) {
                Add-Resultat -Nr 5 -Sjekk 'Hopp 2 (første hopp utenfor brannmuren — fiber/ISP-side)' -Status WARN -Verdi 'svarer ikke (* * *)' -Terskel 'PASS < 10 ms, WARN < 25 ms, FAIL ≥ 25 ms' -Detaljer 'ISP-siden svarer ikke på ICMP TTL-exceeded — kan være normalt, men gjør feilsøking mot fiber vanskeligere.'
            }
            foreach ($h in $hopp) { if ($h.Adresse -and (Test-Ipv4IOmraade $h.Adresse '100.64.0.0/10')) { $script:CgnatHopp = $h.Adresse } }
        }
        $forste = $false
        $tab = $hopp | ForEach-Object { [pscustomobject]@{ Hopp = $_.Nr; Adresse = $_.Adresse; Tider = (($_.Tider | ForEach-Object { if ($null -eq $_) { '*' } else { Format-Tall $_ 0 } }) -join ' / '); SnittMs = $(if ($null -ne $_.Snitt) { Format-Tall $_.Snitt 1 } else { '-' }) } }
        Add-RaaUtdata -Nr 5 -Tittel ('Tolkede hopp mot ' + $m) -Tekst (ConvertTo-Tekst $tab)
    }
}

# ------------------------------------------------------------------------------------
# Seksjon 6 — Fiber og WAN
# ------------------------------------------------------------------------------------
function Invoke-Seksjon6 {
    Add-Resultat -Nr 6 -Sjekk 'Fiber/ONT og ISP' -Status INFO -Verdi 'fyll inn: ISP ____________, ONT/mediakonverter ____________, avtalt hastighet ____ / ____ Mbit/s' -Detaljer 'Fiber-uplinken terminerer i brannmuren i trafokiosken.'
    # Offentlig IP
    $ip = ''
    $colo = ''
    $kilde = ''
    $tr = Invoke-HttpEnkel -Url 'https://1.1.1.1/cdn-cgi/trace' -TimeoutSek 6
    if ($tr.Ok -and $tr.Innhold) {
        Add-RaaUtdata -Nr 6 -Tittel 'https://1.1.1.1/cdn-cgi/trace' -Tekst $tr.Innhold
        $m = [regex]::Match($tr.Innhold, '(?m)^ip=(\S+)')
        if ($m.Success) { $ip = $m.Groups[1].Value; $kilde = '1.1.1.1/cdn-cgi/trace' }
        $c = [regex]::Match($tr.Innhold, '(?m)^colo=(\S+)')
        if ($c.Success) { $colo = $c.Groups[1].Value }
    }
    if (-not $ip) {
        $r2 = Invoke-HttpEnkel -Url 'https://api.ipify.org' -TimeoutSek 8
        if ($r2.Ok -and $r2.Innhold) { $ip = $r2.Innhold.Trim(); $kilde = 'api.ipify.org' }
    }
    $script:OffentligIp = $ip
    if ($ip) {
        $v = ('{0} (kilde {1})' -f $ip, $kilde)
        if ($colo) { $v += (', Cloudflare-node {0}' -f $colo) }
        Add-Resultat -Nr 6 -Sjekk 'Offentlig IP' -Status INFO -Verdi $v
        if ($colo -and $colo -notmatch '^(OSL|ARN|CPH|HEL|GOT|AMS)$') { Add-Resultat -Nr 6 -Sjekk 'Cloudflare-node' -Status INFO -Verdi ('{0} — forventet OSL (Oslo) for norsk fiber; annet kan bety avvikende ISP-ruting' -f $colo) }
    } else {
        Add-Resultat -Nr 6 -Sjekk 'Offentlig IP' -Status FAIL -Verdi ('kunne ikke hentes ({0}; {1})' -f $tr.Feil, 'api.ipify.org feilet') -Detaljer 'Ingen HTTPS ut mot internett, eller portal/proxy stopper trafikken.'
    }
    # CGNAT
    if ($ip -and (Test-Ipv4IOmraade $ip '100.64.0.0/10')) {
        Add-Resultat -Nr 6 -Sjekk 'CGNAT' -Status WARN -Verdi ('offentlig IP {0} er i 100.64.0.0/10' -f $ip) -Detaljer 'Carrier-grade NAT: ingen innkommende tilkoblinger/port-forward; kan påvirke VPN og fjerntilgang.'
    } elseif ($script:CgnatHopp) {
        Add-Resultat -Nr 6 -Sjekk 'CGNAT' -Status WARN -Verdi ('hopp i 100.64.0.0/10 sett i traceroute ({0})' -f $script:CgnatHopp) -Detaljer 'Tyder på CGNAT hos ISP.'
    } elseif ($ip) {
        $privat = (Test-Ipv4IOmraade $ip '10.0.0.0/8') -or (Test-Ipv4IOmraade $ip '192.168.0.0/16') -or (Test-Ipv4IOmraade $ip '172.16.0.0/12')
        if ($privat) { Add-Resultat -Nr 6 -Sjekk 'CGNAT' -Status INFO -Verdi ('«offentlig» IP {0} er privat — proxy/tunnel i veien' -f $ip) }
        else { Add-Resultat -Nr 6 -Sjekk 'CGNAT' -Status PASS -Verdi 'nei — ekte offentlig IP' -Terskel 'ikke 100.64.0.0/10' }
    }
    # ISP/ASN (best effort)
    if ($ip) {
        $ii = Invoke-HttpEnkel -Url ('https://ipinfo.io/{0}/json' -f $ip) -TimeoutSek 8
        if ($ii.Ok -and $ii.Innhold) {
            Add-RaaUtdata -Nr 6 -Tittel ('ipinfo.io/' + $ip + '/json') -Tekst $ii.Innhold
            try {
                $j = $ii.Innhold | ConvertFrom-Json
                Add-Resultat -Nr 6 -Sjekk 'ISP/ASN' -Status INFO -Verdi ('{0}; {1}, {2}, {3}; vertsnavn {4}' -f (Get-Egenskap $j 'org' '?'), (Get-Egenskap $j 'city' '?'), (Get-Egenskap $j 'region' '?'), (Get-Egenskap $j 'country' '?'), (Get-Egenskap $j 'hostname' '-'))
            } catch { Add-Resultat -Nr 6 -Sjekk 'ISP/ASN' -Status INFO -Verdi 'svar fra ipinfo.io kunne ikke tolkes (se rå utdata)' }
        } else {
            Add-Resultat -Nr 6 -Sjekk 'ISP/ASN' -Status INFO -Verdi ('ipinfo.io utilgjengelig ({0})' -f $ii.Feil)
        }
    }
    # Internett-RTT
    $antallInternett = 10
    if ($Hurtig) { $antallInternett = 6 }
    foreach ($m in @('1.1.1.1', '8.8.8.8')) {
        $pg = Invoke-Ping -Maal $m -Antall $antallInternett -TimeoutMs 1500
        Add-RaaUtdata -Nr 6 -Tittel ('ping ' + $m + ' (' + $antallInternett + ' pakker)') -Tekst ('$ ' + $pg.Kommando + "`n" + $pg.Utdata + $pg.Feil)
        Add-PingResultat -Nr 6 -Etikett ('mot ' + $m) -Ping $pg -RttPass 25 -RttWarn 60 -MedTap
    }
    $pg9 = Invoke-Ping -Maal '9.9.9.9' -Antall $antallInternett -TimeoutMs 1500
    Add-RaaUtdata -Nr 6 -Tittel ('ping 9.9.9.9 (' + $antallInternett + ' pakker)') -Tekst ('$ ' + $pg9.Kommando + "`n" + $pg9.Utdata + $pg9.Feil)
    if ($pg9.Kjort -and $pg9.Mottatt -gt 0) { Add-Resultat -Nr 6 -Sjekk 'RTT mot 9.9.9.9' -Status INFO -Verdi ('snitt {0} ms, tap {1} %' -f (Format-Tall $pg9.Snitt 1), (Format-Tall $pg9.TapProsent 0)) }
    elseif ($pg9.Kjort) { Add-Resultat -Nr 6 -Sjekk 'RTT mot 9.9.9.9' -Status INFO -Verdi 'ingen svar' }
    else { Add-Resultat -Nr 6 -Sjekk 'RTT mot 9.9.9.9' -Status SKIP -Verdi 'ping ikke tilgjengelig' }
    # Norske mål
    $antallNorsk = 4
    if ($Hurtig) { $antallNorsk = 3 }
    foreach ($m in @('nrk.no', 'vg.no', 'telenor.no')) {
        $pg = Invoke-Ping -Maal $m -Antall $antallNorsk -TimeoutMs 1500
        Add-RaaUtdata -Nr 6 -Tittel ('ping ' + $m + ' (' + $antallNorsk + ' pakker)') -Tekst ('$ ' + $pg.Kommando + "`n" + $pg.Utdata + $pg.Feil)
        if (-not $pg.Kjort) { Add-Resultat -Nr 6 -Sjekk ('RTT mot ' + $m) -Status SKIP -Verdi 'ping ikke tilgjengelig' }
        elseif ($pg.Mottatt -gt 0) { Add-Resultat -Nr 6 -Sjekk ('RTT mot ' + $m) -Status INFO -Verdi ('snitt {0} ms, tap {1} %' -f (Format-Tall $pg.Snitt 1), (Format-Tall $pg.TapProsent 0)) }
        else { Add-Resultat -Nr 6 -Sjekk ('RTT mot ' + $m) -Status INFO -Verdi 'ingen ICMP-svar (mange norske nettsteder blokkerer ping)' }
    }
    # IPv6
    if ($script:Ipv6Adresser.Count -gt 0) { Add-Resultat -Nr 6 -Sjekk 'IPv6 på WAN' -Status INFO -Verdi ('klienten har globale IPv6-adresser: ' + ($script:Ipv6Adresser -join '; ')) }
    else { Add-Resultat -Nr 6 -Sjekk 'IPv6 på WAN' -Status INFO -Verdi 'ingen global IPv6 på klienten (kun IPv4 — vanlig og uproblematisk)' }

    # XIQ-forutsetninger (det AP-ene trenger mot skyen)
    foreach ($h in @('redirector.aerohive.com', 'extremecloudiq.com')) {
        $d = Resolve-Navn -Navn $h -TimeoutMs 4000
        $t = Test-TcpTilkobling -Vert $h -Port 443 -TimeoutMs 4000
        $dnsTekst = 'DNS feil: ' + $d.Feil
        if ($d.Ok -and $d.Adresser.Count -gt 0) { $dnsTekst = 'DNS ok (' + ($d.Adresser -join ' ') + ')' }
        $tcpTekst = 'TCP 443 feil: ' + $t.Feil
        if ($t.Ok) { $tcpTekst = ('TCP 443 ok ({0} ms)' -f (Format-Tall $t.ConnectMs 0)) }
        $st = 'INFO'
        if (-not ($d.Ok -and $d.Adresser.Count -gt 0) -or -not $t.Ok) { $st = 'WARN' }
        Add-Resultat -Nr 6 -Sjekk ('XIQ-forutsetning: ' + $h) -Status $st -Verdi ($dnsTekst + '; ' + $tcpTekst) -Terskel 'DNS + TCP 443 må virke fra AP-VLAN' -Detaljer 'AP-ene trenger DNS, TCP 443 og UDP 12222 (CAPWAP) ut mot ExtremeCloudIQ. «CAPWAP connection was lost» = brudd her. Testen her går fra klient-VLAN, ikke AP-VLAN.'
    }
    Add-Resultat -Nr 6 -Sjekk 'XIQ-forutsetning: UDP 12222 (CAPWAP)' -Status INFO -Verdi 'ikke testbart fra klient (ingen tjeneste svarer på UDP 12222). Sjekk at brannmuren tillater UDP 12222 utgående fra AP-VLAN, og se CAPWAP-status i XIQ (Manage > Devices).'
}

# ------------------------------------------------------------------------------------
# Seksjon 7 — TCP-ytelse
# ------------------------------------------------------------------------------------
function Get-TcpTellere {
    # Leser sendte og retransmitterte TCP-segmenter (netstat -s -p tcp på Windows, /proc/net/snmp på Linux).
    $res = [pscustomobject]@{ Ok = $false; Sendt = [long]-1; Retrans = [long]-1; Raa = ''; Kilde = ''; Feil = '' }
    if ($script:PaaWindows) {
        if (-not (Test-Kommando 'netstat')) { $res.Feil = 'netstat mangler'; return $res }
        $ut = Invoke-Ekstern -Exe 'netstat' -Argumenter @('-s', '-p', 'tcp') -TimeoutSek 30
        $res.Raa = $ut.Utdata + $ut.Feil
        $res.Kilde = 'netstat -s -p tcp'
        if (-not $ut.Kjort) { $res.Feil = $ut.Feil; return $res }
        foreach ($l in ($ut.Utdata -split "`r?`n")) {
            $nm = [regex]::Match($l, '=\s*(\d+)\s*$')
            if (-not $nm.Success) { continue }
            $tall = [long]$nm.Groups[1].Value
            if ([regex]::IsMatch($l, '(?i)retransmit|p.\s*nytt|nytt\b')) {
                if ($res.Retrans -lt 0 -and [regex]::IsMatch($l, '(?i)segment')) { $res.Retrans = $tall }
            } elseif ([regex]::IsMatch($l, '(?i)segments?\s+sent|segmenter\s+sendt')) {
                if ($res.Sendt -lt 0) { $res.Sendt = $tall }
            }
        }
        $res.Ok = ($res.Sendt -ge 0 -and $res.Retrans -ge 0)
        if (-not $res.Ok) { $res.Feil = 'fant ikke tellerne i netstat-utdata (uventet språk/format)' }
        return $res
    }
    if (Test-Path -LiteralPath '/proc/net/snmp') {
        try {
            $linjer = @(Get-Content -LiteralPath '/proc/net/snmp' -ErrorAction Stop | Where-Object { $_ -match '^Tcp:' })
            $res.Raa = ($linjer -join "`n")
            $res.Kilde = '/proc/net/snmp'
            if ($linjer.Count -ge 2) {
                $hode = ($linjer[0] -split '\s+')
                $verdi = ($linjer[1] -split '\s+')
                for ($i = 0; $i -lt $hode.Count -and $i -lt $verdi.Count; $i++) {
                    if ($hode[$i] -eq 'OutSegs') { $res.Sendt = [long]$verdi[$i] }
                    if ($hode[$i] -eq 'RetransSegs') { $res.Retrans = [long]$verdi[$i] }
                }
            }
            $res.Ok = ($res.Sendt -ge 0 -and $res.Retrans -ge 0)
        } catch { $res.Feil = Get-Feilmelding $_ }
        return $res
    }
    $res.Feil = 'ingen kilde for TCP-tellere på denne plattformen'
    return $res
}

function Invoke-Seksjon7 {
    if (Test-Kommando 'Get-NetTCPSetting') {
        try {
            $ts = Get-NetTCPSetting -SettingName Internet -ErrorAction Stop
            Add-RaaUtdata -Nr 7 -Tittel 'Get-NetTCPSetting -SettingName Internet' -Tekst (($ts | Format-List | Out-String -Width 200).TrimEnd())
            Add-Resultat -Nr 7 -Sjekk 'TCP-innstillinger (Internet-profil)' -Status INFO -Verdi ('CongestionProvider={0}, AutoTuningLevelLocal={1}, EcnCapability={2}, InitialRto={3} ms, Timestamps={4}, MinRto={5} ms' -f (Get-Egenskap $ts 'CongestionProvider' '?'), (Get-Egenskap $ts 'AutoTuningLevelLocal' '?'), (Get-Egenskap $ts 'EcnCapability' '?'), (Get-Egenskap $ts 'InitialRto' '?'), (Get-Egenskap $ts 'Timestamps' '?'), (Get-Egenskap $ts 'MinRto' '?')) -Detaljer 'AutoTuningLevelLocal bør være Normal; CUBIC er standard på Windows 10 1709+/11.'
            if ([string](Get-Egenskap $ts 'AutoTuningLevelLocal' '') -notmatch '^Normal$') { Add-Resultat -Nr 7 -Sjekk 'TCP Receive Window Auto-Tuning' -Status WARN -Verdi ([string](Get-Egenskap $ts 'AutoTuningLevelLocal' '')) -Terskel 'Normal' -Detaljer 'Annet enn Normal begrenser gjennomstrømning ved høy RTT. (Skriptet endrer ikke dette.)' }
        } catch { Add-Resultat -Nr 7 -Sjekk 'TCP-innstillinger (Internet-profil)' -Status SKIP -Verdi (Get-Feilmelding $_) }
    } else {
        Add-Resultat -Nr 7 -Sjekk 'TCP-innstillinger (Get-NetTCPSetting)' -Status SKIP -Verdi 'ikke tilgjengelig (ikke Windows)'
    }
    $tell = Get-TcpTellere
    $script:TcpTellereFoer = $tell
    if ($tell.Raa) { Add-RaaUtdata -Nr 7 -Tittel ('TCP-tellere før hastighetstest (' + $tell.Kilde + ')') -Tekst $tell.Raa }
    if ($tell.Ok) {
        $andel = 0.0
        if ($tell.Sendt -gt 0) { $andel = ($tell.Retrans / [double]$tell.Sendt) * 100.0 }
        Add-Resultat -Nr 7 -Sjekk 'TCP-tellere siden oppstart' -Status INFO -Verdi ('{0} segmenter sendt, {1} retransmittert ({2} %)' -f $tell.Sendt, $tell.Retrans, (Format-Tall $andel 2)) -Detaljer 'Differansen før/etter hastighetstesten (seksjon 8) brukes til retransmisjonsandelen.'
    } else {
        Add-Resultat -Nr 7 -Sjekk 'TCP-tellere siden oppstart' -Status SKIP -Verdi $tell.Feil
    }
    # TCP-connect og TLS-handshake
    $maal = @('www.nrk.no', 'www.vg.no', 'www.google.com', 'www.cloudflare.com', 'www.microsoft.com')
    $connect = New-Object System.Collections.Generic.List[double]
    $tls = New-Object System.Collections.Generic.List[double]
    $tab = New-Object System.Collections.Generic.List[object]
    $feil = 0
    foreach ($h in $maal) {
        $t = Test-TcpTilkobling -Vert $h -Port 443 -TimeoutMs 3000 -Tls
        $rad = [pscustomobject]@{ Vert = $h; ConnectMs = '-'; TlsMs = '-'; Protokoll = $t.Protokoll; Chiffer = $t.Chiffer; Feil = $t.Feil }
        if ($t.Ok) { $connect.Add([double]$t.ConnectMs); $rad.ConnectMs = Format-Tall $t.ConnectMs 0 } else { $feil++ }
        if ($null -ne $t.TlsMs) { $rad.TlsMs = Format-Tall $t.TlsMs 0; if ($t.TlsOk) { $tls.Add([double]$t.TlsMs) } }
        $tab.Add($rad)
    }
    Add-RaaUtdata -Nr 7 -Tittel 'TCP-connect og TLS-handshake (port 443)' -Tekst (ConvertTo-Tekst $tab)
    $med = Get-Median -Verdier $connect.ToArray()
    if ($null -eq $med) {
        Add-Resultat -Nr 7 -Sjekk 'TCP-connect til 443 (5 mål)' -Status FAIL -Verdi 'ingen tilkoblinger lyktes' -Terskel 'PASS median < 40 ms, WARN < 100 ms, FAIL ≥ 100 ms'
    } else {
        $st = 'FAIL'
        if ($med -lt 40) { $st = 'PASS' } elseif ($med -lt 100) { $st = 'WARN' }
        if ($feil -gt 0 -and $st -eq 'PASS') { $st = 'WARN' }
        Add-Resultat -Nr 7 -Sjekk 'TCP-connect til 443 (5 mål)' -Status $st -Verdi ('median {0} ms, {1} av {2} lyktes' -f (Format-Tall $med 0), $connect.Count, $maal.Count) -Terskel 'PASS median < 40 ms, WARN < 100 ms, FAIL ≥ 100 ms'
    }
    $medTls = Get-Median -Verdier $tls.ToArray()
    if ($null -ne $medTls) { Add-Resultat -Nr 7 -Sjekk 'TLS-handshake (5 mål)' -Status INFO -Verdi ('median {0} ms, {1} fullført' -f (Format-Tall $medTls 0), $tls.Count) }
    else { Add-Resultat -Nr 7 -Sjekk 'TLS-handshake (5 mål)' -Status INFO -Verdi 'ingen TLS-handshake fullført (sertifikatfeil/proxy/TLS-inspeksjon?) — se rå tabell' }
    $sertFeil = @($tab | Where-Object { $_.Feil -match 'TLS:' })
    if ($sertFeil.Count -gt 0) { Add-Resultat -Nr 7 -Sjekk 'TLS-sertifikat validert' -Status WARN -Verdi ('feil hos {0} av {1}: {2}' -f $sertFeil.Count, $maal.Count, ($sertFeil[0].Feil)) -Detaljer 'Sertifikatfeil mot kjente nettsteder tyder på TLS-inspeksjon i brannmur/proxy, captive portal eller feil klokke.' }
}

function Measure-TcpRetransDelta {
    # Kalles etter seksjon 8: differanse i tellerne delt på sendte segmenter.
    $foer = $script:TcpTellereFoer
    if ($null -eq $foer -or -not $foer.Ok) {
        Add-Resultat -Nr 7 -Sjekk 'TCP-retransmisjoner under hastighetstest' -Status SKIP -Verdi 'tellere ikke tilgjengelig'
        return
    }
    $etter = Get-TcpTellere
    if (-not $etter.Ok) {
        Add-Resultat -Nr 7 -Sjekk 'TCP-retransmisjoner under hastighetstest' -Status SKIP -Verdi $etter.Feil
        return
    }
    Add-RaaUtdata -Nr 7 -Tittel ('TCP-tellere etter hastighetstest (' + $etter.Kilde + ')') -Tekst $etter.Raa
    $dSendt = $etter.Sendt - $foer.Sendt
    $dRetrans = $etter.Retrans - $foer.Retrans
    if ($dSendt -le 0) {
        Add-Resultat -Nr 7 -Sjekk 'TCP-retransmisjoner under hastighetstest' -Status SKIP -Verdi ('ingen økning i sendte segmenter ({0})' -f $dSendt)
        return
    }
    $andel = ($dRetrans / [double]$dSendt) * 100.0
    $st = 'FAIL'
    if ($andel -lt 0.5) { $st = 'PASS' } elseif ($andel -lt 2) { $st = 'WARN' }
    Add-Resultat -Nr 7 -Sjekk 'TCP-retransmisjoner under hastighetstest' -Status $st -Verdi ('{0} % ({1} retransmittert av {2} sendte segmenter)' -f (Format-Tall $andel 2), $dRetrans, $dSendt) -Terskel 'PASS < 0,5 %, WARN < 2 %, FAIL ≥ 2 %' -Detaljer 'Høy andel retransmisjoner på Wi-Fi = pakketap i luften (interferens/svakt signal) eller bufferbloat.'
}

# ------------------------------------------------------------------------------------
# Seksjon 8 — Hastighet
# ------------------------------------------------------------------------------------
function Measure-HttpOpplasting {
    # POST-er et byte-array med nuller (standard 30 MB) til Cloudflare __up med tidsavbrudd.
    param([string]$Url, [int]$Megabyte = 30, [int]$TimeoutSek = 25)
    $res = [pscustomobject]@{ Ok = $false; Bytes = [long]($Megabyte * 1048576); Sekunder = 0.0; MbitPerSek = $null; Status = 0; Feil = ''; Tidsavbrudd = $false }
    $k = $null
    $svar = $null
    try {
        $k = New-HttpKlient -TimeoutSek $TimeoutSek
        if ($null -eq $k) { $res.Feil = 'HttpClient ikke tilgjengelig'; return $res }
        $bytes = New-Object byte[] ($Megabyte * 1048576)
        $innhold = New-Object System.Net.Http.ByteArrayContent -ArgumentList (, $bytes)
        $innhold.Headers.ContentType = New-Object System.Net.Http.Headers.MediaTypeHeaderValue('application/octet-stream')
        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        $svar = $k.PostAsync($Url, $innhold).Result
        $sw.Stop()
        $res.Sekunder = [math]::Round($sw.Elapsed.TotalSeconds, 2)
        $res.Status = [int]$svar.StatusCode
        if ($svar.IsSuccessStatusCode -and $res.Sekunder -gt 0) {
            $res.Ok = $true
            $res.MbitPerSek = [math]::Round(($res.Bytes * 8.0) / $res.Sekunder / 1000000.0, 1)
        } else {
            $res.Feil = "HTTP $($res.Status)"
        }
    } catch {
        $res.Feil = Get-Feilmelding $_
        if ($res.Feil -match 'TaskCanceled|canceled|cancelled|avbrutt|timeout|tidsavbrudd') { $res.Tidsavbrudd = $true }
        $res.Sekunder = $TimeoutSek
    } finally {
        if ($null -ne $svar) { try { $svar.Dispose() } catch { } }
        if ($null -ne $k) { try { $k.Dispose() } catch { } }
    }
    return $res
}

function Add-HastighetResultat {
    param([string]$Sjekk, $MbitPerSek, [int]$Forventet, [string]$Ekstra = '', [switch]$OvreGrense)
    $terskel = ('PASS ≥ 80 % av {0} Mbit/s (≥ {1}), WARN ≥ 50 % (≥ {2}), FAIL < 50 %' -f $Forventet, (Format-Tall ($Forventet * 0.8) 0), (Format-Tall ($Forventet * 0.5) 0))
    $pct = ([double]$MbitPerSek / [double]$Forventet) * 100.0
    $st = Get-TerskelStatusHoy -Verdi $pct -Pass 80 -Warn 50
    $prefiks = ''
    if ($OvreGrense) { $prefiks = '< ' }
    Add-Resultat -Nr 8 -Sjekk $Sjekk -Status $st -Verdi (('{0}{1} Mbit/s = {2} % av forventet {3}' -f $prefiks, (Format-Tall ([double]$MbitPerSek) 1), (Format-Tall $pct 0), $Forventet) + $Ekstra) -Terskel $terskel
}

function Invoke-Seksjon8 {
    if ($Hurtig) { Add-Resultat -Nr 8 -Sjekk 'Hastighetstest' -Status SKIP -Verdi 'hoppet over (-Hurtig)'; return }
    if (-not $script:HarHttpClient) {
        Add-Resultat -Nr 8 -Sjekk 'Hastighetstest' -Status SKIP -Verdi 'HttpClient (.NET) ikke tilgjengelig' -Detaljer 'Installasjon: .NET Framework 4.5+ (innebygd i Windows 8+) eller PowerShell 7'
        return
    }
    # Nedlasting
    $nedUrl = $script:UrlNed
    $ned = Measure-HttpNedlasting -Url $nedUrl -MaksSek 25 -TimeoutSek 30
    if (-not $ned.Ok -and $ned.Status -ne 200) {
        # 100 MB-URL-en avvist (f.eks. HTTP 403 bak proxy) — prøv 25 MB-varianten
        $ned2 = Measure-HttpNedlasting -Url $script:UrlNedReserve -MaksSek 25 -TimeoutSek 30
        if ($ned2.Ok) {
            Add-Resultat -Nr 8 -Sjekk 'Nedlasting: reserve-URL' -Status INFO -Verdi ('100 MB-URL ga HTTP {0} ({1}); brukte 25 MB-URL i stedet' -f $ned.Status, $ned.Feil)
            $ned = $ned2
            $nedUrl = $script:UrlNedReserve
        }
    }
    Add-RaaUtdata -Nr 8 -Tittel 'Nedlasting (Cloudflare __down, maks 25 s)' -Tekst (('URL: {0}`nHTTP-status: {1}`nTid til første byte: {2} ms`nBytes lest: {3}`nSekunder: {4}`nFullført (EOF): {5}`nMbit/s: {6}`nFeil: {7}' -f $nedUrl, $ned.Status, $ned.Ttfb, $ned.Bytes, $ned.Sekunder, $ned.Ferdig, $ned.MbitPerSek, $ned.Feil) -replace '`n', "`n")
    if ($ned.Ok) {
        Add-HastighetResultat -Sjekk 'Nedlasting (HTTPS, Cloudflare)' -MbitPerSek $ned.MbitPerSek -Forventet $ForventetNed -Ekstra ((' ({0} MB på {1} s)' -f (Format-Tall ($ned.Bytes / 1048576.0) 1), (Format-Tall $ned.Sekunder 1)))
    } else {
        Add-Resultat -Nr 8 -Sjekk 'Nedlasting (HTTPS, Cloudflare)' -Status FAIL -Verdi ('mislyktes: ' + $ned.Feil) -Terskel ('PASS ≥ 80 % av {0} Mbit/s' -f $ForventetNed)
    }
    # Opplasting
    $opp = Measure-HttpOpplasting -Url $script:UrlOpp -Megabyte 30 -TimeoutSek 25
    Add-RaaUtdata -Nr 8 -Tittel 'Opplasting (Cloudflare __up 30 MB, tidsavbrudd 25 s)' -Tekst (('URL: {0}`nHTTP-status: {1}`nBytes: {2}`nSekunder: {3}`nMbit/s: {4}`nTidsavbrudd: {5}`nFeil: {6}' -f $script:UrlOpp, $opp.Status, $opp.Bytes, $opp.Sekunder, $opp.MbitPerSek, $opp.Tidsavbrudd, $opp.Feil) -replace '`n', "`n")
    if ($opp.Ok) {
        Add-HastighetResultat -Sjekk 'Opplasting (HTTPS, Cloudflare)' -MbitPerSek $opp.MbitPerSek -Forventet $ForventetOpp -Ekstra ((' (30 MB på {0} s)' -f (Format-Tall $opp.Sekunder 1)))
    } elseif ($opp.Tidsavbrudd) {
        $grense = [math]::Round(($opp.Bytes * 8.0) / $opp.Sekunder / 1000000.0, 1)
        Add-HastighetResultat -Sjekk 'Opplasting (HTTPS, Cloudflare)' -MbitPerSek $grense -Forventet $ForventetOpp -Ekstra ' (30 MB ble ikke ferdig på 25 s)' -OvreGrense
    } else {
        Add-Resultat -Nr 8 -Sjekk 'Opplasting (HTTPS, Cloudflare)' -Status FAIL -Verdi ('mislyktes: ' + $opp.Feil) -Terskel ('PASS ≥ 80 % av {0} Mbit/s' -f $ForventetOpp)
    }
    # iperf3 mot LAN-server (valgfritt)
    if ($IperfServer) {
        $iperf = ''
        if (Test-Kommando 'iperf3') { $iperf = 'iperf3' }
        else {
            $skriptMappe = $PSScriptRoot
            if (-not $skriptMappe) { $skriptMappe = (Get-Location).Path }
            foreach ($kand in @('iperf3.exe', 'iperf3')) {
                $sti = Join-Path -Path $skriptMappe -ChildPath $kand
                if (Test-Path -LiteralPath $sti) { $iperf = $sti; break }
            }
        }
        if (-not $iperf) {
            Add-Resultat -Nr 8 -Sjekk ('iperf3 mot ' + $IperfServer) -Status SKIP -Verdi 'iperf3 ikke funnet' -Detaljer 'Installasjon: last ned fra https://iperf.fr/iperf-download.php og legg iperf3.exe (+ cygwin1.dll) ved siden av skriptet, eller i PATH. Linux: sudo apt install iperf3'
        } else {
            foreach ($retning in @('ned', 'opp')) {
                $arg = @('-c', $IperfServer, '-J', '-t', '8', '-P', '1')
                $etikett = 'opplasting (klient → server)'
                if ($retning -eq 'ned') { $arg += '-R'; $etikett = 'nedlasting (server → klient, -R)' }
                $ut = Invoke-Ekstern -Exe $iperf -Argumenter $arg -TimeoutSek 45
                Add-RaaUtdata -Nr 8 -Tittel ('iperf3 ' + $etikett) -Tekst ('$ ' + $ut.Kommando + "`n" + $ut.Utdata + $ut.Feil)
                if (-not $ut.Kjort) { Add-Resultat -Nr 8 -Sjekk ('iperf3 ' + $etikett) -Status SKIP -Verdi $ut.Feil; continue }
                $mbit = $null
                $feilTekst = ''
                try {
                    $j = $ut.Utdata | ConvertFrom-Json
                    $feilTekst = [string](Get-Egenskap $j 'error' '')
                    $slutt = Get-Egenskap $j 'end' $null
                    if ($null -ne $slutt) {
                        $nokkel = 'sum_sent'
                        if ($retning -eq 'ned') { $nokkel = 'sum_received' }
                        $sum = Get-Egenskap $slutt $nokkel $null
                        if ($null -eq $sum) { $sum = Get-Egenskap $slutt 'sum_received' $null }
                        if ($null -ne $sum) { $bps = Get-Egenskap $sum 'bits_per_second' $null; if ($null -ne $bps) { $mbit = [math]::Round([double]$bps / 1000000.0, 1) } }
                    }
                } catch { $feilTekst = Get-Feilmelding $_ }
                if ($null -ne $mbit) {
                    $forv = $ForventetOpp
                    if ($retning -eq 'ned') { $forv = $ForventetNed }
                    Add-HastighetResultat -Sjekk ('iperf3 ' + $etikett + ' mot ' + $IperfServer) -MbitPerSek $mbit -Forventet $forv -Ekstra ' (LAN — bør ligge godt over WAN-forventningen; lavere = Wi-Fi/svitsj er flaskehals)'
                } else {
                    Add-Resultat -Nr 8 -Sjekk ('iperf3 ' + $etikett + ' mot ' + $IperfServer) -Status FAIL -Verdi ('ingen måling: ' + $feilTekst) -Detaljer 'Kjører iperf3 -s på serveren? Slipper brannmuren TCP 5201?'
                }
            }
        }
    } else {
        Add-Resultat -Nr 8 -Sjekk 'iperf3 (LAN)' -Status INFO -Verdi 'ingen -IperfServer oppgitt — LAN-hastighet mot svitsj/AP ikke målt' -Detaljer 'Tips: kjør iperf3 -s på en kablet PC i trafokiosken og oppgi -IperfServer <IP> for å skille Wi-Fi fra fiber.'
    }
    $script:Hastighet8Kjort = $true
}

# ------------------------------------------------------------------------------------
# Seksjon 9 — Bufferbloat og jitter under last
# ------------------------------------------------------------------------------------
function Invoke-Seksjon9 {
    if ($Hurtig) { Add-Resultat -Nr 9 -Sjekk 'Bufferbloat' -Status SKIP -Verdi 'hoppet over (-Hurtig)'; return }
    if (-not (Get-PingStotte)) {
        Add-Resultat -Nr 9 -Sjekk 'Bufferbloat' -Status SKIP -Verdi 'ping ikke tilgjengelig' -Detaljer 'Installasjon: ping er innebygd i Windows; Linux: sudo apt install iputils-ping'
        return
    }
    $maal = @()
    if ($script:GatewayIp) { $maal += $script:GatewayIp } else { Add-Resultat -Nr 9 -Sjekk 'Bufferbloat mot gateway' -Status SKIP -Verdi 'ingen gateway kjent' }
    $maal += '1.1.1.1'
    $ro = @{}
    $raa = New-Object System.Text.StringBuilder
    foreach ($m in $maal) {
        $pg = Invoke-Ping -Maal $m -Antall 10 -TimeoutMs 1000
        $ro[$m] = $pg
        [void]$raa.AppendLine('$ ' + $pg.Kommando + ' (i ro)')
        [void]$raa.AppendLine($pg.Utdata + $pg.Feil)
    }
    $temp = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath ('nettsjekk-last-' + [guid]::NewGuid().ToString('N') + '.bin')
    $job = $null
    $last = @{}
    $jobTekst = ''
    try {
        $job = Start-Job -ScriptBlock {
            param($Urler, $Fil, $MaksSek)
            $ProgressPreference = 'SilentlyContinue'
            try { [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12 } catch { }
            $sw = [System.Diagnostics.Stopwatch]::StartNew()
            $n = 0
            $feil = 0
            $i = 0
            # Skriver en linje per nedlasting slik at Receive-Job får med seg fremdriften selv om jobben stoppes.
            while ($sw.Elapsed.TotalSeconds -lt $MaksSek) {
                $url = $Urler[$i % $Urler.Count]
                try {
                    Invoke-WebRequest -Uri $url -OutFile $Fil -UseBasicParsing -TimeoutSec 60 -ErrorAction Stop
                    $n++
                    Write-Output ('lastjobb: nedlasting {0} fullført etter {1} s ({2})' -f $n, [int]$sw.Elapsed.TotalSeconds, $url)
                } catch {
                    $feil++
                    $i++
                    Write-Output ('lastjobb: feil {0} etter {1} s ({2}): {3}' -f $feil, [int]$sw.Elapsed.TotalSeconds, $url, $_.Exception.Message)
                    Start-Sleep -Seconds 1
                }
            }
            Write-Output ('lastjobb: ferdig — {0} nedlastinger, {1} feil, {2} s' -f $n, $feil, [int]$sw.Elapsed.TotalSeconds)
        } -ArgumentList @($script:UrlNed, $script:UrlNedReserve), $temp, 45
        Start-Sleep -Seconds 2
        foreach ($m in $maal) {
            $pg = Invoke-Ping -Maal $m -Antall 15 -TimeoutMs 1000
            $last[$m] = $pg
            [void]$raa.AppendLine('$ ' + $pg.Kommando + ' (under nedlasting)')
            [void]$raa.AppendLine($pg.Utdata + $pg.Feil)
        }
    } finally {
        if ($null -ne $job) {
            try { Stop-Job -Job $job -ErrorAction SilentlyContinue } catch { }
            try { $null = Wait-Job -Job $job -Timeout 10 } catch { }
            try { $jobTekst = [string](Receive-Job -Job $job -ErrorAction SilentlyContinue | Out-String) } catch { }
            try { Remove-Job -Job $job -Force -ErrorAction SilentlyContinue } catch { }
        }
        try { if (Test-Path -LiteralPath $temp) { Remove-Item -LiteralPath $temp -Force -ErrorAction SilentlyContinue } } catch { }
    }
    if ($jobTekst) { [void]$raa.AppendLine($jobTekst.Trim()) }
    Add-RaaUtdata -Nr 9 -Tittel 'ping i ro og under nedlasting' -Tekst $raa.ToString()
    foreach ($m in $maal) {
        $r = $ro[$m]
        $l = $last[$m]
        $etikett = 'mot ' + $m
        if ($m -eq $script:GatewayIp) { $etikett = 'mot gateway ' + $m }
        if (-not $r.Kjort -or -not $l.Kjort) { Add-Resultat -Nr 9 -Sjekk ('Bufferbloat ' + $etikett) -Status SKIP -Verdi 'ping kunne ikke kjøres'; continue }
        if ($r.Mottatt -eq 0 -or $l.Mottatt -eq 0) { Add-Resultat -Nr 9 -Sjekk ('Bufferbloat ' + $etikett) -Status SKIP -Verdi ('ingen ping-svar (i ro: {0}, under last: {1})' -f $r.Mottatt, $l.Mottatt); continue }
        $okning = [double]$l.Median - [double]$r.Median
        $st = 'FAIL'
        if ($okning -lt 30) { $st = 'PASS' } elseif ($okning -lt 100) { $st = 'WARN' }
        Add-Resultat -Nr 9 -Sjekk ('Bufferbloat ' + $etikett) -Status $st -Verdi ('+{0} ms (median i ro {1} ms → under nedlasting {2} ms)' -f (Format-Tall $okning 0), (Format-Tall $r.Median 1), (Format-Tall $l.Median 1)) -Terskel 'PASS < 30 ms, WARN < 100 ms, FAIL ≥ 100 ms' -Detaljer 'Høy økning = for store buffere (bufferbloat) i AP/brannmur/ONT. SQM/fq_codel i brannmuren og airtime fairness på AP hjelper.'
        Add-Resultat -Nr 9 -Sjekk ('Jitter under last ' + $etikett) -Status INFO -Verdi ('{0} ms (i ro {1} ms); tap under last {2} %' -f (Format-Tall $l.Jitter 1), (Format-Tall $r.Jitter 1), (Format-Tall $l.TapProsent 0))
    }
}

# ------------------------------------------------------------------------------------
# Seksjon 10 — Video og strømming
# ------------------------------------------------------------------------------------
function Get-HlsVarianter {
    param([string]$Tekst)
    $linjer = @($Tekst -split "`r?`n")
    $liste = New-Object System.Collections.Generic.List[object]
    for ($i = 0; $i -lt $linjer.Count; $i++) {
        $l = $linjer[$i].Trim()
        if (-not $l.StartsWith('#EXT-X-STREAM-INF')) { continue }
        $bw = 0
        $bm = [regex]::Match($l, '(?<![A-Z-])BANDWIDTH=(\d+)')
        if ($bm.Success) { $bw = [long]$bm.Groups[1].Value }
        $opl = ''
        $rm = [regex]::Match($l, 'RESOLUTION=(\d+x\d+)')
        if ($rm.Success) { $opl = $rm.Groups[1].Value }
        $uri = ''
        for ($j = $i + 1; $j -lt $linjer.Count; $j++) {
            $n = $linjer[$j].Trim()
            if ($n -and -not $n.StartsWith('#')) { $uri = $n; break }
        }
        if ($uri) { $liste.Add([pscustomobject]@{ Bandwidth = $bw; Opplosning = $opl; Uri = $uri }) }
    }
    return @($liste.ToArray())
}

function Invoke-Seksjon10 {
    if ($Hurtig) { Add-Resultat -Nr 10 -Sjekk 'Video (HLS)' -Status SKIP -Verdi 'hoppet over (-Hurtig)'; return }
    if (-not $script:HarHttpClient) { Add-Resultat -Nr 10 -Sjekk 'Video (HLS)' -Status SKIP -Verdi 'HttpClient (.NET) ikke tilgjengelig'; return }
    $brukt = ''
    $master = $null
    foreach ($u in @($script:UrlHls, $script:UrlHlsReserve)) {
        $m = Get-HttpTekst -Url $u -TimeoutSek 15
        if ($m.Ok -and $m.Tekst -match '#EXTM3U') { $master = $m; $brukt = $u; break }
        Add-Resultat -Nr 10 -Sjekk ('HLS-master ' + $u) -Status WARN -Verdi ('utilgjengelig: {0} {1}' -f $m.Status, $m.Feil)
    }
    if ($null -eq $master) {
        Add-Resultat -Nr 10 -Sjekk 'Video (HLS)' -Status FAIL -Verdi 'ingen HLS-teststrøm tilgjengelig (primær og reserve feilet)' -Detaljer 'HTTPS ut mot CDN-er feiler — sjekk brannmur/proxy/DNS.'
    } else {
        Add-RaaUtdata -Nr 10 -Tittel ('HLS-master ' + $brukt) -Tekst $master.Tekst
        $varianter = @(Get-HlsVarianter -Tekst $master.Tekst)
        if ($varianter.Count -eq 0) {
            Add-Resultat -Nr 10 -Sjekk 'HLS-varianter' -Status FAIL -Verdi 'ingen #EXT-X-STREAM-INF funnet i master-spillelisten'
        } else {
            $beste = $varianter | Sort-Object -Property Bandwidth -Descending | Select-Object -First 1
            $baseUri = New-Object System.Uri($brukt)
            $mediaUri = (New-Object System.Uri($baseUri, $beste.Uri)).AbsoluteUri
            Add-Resultat -Nr 10 -Sjekk 'HLS-variant (høyeste bitrate)' -Status INFO -Verdi ('{0} kbit/s, {1}, {2} varianter totalt' -f [math]::Round($beste.Bandwidth / 1000.0), $beste.Opplosning, $varianter.Count) -Detaljer $mediaUri
            $media = Get-HttpTekst -Url $mediaUri -TimeoutSek 15
            if (-not $media.Ok) {
                Add-Resultat -Nr 10 -Sjekk 'HLS-mediespilleliste' -Status FAIL -Verdi ('utilgjengelig: {0} {1}' -f $media.Status, $media.Feil)
            } else {
                Add-RaaUtdata -Nr 10 -Tittel 'HLS-mediespilleliste (første 40 linjer)' -Tekst ((@($media.Tekst -split "`r?`n") | Select-Object -First 40) -join "`n")
                $segmenter = @(@($media.Tekst -split "`r?`n") | ForEach-Object { $_.Trim() } | Where-Object { $_ -and -not $_.StartsWith('#') } | Select-Object -First 7)
                $medBase = New-Object System.Uri($mediaUri)
                $tab = New-Object System.Collections.Generic.List[object]
                $mbits = New-Object System.Collections.Generic.List[double]
                $tider = New-Object System.Collections.Generic.List[double]
                $swTot = [System.Diagnostics.Stopwatch]::StartNew()
                $nr = 0
                foreach ($s in $segmenter) {
                    $nr++
                    if ($swTot.Elapsed.TotalSeconds -gt 75) { Add-Resultat -Nr 10 -Sjekk 'HLS-segmenter' -Status WARN -Verdi ('stoppet etter {0} segmenter (tidsbudsjett 75 s brukt opp)' -f ($nr - 1)); break }
                    $segUri = (New-Object System.Uri($medBase, $s)).AbsoluteUri
                    $r = Measure-HttpNedlasting -Url $segUri -MaksSek 20 -TimeoutSek 20
                    $rad = [pscustomobject]@{ Nr = $nr; Segment = $s; Bytes = $r.Bytes; Sekunder = $r.Sekunder; MbitPerSek = $r.MbitPerSek; TtfbMs = $r.Ttfb; Status = $r.Status; Feil = $r.Feil }
                    $tab.Add($rad)
                    if ($r.Ok -and $r.Ferdig) { $mbits.Add([double]$r.MbitPerSek); $tider.Add([double]$r.Sekunder) }
                }
                Add-RaaUtdata -Nr 10 -Tittel 'HLS-segmenter (høyeste variant)' -Tekst (ConvertTo-Tekst $tab)
                if ($mbits.Count -eq 0) {
                    Add-Resultat -Nr 10 -Sjekk 'HLS segment-gjennomstrømning' -Status FAIL -Verdi 'ingen segmenter lastet ned' -Terskel 'PASS ≥ 25 Mbit/s, WARN ≥ 8 Mbit/s, FAIL < 8 Mbit/s'
                } else {
                    $snitt = Get-Snitt -Verdier $mbits.ToArray()
                    $minst = ($mbits | Measure-Object -Minimum).Minimum
                    $st = Get-TerskelStatusHoy -Verdi $snitt -Pass 25 -Warn 8
                    if ($mbits.Count -lt 6) { Add-Resultat -Nr 10 -Sjekk 'HLS-segmenter' -Status WARN -Verdi ('bare {0} av {1} segmenter fullført (minst 6 ønsket)' -f $mbits.Count, $segmenter.Count) }
                    Add-Resultat -Nr 10 -Sjekk 'HLS segment-gjennomstrømning' -Status $st -Verdi ('snitt {0} Mbit/s, min {1} Mbit/s over {2} segmenter (strømmen krever ca. {3} Mbit/s)' -f (Format-Tall $snitt 1), (Format-Tall $minst 1), $mbits.Count, (Format-Tall ($beste.Bandwidth / 1000000.0) 1)) -Terskel 'PASS ≥ 25 Mbit/s (4K-margin), WARN ≥ 8 Mbit/s (1080p), FAIL < 8 Mbit/s'
                    $medT = Get-Median -Verdier $tider.ToArray()
                    $maksT = ($tider | Measure-Object -Maximum).Maximum
                    if ($null -ne $medT -and $medT -gt 0) {
                        $forhold = $maksT / $medT
                        $stF = 'PASS'
                        if ($forhold -gt 3) { $stF = 'WARN' }
                        Add-Resultat -Nr 10 -Sjekk 'Segment-hentetid maks/median' -Status $stF -Verdi ('{0} (maks {1} s, median {2} s)' -f (Format-Tall $forhold 2), (Format-Tall $maksT 2), (Format-Tall $medT 2)) -Terskel '> 3 → WARN (stalling-risiko)'
                    }
                }
            }
        }
    }
    # Strømmetjenester: TCP/TLS-tider
    $tab2 = New-Object System.Collections.Generic.List[object]
    foreach ($h in @('www.youtube.com', 'www.netflix.com', 'tv.nrk.no', 'www.twitch.tv')) {
        $t = Test-TcpTilkobling -Vert $h -Port 443 -TimeoutMs 3000 -Tls
        $c = '-'
        if ($t.Ok) { $c = Format-Tall $t.ConnectMs 0 }
        $tl = '-'
        if ($null -ne $t.TlsMs) { $tl = Format-Tall $t.TlsMs 0 }
        $tab2.Add([pscustomobject]@{ Vert = $h; ConnectMs = $c; TlsMs = $tl; Protokoll = $t.Protokoll; Feil = $t.Feil })
    }
    Add-RaaUtdata -Nr 10 -Tittel 'Strømmetjenester: TCP-connect og TLS (443)' -Tekst (ConvertTo-Tekst $tab2)
    $ok = @($tab2 | Where-Object { $_.ConnectMs -ne '-' })
    Add-Resultat -Nr 10 -Sjekk 'Strømmetjenester nåbare (TCP 443)' -Status INFO -Verdi (('{0} av {1}: ' -f $ok.Count, $tab2.Count) + (($tab2 | ForEach-Object { '{0} {1}/{2} ms' -f $_.Vert, $_.ConnectMs, $_.TlsMs }) -join '; '))
    Add-Resultat -Nr 10 -Sjekk 'QUIC/HTTP3 (UDP 443)' -Status INFO -Verdi 'ikke testbart uten HTTP/3-klient. YouTube/Google bruker QUIC; blokkert UDP 443 gir fallback til TCP (fungerer, men tregere oppstart).'
}

# ------------------------------------------------------------------------------------
# Seksjon 11 — Roaming
# ------------------------------------------------------------------------------------
function Invoke-Seksjon11 {
    if (-not $script:PaaWindows) {
        Add-Resultat -Nr 11 -Sjekk 'Roaming-øyeblikksbilde' -Status SKIP -Verdi 'krever Windows (netsh wlan)'
        Add-Resultat -Nr 11 -Sjekk 'Roamingtest' -Status INFO -Verdi 'kjør roaming-logg.ps1 på Windows-PC-en mens du går mellom AP-ene'
        return
    }
    if (-not $script:ErWifi -or $null -eq $script:Wlan) {
        Add-Resultat -Nr 11 -Sjekk 'Roaming-øyeblikksbilde' -Status SKIP -Verdi 'ikke tilkoblet via Wi-Fi'
        return
    }
    $w = $script:Wlan
    $ssid = [string](Find-Nokkel $w '^SSID$' '')
    $bssid = ([string](Find-Nokkel $w '^BSSID$' '')).ToLower()
    $kanal = $null
    $km = [regex]::Match([string](Find-Nokkel $w '^(channel|kanal)$' ''), '(\d+)')
    if ($km.Success) { $kanal = [int]$km.Groups[1].Value }
    $pct = $null
    $sm = [regex]::Match([string](Find-Nokkel $w '^signal$' ''), '(\d+)')
    if ($sm.Success) { $pct = [int]$sm.Groups[1].Value }
    $band = Get-BandFraKanal -Kanal $kanal -BandTekst ([string](Find-Nokkel $w '^b.{1,2}nd$' ''))
    Add-Resultat -Nr 11 -Sjekk 'Nåværende AP' -Status INFO -Verdi ('SSID {0}, BSSID {1}, {2} kanal {3}, ca. {4} dBm ({5} %)' -f $ssid, $bssid, $band, $kanal, (ConvertTo-Dbm $pct), $pct)
    if ($script:NaboBssid.Count -eq 0) {
        Add-Resultat -Nr 11 -Sjekk 'Roamingkandidater (samme SSID)' -Status SKIP -Verdi 'BSSID-liste ikke tilgjengelig (se seksjon 1: plasseringstillatelse for netsh wlan show networks)'
    } else {
        $kand = @($script:NaboBssid | Where-Object { $_.SSID -eq $ssid -and $_.BSSID -ne $bssid })
        if ($kand.Count -eq 0) {
            Add-Resultat -Nr 11 -Sjekk 'Roamingkandidater (samme SSID)' -Status INFO -Verdi 'ingen andre AP-er med samme SSID synlige herfra — roaming ikke mulig på dette stedet'
        } else {
            $best = $kand | Sort-Object -Property SignalProsent -Descending | Select-Object -First 1
            $liste = ($kand | Sort-Object -Property SignalProsent -Descending | ForEach-Object { '{0} ({1}, kanal {2}, ca. {3} dBm)' -f $_.BSSID, (Get-BandFraKanal -Kanal $_.Kanal -BandTekst $_.Band), $_.Kanal, (ConvertTo-Dbm $_.SignalProsent) }) -join '; '
            Add-Resultat -Nr 11 -Sjekk 'Roamingkandidater (samme SSID)' -Status INFO -Verdi ('{0}: {1}' -f $kand.Count, $liste)
            if ($null -ne $pct -and $null -ne $best.SignalProsent) {
                $diff = [int]$best.SignalProsent - [int]$pct
                if ($diff -ge 20) {
                    Add-Resultat -Nr 11 -Sjekk 'Klient henger igjen på svakere AP (sticky)' -Status WARN -Verdi ('nabo {0} er ca. {1} dB sterkere enn nåværende AP' -f $best.BSSID, [int]($diff / 2)) -Terskel 'WARN ≥ 10 dB sterkere nabo' -Detaljer 'Øk «Roaming Aggressiveness» på klienten og sjekk 802.11k/v/r på SSID-en i XIQ. Signalverdier er tilnærmet (prosent/2 − 100).'
                } else {
                    Add-Resultat -Nr 11 -Sjekk 'Klient henger igjen på svakere AP (sticky)' -Status PASS -Verdi ('nei — beste nabo er {0} dB {1}' -f [math]::Abs([int]($diff / 2)), $(if ($diff -ge 0) { 'sterkere' } else { 'svakere' })) -Terskel 'WARN ≥ 10 dB sterkere nabo'
                }
            }
            if ($band -match '2,4') {
                $fem = @($kand | Where-Object { (Get-BandFraKanal -Kanal $_.Kanal -BandTekst $_.Band) -notmatch '2,4' })
                if ($fem.Count -gt 0) { Add-Resultat -Nr 11 -Sjekk 'Henger på 2,4 GHz med 5 GHz tilgjengelig' -Status WARN -Verdi ('{0} 5/6 GHz-BSSID-er synlige på samme SSID' -f $fem.Count) -Detaljer 'Sett «Preferred Band» til 5 GHz på klienten og bruk båndstyring i XIQ.' }
            }
        }
    }
    $roam = @($script:AvanserteEgenskaper | Where-Object { $_.Egenskap -match 'Roam' })
    $bandPref = @($script:AvanserteEgenskaper | Where-Object { $_.Egenskap -match 'Band|B.nd' })
    if ($roam.Count -gt 0) {
        $rv = [string]$roam[0].Verdi
        $st = 'INFO'
        if ($rv -match 'Lowest|Medium-?low|Laveste|Lav') { $st = 'WARN' }
        Add-Resultat -Nr 11 -Sjekk 'Roaming-aggressivitet (driver)' -Status $st -Verdi ('{0} = {1}' -f $roam[0].Egenskap, $rv) -Detaljer 'Lav aggressivitet gjør at klienten holder på et svakt AP for lenge. Medium/High anbefales i tett AP-dekning.'
    } else {
        Add-Resultat -Nr 11 -Sjekk 'Roaming-aggressivitet (driver)' -Status INFO -Verdi 'ikke eksponert av driveren'
    }
    if ($bandPref.Count -gt 0) { Add-Resultat -Nr 11 -Sjekk 'Foretrukket bånd (driver)' -Status INFO -Verdi ('{0} = {1}' -f $bandPref[0].Egenskap, $bandPref[0].Verdi) }
    Add-Resultat -Nr 11 -Sjekk '802.11k/v/r' -Status INFO -Verdi 'klientstøtte kan ikke leses via netsh. XIQ-radioprofilen har BSS transition (11v) aktivert — sjekk også 11k (neighbor report) og 11r (fast transition) på SSID-en.'
    Add-Resultat -Nr 11 -Sjekk 'Roamingtest' -Status INFO -Verdi 'dette er et øyeblikksbilde. Kjør roaming-logg.ps1 mens du går mellom AP-ene for å logge BSSID/RSSI/kanal-bytter og tap under roaming.'
}

# ------------------------------------------------------------------------------------
# Seksjon 12 — Hygiene
# ------------------------------------------------------------------------------------
function Invoke-Seksjon12 {
    # Klokke / NTP
    $synk = ''
    if ($script:PaaWindows -and (Test-Kommando 'w32tm')) {
        $ut = Invoke-Ekstern -Exe 'w32tm' -Argumenter @('/query', '/status') -TimeoutSek 15
        Add-RaaUtdata -Nr 12 -Tittel 'w32tm /query /status' -Tekst ($ut.Utdata + $ut.Feil)
        if ($ut.Kjort -and $ut.ExitCode -eq 0) {
            $kilde = ''
            $km = [regex]::Match($ut.Utdata, '(?im)^\s*(source|kilde)\s*:\s*(.+)$')
            if ($km.Success) { $kilde = $km.Groups[2].Value.Trim() }
            $lm = [regex]::Match($ut.Utdata, '(?i)(leap.?indi\w*|sprang\w*indikator)\s*:\s*(\d)')
            if ($lm.Success -and $lm.Groups[2].Value -eq '3') { $synk = 'nei' } elseif ($lm.Success) { $synk = 'ja' }
            Add-Resultat -Nr 12 -Sjekk 'Tidstjeneste (w32tm)' -Status INFO -Verdi ('kilde: {0}; synkronisert: {1}' -f $kilde, $(if ($synk) { $synk } else { 'ukjent' }))
        } else {
            Add-Resultat -Nr 12 -Sjekk 'Tidstjeneste (w32tm)' -Status INFO -Verdi ('w32tm ga ingen status (tjenesten stoppet?) — ' + ($ut.Utdata + $ut.Feil).Trim())
        }
    } elseif (Test-Path -LiteralPath '/run/systemd/timesync/synchronized') {
        $synk = 'ja'
        Add-Resultat -Nr 12 -Sjekk 'Tidstjeneste' -Status INFO -Verdi 'systemd-timesyncd rapporterer synkronisert'
    }
    $dato = $null
    $foer = [DateTime]::UtcNow
    $etter = $foer
    foreach ($u in @('https://1.1.1.1/', 'https://www.cloudflare.com/', 'http://connectivitycheck.gstatic.com/generate_204')) {
        $foer = [DateTime]::UtcNow
        $r = Invoke-HttpEnkel -Url $u -TimeoutSek 6
        $etter = [DateTime]::UtcNow
        if ($r.Hoder.ContainsKey('Date') -and $r.Hoder['Date']) {
            try { $dato = [DateTime]::SpecifyKind([DateTime]::ParseExact([string]$r.Hoder['Date'], 'r', $script:Inv), [DateTimeKind]::Utc); break } catch { $dato = $null }
        }
    }
    if ($null -ne $dato) {
        $midt = $foer.AddTicks([long](($etter - $foer).Ticks / 2))
        $avvik = [math]::Abs(($midt - $dato).TotalSeconds)
        $st = 'FAIL'
        if ($avvik -lt 1) { $st = 'PASS' } elseif ($avvik -lt 5) { $st = 'WARN' }
        if ($synk -eq 'nei') { $st = 'FAIL' }
        Add-Resultat -Nr 12 -Sjekk 'Klokkeavvik mot HTTP Date' -Status $st -Verdi ('{0} s (lokal UTC {1}, server {2}){3}' -f (Format-Tall $avvik 1), $midt.ToString('HH:mm:ss'), $dato.ToString('HH:mm:ss'), $(if ($synk -eq 'nei') { '; tidstjenesten er IKKE synkronisert' } else { '' })) -Terskel 'PASS < 1 s, WARN < 5 s, FAIL ellers / ikke synkronisert' -Detaljer 'HTTP Date har 1 s oppløsning. Feil klokke gir TLS-feil og problemer med XIQ/sertifikater.'
    } else {
        Add-Resultat -Nr 12 -Sjekk 'Klokkeavvik mot HTTP Date' -Status SKIP -Verdi 'fikk ingen Date-header fra testmålene'
    }

    # Captive portal
    $g = Invoke-HttpEnkel -Url 'http://connectivitycheck.gstatic.com/generate_204' -TimeoutSek 8 -MaksRedirect 0
    if ($g.Status -eq 204) { Add-Resultat -Nr 12 -Sjekk 'Captive portal (gstatic generate_204)' -Status PASS -Verdi ('HTTP 204 ({0} ms)' -f (Format-Tall $g.Ms 0)) -Terskel 'HTTP 204' }
    else { Add-Resultat -Nr 12 -Sjekk 'Captive portal (gstatic generate_204)' -Status FAIL -Verdi ('HTTP {0} {1} {2}' -f $g.Status, $g.Location, $g.Feil).Trim() -Terskel 'HTTP 204' -Detaljer 'Annet enn 204 = captive portal, proxy eller DNS-kapring i veien.' }
    $a = Invoke-HttpEnkel -Url 'http://captive.apple.com/hotspot-detect.html' -TimeoutSek 8 -MaksRedirect 0
    if ($a.Status -eq 200 -and $a.Innhold -match 'Success') { Add-Resultat -Nr 12 -Sjekk 'Captive portal (captive.apple.com)' -Status PASS -Verdi ('HTTP 200 med «Success» ({0} ms)' -f (Format-Tall $a.Ms 0)) -Terskel 'HTTP 200 + Success' }
    else { Add-Resultat -Nr 12 -Sjekk 'Captive portal (captive.apple.com)' -Status FAIL -Verdi ('HTTP {0} {1} {2}' -f $a.Status, $a.Location, $a.Feil).Trim() -Terskel 'HTTP 200 + Success' -Detaljer 'Annet enn 200/Success = captive portal, proxy eller DNS-kapring i veien.' }

    # Proxy
    if ($script:PaaWindows -and (Test-Kommando 'netsh')) {
        $pw = Invoke-Ekstern -Exe 'netsh' -Argumenter @('winhttp', 'show', 'proxy') -TimeoutSek 15
        Add-RaaUtdata -Nr 12 -Tittel 'netsh winhttp show proxy' -Tekst ($pw.Utdata + $pw.Feil)
        if ($pw.Kjort) {
            if ($pw.Utdata -match '(?i)direct access|direkte tilgang|ingen proxy|no proxy') { Add-Resultat -Nr 12 -Sjekk 'WinHTTP-proxy' -Status PASS -Verdi 'direkte tilgang (ingen proxy)' -Terskel 'ingen proxy' }
            else { Add-Resultat -Nr 12 -Sjekk 'WinHTTP-proxy' -Status WARN -Verdi (($pw.Utdata -replace '\s+', ' ').Trim()) -Terskel 'ingen proxy' -Detaljer 'En proxy påvirker alle HTTP-målingene i denne rapporten.' }
        }
    }
    $proxyUri = $null
    try { $proxyUri = [System.Net.WebRequest]::DefaultWebProxy.GetProxy((New-Object System.Uri('https://www.nrk.no/'))) } catch { $proxyUri = $null }
    $envProxy = ''
    foreach ($n in @('HTTPS_PROXY', 'https_proxy', 'HTTP_PROXY', 'http_proxy')) {
        $v = [Environment]::GetEnvironmentVariable($n)
        if ($v) { $envProxy = ('{0}={1}' -f $n, $v); break }
    }
    if ($null -ne $proxyUri -and [string]$proxyUri.Host -and $proxyUri.Host -ne 'www.nrk.no') {
        Add-Resultat -Nr 12 -Sjekk 'Systemproxy (.NET DefaultWebProxy)' -Status WARN -Verdi ('proxy for https://www.nrk.no: {0}' -f $proxyUri.AbsoluteUri) -Terskel 'ingen proxy' -Detaljer 'Målingene går via proxy — ikke representativt for direkte fiber/Wi-Fi-ytelse.'
    } elseif ($envProxy) {
        Add-Resultat -Nr 12 -Sjekk 'Systemproxy (miljøvariabel)' -Status WARN -Verdi $envProxy -Terskel 'ingen proxy' -Detaljer 'Målingene går via proxy — ikke representativt for direkte fiber/Wi-Fi-ytelse.'
    } else {
        Add-Resultat -Nr 12 -Sjekk 'Systemproxy' -Status PASS -Verdi 'ingen proxy for https://www.nrk.no' -Terskel 'ingen proxy'
    }

    # VPN
    $vpn = @()
    if (Test-Kommando 'Get-VpnConnection') {
        try {
            $vc = @(Get-VpnConnection -ErrorAction Stop | Where-Object { [string](Get-Egenskap $_ 'ConnectionStatus' '') -eq 'Connected' })
            foreach ($v in $vc) { $vpn += ('Windows VPN «{0}» ({1})' -f (Get-Egenskap $v 'Name' ''), (Get-Egenskap $v 'ServerAddress' '')) }
        } catch { }
    }
    if (Test-Kommando 'Get-NetAdapter') {
        try {
            $va = @(Get-NetAdapter -ErrorAction Stop | Where-Object { [string](Get-Egenskap $_ 'Status' '') -eq 'Up' -and [string](Get-Egenskap $_ 'InterfaceDescription' '') -match 'WireGuard|OpenVPN|TAP-|AnyConnect|Fortinet|GlobalProtect|Tailscale|ZeroTier|Juniper|Pulse|Check Point|NordLynx|Proton' })
            foreach ($v in $va) { $vpn += ('adapter «{0}» ({1})' -f (Get-Egenskap $v 'Name' ''), (Get-Egenskap $v 'InterfaceDescription' '')) }
        } catch { }
    } else {
        foreach ($n in @(Get-NetworkInterfaceInfo)) {
            if ($n.Status -eq 'Up' -and ($n.Navn -match '^(tun|tap|wg|utun|ppp|zt|tailscale|nordlynx|proton)' -or $n.Type -eq 'Tunnel' -or $n.Type -eq 'Ppp')) { $vpn += ('grensesnitt «{0}» ({1})' -f $n.Navn, $n.Type) }
        }
    }
    if ($vpn.Count -gt 0) { Add-Resultat -Nr 12 -Sjekk 'VPN aktiv' -Status WARN -Verdi ($vpn -join '; ') -Terskel 'ingen VPN under måling' -Detaljer 'Målingene går gjennom VPN og sier lite om fiber/Wi-Fi. Koble fra VPN og kjør på nytt.' }
    else { Add-Resultat -Nr 12 -Sjekk 'VPN aktiv' -Status PASS -Verdi 'nei' -Terskel 'ingen VPN under måling' }

    # Windows-brannmur
    if (Test-Kommando 'Get-NetFirewallProfile') {
        try {
            $fp = @(Get-NetFirewallProfile -ErrorAction Stop)
            Add-Resultat -Nr 12 -Sjekk 'Windows-brannmur per profil' -Status INFO -Verdi (($fp | ForEach-Object { '{0}={1}' -f (Get-Egenskap $_ 'Name' ''), (Get-Egenskap $_ 'Enabled' '') }) -join ', ')
        } catch { Add-Resultat -Nr 12 -Sjekk 'Windows-brannmur per profil' -Status SKIP -Verdi (Get-Feilmelding $_) }
    } else {
        Add-Resultat -Nr 12 -Sjekk 'Windows-brannmur per profil' -Status SKIP -Verdi 'Get-NetFirewallProfile mangler (ikke Windows)'
    }

    # IPv6-binding
    if ((Test-Kommando 'Get-NetAdapterBinding') -and $null -ne $script:Primaer -and $script:Primaer.Navn) {
        try {
            $b = Get-NetAdapterBinding -Name $script:Primaer.Navn -ComponentID 'ms_tcpip6' -ErrorAction Stop | Select-Object -First 1
            Add-Resultat -Nr 12 -Sjekk 'IPv6-binding (ms_tcpip6) på grensesnittet' -Status INFO -Verdi ('Enabled={0}' -f (Get-Egenskap $b 'Enabled' '?'))
        } catch { Add-Resultat -Nr 12 -Sjekk 'IPv6-binding (ms_tcpip6)' -Status SKIP -Verdi (Get-Feilmelding $_) }
    }

    # Samlepunkter fra tidligere seksjoner
    $apipa = @($script:Ipv4Adresser | Where-Object { $_ -match '^169\.254\.' })
    if ($apipa.Count -gt 0) { Add-Resultat -Nr 12 -Sjekk 'APIPA-adresse' -Status FAIL -Verdi ($apipa -join ', ') -Terskel 'ingen' -Detaljer 'Se seksjon 3.' }
    if ($script:AntallDefaultRuter -gt 1) { Add-Resultat -Nr 12 -Sjekk 'Flere default-ruter' -Status WARN -Verdi ('{0} ruter' -f $script:AntallDefaultRuter) -Terskel '1' -Detaljer 'Se seksjon 2.' }
    Add-Resultat -Nr 12 -Sjekk 'DoH i nettleser' -Status INFO -Verdi 'nettleser-DoH går utenom lokal DNS (interne navn, filtrering og NXDOMAIN-testen gjelder da ikke nettleseren)'

    # wlanreport (krever admin — aldri påkrevd)
    if ($script:PaaWindows -and $script:ErWifi -and (Test-Kommando 'netsh')) {
        if ($script:ErAdmin) {
            $wr = Invoke-Ekstern -Exe 'netsh' -Argumenter @('wlan', 'show', 'wlanreport') -TimeoutSek 120
            Add-RaaUtdata -Nr 12 -Tittel 'netsh wlan show wlanreport' -Tekst ($wr.Utdata + $wr.Feil)
            $sti = 'C:\ProgramData\Microsoft\Windows\WlanReport\wlan-report-latest.html'
            $pm = [regex]::Match($wr.Utdata, '([A-Za-z]:\\[^\r\n"]+?\.html)')
            if ($pm.Success) { $sti = $pm.Groups[1].Value }
            if ($wr.Kjort -and -not $wr.TidsAvbrutt) { Add-Resultat -Nr 12 -Sjekk 'WLAN-rapport (wlanreport)' -Status INFO -Verdi ('generert: {0}' -f $sti) -Detaljer 'Åpne filen i nettleser: viser tilkoblingshistorikk, frakoblingsårsaker og driverhendelser siste 3 døgn.' }
            else { Add-Resultat -Nr 12 -Sjekk 'WLAN-rapport (wlanreport)' -Status INFO -Verdi ('kunne ikke genereres: ' + $wr.Feil) }
        } else {
            Add-Resultat -Nr 12 -Sjekk 'WLAN-rapport (wlanreport)' -Status INFO -Verdi 'krever administrator — hoppet over (kjør «netsh wlan show wlanreport» i et admin-vindu ved behov)'
        }
    }
}

# ------------------------------------------------------------------------------------
# Seksjon 13 — Oppsummering
# ------------------------------------------------------------------------------------
function Get-Oppsummering {
    $o = [ordered]@{ pass = 0; warn = 0; fail = 0; skip = 0; info = 0 }
    foreach ($r in $script:Resultater) {
        switch ($r.status) {
            'PASS' { $o['pass']++ }
            'WARN' { $o['warn']++ }
            'FAIL' { $o['fail']++ }
            'SKIP' { $o['skip']++ }
            default { $o['info']++ }
        }
    }
    return $o
}

function Invoke-Seksjon13 {
    $o = Get-Oppsummering
    $kjoretid = (Get-Date) - $script:StartTid
    Add-Resultat -Nr 13 -Sjekk 'Totalt' -Status INFO -Verdi ('PASS {0}, WARN {1}, FAIL {2}, SKIP {3}, INFO {4} — kjøretid {5}' -f $o['pass'], $o['warn'], $o['fail'], $o['skip'], $o['info'], (Format-Varighet $kjoretid))
    $feil = @($script:Resultater | Where-Object { $_.status -eq 'FAIL' })
    $adv = @($script:Resultater | Where-Object { $_.status -eq 'WARN' })
    if ($feil.Count -gt 0) { Add-Resultat -Nr 13 -Sjekk 'FAIL-punkter' -Status INFO -Verdi (($feil | ForEach-Object { '{0}: {1}' -f $_.seksjon, $_.sjekk }) -join ' | ') }
    else { Add-Resultat -Nr 13 -Sjekk 'FAIL-punkter' -Status INFO -Verdi 'ingen' }
    if ($adv.Count -gt 0) { Add-Resultat -Nr 13 -Sjekk 'WARN-punkter' -Status INFO -Verdi (($adv | ForEach-Object { '{0}: {1}' -f $_.seksjon, $_.sjekk }) -join ' | ') }
    else { Add-Resultat -Nr 13 -Sjekk 'WARN-punkter' -Status INFO -Verdi 'ingen' }
    $kjede = @()
    $kjede += ('klient: {0}' -f $(if ($null -ne $script:Primaer) { $script:Primaer.Navn } else { 'ukjent' }))
    if ($script:ErWifi -and $null -ne $script:Wlan) { $kjede += ('AP: BSSID {0} på {1}' -f (Find-Nokkel $script:Wlan '^BSSID$' '?'), (Find-Nokkel $script:Wlan '^SSID$' '?')) } else { $kjede += 'AP: (kablet/ukjent)' }
    $kjede += 'svitsj: (modell fylles inn)'
    $kjede += ('brannmur/gateway: {0}' -f $(if ($script:GatewayIp) { $script:GatewayIp } else { 'ukjent' }))
    $kjede += ('fiber/WAN: offentlig IP {0}' -f $(if ($script:OffentligIp) { $script:OffentligIp } else { 'ukjent' }))
    Add-Resultat -Nr 13 -Sjekk 'Kjede' -Status INFO -Verdi ($kjede -join ' → ')
    Add-Resultat -Nr 13 -Sjekk 'Rapportfiler' -Status INFO -Verdi ('{0} og {1}' -f $script:MdSti, $script:JsonSti)
    Add-Resultat -Nr 13 -Sjekk 'Neste steg' -Status INFO -Verdi 'Lim inn innholdet i .md-filen i chatten for analyse'
}

# ------------------------------------------------------------------------------------
# Rapportskriving (Markdown + JSON, UTF-8 uten BOM)
# ------------------------------------------------------------------------------------
function Write-Rapport {
    $utf8 = New-Object System.Text.UTF8Encoding($false)
    try { if (-not (Test-Path -LiteralPath $Rapportmappe)) { $null = New-Item -ItemType Directory -Path $Rapportmappe -Force -ErrorAction Stop } } catch { }
    $o = Get-Oppsummering
    $tid = $script:StartTid.ToString('yyyy-MM-ddTHH:mm:sszzz')
    $kjoretid = (Get-Date) - $script:StartTid
    $vert = [Environment]::MachineName
    $param = [ordered]@{
        rapportmappe = [string]$Rapportmappe; hurtig = [bool]$Hurtig; forventet_ned = $ForventetNed; forventet_opp = $ForventetOpp
        iperf_server = $IperfServer; interne_navn = @($InterneNavn); gateway = $Gateway; grensesnitt = $Grensesnitt; ingen_farger = [bool]$IngenFarger
    }
    $ssid = ''
    if ($null -ne $script:Wlan) { $ssid = [string](Find-Nokkel $script:Wlan '^SSID$' '') }

    # Markdown
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.AppendLine(('# nettsjekk-rapport — {0} — {1}' -f $vert, $script:StartTid.ToString('yyyy-MM-dd HH:mm:ss')))
    [void]$sb.AppendLine()
    [void]$sb.AppendLine('Lim inn innholdet i denne filen i chatten for analyse. Skriptet endrer ingenting — kun lesing og målinger.')
    [void]$sb.AppendLine()
    [void]$sb.AppendLine('| Felt | Verdi |')
    [void]$sb.AppendLine('|---|---|')
    [void]$sb.AppendLine(('| Verktøy | nettsjekk sjekk-klient.ps1 versjon {0} |' -f $script:Versjon))
    [void]$sb.AppendLine(('| Vert | {0} |' -f $vert))
    [void]$sb.AppendLine(('| OS | {0} |' -f $script:OsTekst))
    [void]$sb.AppendLine(('| PowerShell | {0} ({1}) |' -f $PSVersionTable.PSVersion.ToString(), $script:PsUtgave))
    [void]$sb.AppendLine(('| Starttid | {0} |' -f $tid))
    [void]$sb.AppendLine(('| Kjøretid | {0} |' -f (Format-Varighet $kjoretid)))
    [void]$sb.AppendLine(('| Modus | {0} |' -f $(if ($Hurtig) { 'hurtig (seksjon 8, 9, 10 hoppet over)' } else { 'normal' })))
    [void]$sb.AppendLine(('| Parametre | ForventetNed={0}, ForventetOpp={1}, IperfServer={2}, InterneNavn={3}, Gateway={4}, Grensesnitt={5} |' -f $ForventetNed, $ForventetOpp, $IperfServer, ($InterneNavn -join ','), $Gateway, $Grensesnitt))
    [void]$sb.AppendLine(('| Grensesnitt | {0} |' -f $(if ($null -ne $script:Primaer) { '{0} — {1}' -f $script:Primaer.Navn, $script:Primaer.Beskrivelse } else { 'ukjent' })))
    [void]$sb.AppendLine(('| SSID | {0} |' -f $(if ($ssid) { $ssid } else { '(ikke Wi-Fi)' })))
    [void]$sb.AppendLine(('| Gateway | {0} |' -f $(if ($script:GatewayIp) { $script:GatewayIp } else { 'ukjent' })))
    [void]$sb.AppendLine(('| Offentlig IP | {0} |' -f $(if ($script:OffentligIp) { $script:OffentligIp } else { 'ukjent' })))
    [void]$sb.AppendLine(('| Oppsummering | PASS {0}, WARN {1}, FAIL {2}, SKIP {3}, INFO {4} |' -f $o['pass'], $o['warn'], $o['fail'], $o['skip'], $o['info']))
    [void]$sb.AppendLine()
    foreach ($seksjon in $script:SeksjonNavn) {
        [void]$sb.AppendLine('## ' + $seksjon)
        [void]$sb.AppendLine()
        $rader = @($script:Resultater | Where-Object { $_.seksjon -eq $seksjon })
        if ($rader.Count -eq 0) { [void]$sb.AppendLine('- [INFO] ingen resultater registrert') }
        foreach ($r in $rader) {
            $linje = ('- [{0}] {1}' -f $r.status, $r.sjekk)
            if ($r.verdi) { $linje += ' — ' + $r.verdi }
            if ($r.terskel) { $linje += (' (terskel {0})' -f $r.terskel) }
            [void]$sb.AppendLine($linje)
            if ($r.detaljer) { [void]$sb.AppendLine('  - detaljer: ' + ($r.detaljer -replace "`r?`n", ' ')) }
        }
        if ($script:RaaUtdata.ContainsKey($seksjon)) {
            foreach ($raa in $script:RaaUtdata[$seksjon]) {
                [void]$sb.AppendLine()
                [void]$sb.AppendLine('### Rå utdata: ' + $raa.tittel)
                [void]$sb.AppendLine()
                [void]$sb.AppendLine('```text')
                [void]$sb.AppendLine(($raa.tekst -replace '```', "'''"))
                [void]$sb.AppendLine('```')
            }
        }
        [void]$sb.AppendLine()
    }
    [void]$sb.AppendLine('---')
    [void]$sb.AppendLine('Lim inn innholdet i .md-filen i chatten for analyse.')
    [System.IO.File]::WriteAllText($script:MdSti, $sb.ToString(), $utf8)

    # JSON
    $json = [ordered]@{
        meta = [ordered]@{
            verktoy = 'nettsjekk'; versjon = $script:Versjon; host = $vert; os = $script:OsTekst; tid = $tid; parametre = $param
        }
        resultater = @($script:Resultater | ForEach-Object { [ordered]@{ seksjon = $_.seksjon; sjekk = $_.sjekk; status = $_.status; verdi = $_.verdi; terskel = $_.terskel; detaljer = $_.detaljer } })
        oppsummering = $o
    }
    $jsonTekst = $json | ConvertTo-Json -Depth 6
    [System.IO.File]::WriteAllText($script:JsonSti, $jsonTekst, $utf8)
}

# ------------------------------------------------------------------------------------
# Hovedløp
# ------------------------------------------------------------------------------------
$vertRen = ([Environment]::MachineName -replace '[^A-Za-z0-9_-]', '_')
$stempel = $script:StartTid.ToString('yyyyMMdd-HHmmss')
$script:MdSti = Join-Path -Path $Rapportmappe -ChildPath ('nettsjekk-rapport-{0}-{1}.md' -f $vertRen, $stempel)
$script:JsonSti = Join-Path -Path $Rapportmappe -ChildPath ('nettsjekk-rapport-{0}-{1}.json' -f $vertRen, $stempel)

Write-Host ''
Write-Host ('nettsjekk sjekk-klient.ps1 versjon {0} — ende-til-ende klientsjekk (fiber – brannmur – svitsj – AP – klient)' -f $script:Versjon)
Write-Host 'Endrer ingenting — kun lesing og målinger. Wi-Fi-passord leses aldri.'
Write-Host ('Rapport: {0}' -f $script:MdSti)
if ($Hurtig) { Write-Host 'Hurtigmodus: seksjon 8, 9 og 10 hoppes over.' }

try {
    Invoke-SeksjonTrygt -Nr 0 -Kode { Invoke-Seksjon0 }
    Invoke-SeksjonTrygt -Nr 1 -Kode { Invoke-Seksjon1 }
    Invoke-SeksjonTrygt -Nr 2 -Kode { Invoke-Seksjon2 }
    Invoke-SeksjonTrygt -Nr 3 -Kode { Invoke-Seksjon3 }
    Invoke-SeksjonTrygt -Nr 4 -Kode { Invoke-Seksjon4 }
    Invoke-SeksjonTrygt -Nr 5 -Kode { Invoke-Seksjon5 }
    Invoke-SeksjonTrygt -Nr 6 -Kode { Invoke-Seksjon6 }
    Invoke-SeksjonTrygt -Nr 7 -Kode { Invoke-Seksjon7 }
    Invoke-SeksjonTrygt -Nr 8 -Kode { Invoke-Seksjon8; if ($script:Hastighet8Kjort) { Measure-TcpRetransDelta } }
    Invoke-SeksjonTrygt -Nr 9 -Kode { Invoke-Seksjon9 }
    Invoke-SeksjonTrygt -Nr 10 -Kode { Invoke-Seksjon10 }
    Invoke-SeksjonTrygt -Nr 11 -Kode { Invoke-Seksjon11 }
    Invoke-SeksjonTrygt -Nr 12 -Kode { Invoke-Seksjon12 }
    Invoke-SeksjonTrygt -Nr 13 -Kode { Invoke-Seksjon13 }
} finally {
    try {
        Write-Rapport
        Write-Host ''
        Write-Host ('Rapport skrevet: {0}' -f $script:MdSti)
        Write-Host ('JSON skrevet:    {0}' -f $script:JsonSti)
        Write-Host 'Lim inn innholdet i .md-filen i chatten for analyse.'
    } catch {
        Write-Host ('[FAIL] 13 Oppsummering: kunne ikke skrive rapport — ' + (Get-Feilmelding $_))
    }
}
exit 0
