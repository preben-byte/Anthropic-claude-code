# =====================================================================================
# ap-status.ps1 — nettsjekk: READ-ONLY statusinnhenting fra Extreme/Aerohive AP-er via plink (SSH)
#
# Formål : Henter status (versjon, oppetid, CAPWAP mot ExtremeCloudIQ, klienter, radio/ACSP, naboer, logg)
#          fra alle AP-er i ap-liste.txt ved å kjøre lesende «show»-kommandoer over SSH med plink.exe (PuTTY),
#          lagrer rå utdata per AP og kommando i en tidsstemplet mappe og skriver oppsummering.md (tabell)
#          som limes inn i chatten for analyse. Passer for AP305C, AP305CX, AP460C, Atom AP30 (IQ Engine)
#          og eldre HiveOS-enheter som AP141.
# Kjøring: powershell.exe -ExecutionPolicy Bypass -File .\ap-status.ps1
#          powershell.exe -ExecutionPolicy Bypass -File .\ap-status.ps1 -KunNaabar
#          pwsh -File .\ap-status.ps1 -Bruker admin -HostKeyGodta -Rapportmappe C:\Temp\ap-status
#          pwsh -File .\ap-status.ps1 -Session "marivold-ap"     (lagret PuTTY-økt med nøkkel, ingen -pw)
# Krav   : Windows PowerShell 5.1 eller PowerShell 7.x. plink.exe fra PuTTY (https://www.putty.org) i PATH,
#          i C:\Program Files\PuTTY\ eller ved siden av skriptet. ap-liste.txt (kopier ap-liste.eksempel.txt)
#          og ap-kommandoer.txt i samme mappe. Ingen adminrettigheter nødvendig.
# Versjon 1.0 — 2026-09-09
# Endrer ingenting — kun lesing og målinger.
# =====================================================================================

<#
.SYNOPSIS
    nettsjekk — ap-status: henter READ-ONLY status fra alle Extreme/Aerohive AP-er over SSH med plink.exe (PuTTY).

.DESCRIPTION
    Skriptet leser AP-listen (én AP per linje på formen navn;ip), sjekker først om hver AP svarer på TCP 22
    (3 s tidsavbrudd) og kjører deretter kommandoene i ap-kommandoer.txt på hver AP med plink.exe – én
    plink-prosess per kommando, hver med tidsavbrudd (-TimeoutSek, standard 25 s). Utdata lagres i en
    tidsstemplet rapportmappe:

        <Rapportmappe>\<navn>_<ip>\<kommando>.txt   rå utdata per kommando (f.eks. show_capwap_client.txt)
        <Rapportmappe>\<navn>_<ip>\all.txt           alle kommandoer for AP-en samlet, med feil og tidsbruk
        <Rapportmappe>\oppsummering.md               tabell per AP: navn, ip, nåbar, versjon, oppetid,
                                                     CAPWAP-status, antall klienter, feil – lim inn i chatten

    Statuslinjer på konsollen har formen  [PASS] <AP>: <sjekk> — <verdi> (terskel <t>)  med statusene
    PASS, WARN, FAIL, INFO og SKIP.

    Skriptet er READ-ONLY og kjører aldri noe som endrer konfigurasjon. Et sikkerhetsfilter nekter å kjøre
    kommandolinjer som inneholder config, reset, reboot, save, write, erase, clear, delete, «no » eller «set »
    – slike linjer rapporteres som [SKIP]. Filteret kan bare slås av bevisst med -TillatEndringer (ikke anbefalt).

    VERTSNØKLER (host keys): plink kjøres med -batch, og -batch NEKTER å koble til en AP hvis SSH-vertsnøkkelen
    ikke allerede ligger i PuTTYs cache (registret på PC-en). Det finnes ikke noe «godta ukjent nøkkel»-flagg
    som kan kombineres med -batch. Du har derfor to valg:
      1) Koble til hver AP én gang manuelt (plink -ssh admin@<ip>  eller PuTTY) og svar «y» – da lagres nøkkelen,
         og skriptet kjører deretter helt uten spørsmål. Dette er det sikreste.
      2) Kjør skriptet med -HostKeyGodta. Da gjøres først én forbindelse per AP UTEN -batch der «y» sendes på
         standard inn, slik at nøkkelen lagres, før kommandoene kjøres med -batch som normalt. Avveining:
         AP-ens identitet godtas blindt første gang (tilsvarer «StrictHostKeyChecking=no»), og «y» blir også
         svaret på eventuelle andre spørsmål plink stiller. Bruk kun på et administrasjonsnett du stoler på.

    PASSORD: Uten -Session spør skriptet én gang om passord (Read-Host -AsSecureString). Passordet holdes bare
    i minnet og sendes til plink som -pw. MERK: -pw er synlig i prosesslisten på PC-en (Oppgavebehandling,
    tasklist, Get-Process) mens hver plink-prosess kjører. Passordet skrives aldri til rapportfilene.
    Bedre alternativ: nøkkelbasert pålogging via en lagret PuTTY-økt med privat nøkkel (eller Pageant) og
    -Session <øktnavn> – da brukes ikke -pw i det hele tatt. Tomt passord = ingen -pw (Pageant/nøkkel brukes).

.PARAMETER ApListe
    Fil med AP-er, én per linje: navn;ip. Standard: .\ap-liste.txt (finnes den ikke i gjeldende mappe, prøves
    mappen skriptet ligger i). Kopier ap-liste.eksempel.txt til ap-liste.txt og rediger.

.PARAMETER Kommandoer
    Fil med CLI-kommandoer, én per linje. Standard: .\ap-kommandoer.txt (reserve: mappen skriptet ligger i).

.PARAMETER Bruker
    SSH-brukernavn på AP-ene. Standard: admin. Sendes til plink som -l. Med -Session brukes brukernavnet fra
    økten, med mindre -Bruker er angitt uttrykkelig.

.PARAMETER PlinkPath
    Full sti til plink.exe. Standard: søker i PATH, deretter C:\Program Files\PuTTY\plink.exe
    (og Program Files (x86)), deretter ved siden av skriptet.

.PARAMETER Rapportmappe
    Mappe for utdata. Standard: .\ap-status-<YYYYMMDD-HHMMSS> i gjeldende mappe. Opprettes ved behov.

.PARAMETER TimeoutSek
    Tidsavbrudd i sekunder per kommando (per plink-prosess). Standard: 25. Prosessen avsluttes ved tidsavbrudd.

.PARAMETER HostKeyGodta
    Godta ukjente SSH-vertsnøkler automatisk: én forbindelse per AP kjøres uten -batch med «y» på standard inn
    (lagrer nøkkelen i PuTTY-cachen), deretter kjøres kommandoene med -batch. Se DESCRIPTION for avveiningen.
    Uten denne bryteren må vertsnøkkelen til hver AP være lagret fra før (koble til manuelt én gang).

.PARAMETER TillatEndringer
    Slår av sikkerhetsfilteret som stopper kommandolinjer med config, reset, reboot, save, write, erase, clear,
    delete, «no » og «set ». Ikke anbefalt – skriptet er ment å være READ-ONLY.

.PARAMETER Session
    Navn på en lagret PuTTY-økt (plink -load). Økten bør inneholde brukernavn og privat nøkkel; da spørres det
    ikke om passord og -pw brukes ikke. IP-adressen fra AP-listen overstyrer vertsnavnet i økten.

.PARAMETER KunNaabar
    Test bare TCP 22-nåbarhet (3 s) mot hver AP uten plink og uten passord. Bruk denne først for å verifisere
    AP-listen. Skriver også oppsummering.md.

.PARAMETER IngenFarger
    Skriv statuslinjer uten farger (for logging/omdirigering).

.EXAMPLE
    .\ap-status.ps1 -KunNaabar
    Sjekker bare at AP-ene i .\ap-liste.txt svarer på TCP 22. Ingen plink, ingen passord.

.EXAMPLE
    .\ap-status.ps1
    Spør om passord for admin, kjører alle kommandoene i .\ap-kommandoer.txt på hver AP og skriver
    .\ap-status-<tid>\oppsummering.md. Krever at vertsnøklene er lagret fra før (se -HostKeyGodta).

.EXAMPLE
    .\ap-status.ps1 -HostKeyGodta -Rapportmappe C:\Temp\ap-status -TimeoutSek 40
    Godtar ukjente vertsnøkler automatisk, lengre tidsavbrudd per kommando, rapport i C:\Temp\ap-status.

.EXAMPLE
    .\ap-status.ps1 -Session marivold-ap
    Bruker en lagret PuTTY-økt med privat nøkkel (ingen -pw i prosesslisten).

.NOTES
    Versjon 1.0 — 2026-09-09. Endrer ingenting — kun lesing og målinger.
    Kompatibel med Windows PowerShell 5.1 og PowerShell 7.x (kjører også under pwsh på Linux/macOS med plink
    fra putty-tools). Avslutningskoder: 0 = kjørt ferdig (rapport skrevet, også når AP-er ikke svarer),
    2 = plink.exe ikke funnet, 3 = AP-liste eller kommandofil mangler/er tom, 4 = uventet feil.
    CAPWAP-forutsetninger for AP-ene mot ExtremeCloudIQ: fungerende DNS, UDP 12222 og TCP 443 mot
    redirector.aerohive.com / extremecloudiq.com.
#>

[CmdletBinding()]
param(
    [Parameter()][string]$ApListe = '.\ap-liste.txt',
    [Parameter()][string]$Kommandoer = '.\ap-kommandoer.txt',
    [Parameter()][string]$Bruker = 'admin',
    [Parameter()][string]$PlinkPath = '',
    [Parameter()][string]$Rapportmappe = '',
    [Parameter()][ValidateRange(3, 600)][int]$TimeoutSek = 25,
    [Parameter()][switch]$HostKeyGodta,
    [Parameter()][switch]$TillatEndringer,
    [Parameter()][string]$Session = '',
    [Parameter()][switch]$KunNaabar,
    [Parameter()][switch]$IngenFarger
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Continue'
$ProgressPreference = 'SilentlyContinue'

# ------------------------------------------------------------------------------------
# Globale variabler
# ------------------------------------------------------------------------------------
$script:Versjon = '1.0'
$script:PaaWindows = ($env:OS -eq 'Windows_NT')
$script:Farger = -not $IngenFarger
$script:Inv = [System.Globalization.CultureInfo]::InvariantCulture
$script:StartTid = Get-Date
$script:Stempel = $script:StartTid.ToString('yyyyMMdd-HHmmss')
$script:Utf8UtenBom = New-Object System.Text.UTF8Encoding($false)
$script:FilterRegex = 'config|reset|reboot|save|write|erase|clear|delete|no |set '
$script:AvbruddRegex = 'FATAL ERROR|not cached|Access denied|Unable to authenticate|Network error|Unable to open connection|Connection refused|timed out|Disconnected|Server unexpectedly closed|Host does not exist|Name or service not known'
$script:Teller = @{ 'PASS' = 0; 'WARN' = 0; 'FAIL' = 0; 'INFO' = 0; 'SKIP' = 0 }
$script:Passord = ''
$script:BrukerAngitt = $PSBoundParameters.ContainsKey('Bruker')
$script:PlinkExe = ''
$script:PlinkVersjon = ''
$script:RapportSti = ''
$script:SvarFil = ''
$script:ApListeSti = ''
$script:KommandoSti = ''
$script:KommandoListe = @()
$script:Resultater = New-Object System.Collections.Generic.List[object]
$script:Vertsnavn = 'ukjent'
try { $script:Vertsnavn = [System.Net.Dns]::GetHostName() } catch { }
if ($env:COMPUTERNAME) { $script:Vertsnavn = $env:COMPUTERNAME }
$script:PsUtgave = 'Desktop'
if ($PSVersionTable.ContainsKey('PSEdition')) { $script:PsUtgave = [string]$PSVersionTable['PSEdition'] }
$script:SkriptMappe = ''
if ($PSScriptRoot) { $script:SkriptMappe = $PSScriptRoot }

# ------------------------------------------------------------------------------------
# Statuslinjer og hjelpefunksjoner
# ------------------------------------------------------------------------------------
function Write-Status {
    param([string]$Status, [string]$Seksjon, [string]$Sjekk, [string]$Verdi = '', [string]$Terskel = '')
    $linje = "[$Status] ${Seksjon}: $Sjekk"
    if ($Verdi) { $linje += " — $Verdi" }
    if ($Terskel) { $linje += " (terskel $Terskel)" }
    if ($script:Teller.ContainsKey($Status)) { $script:Teller[$Status] = [int]$script:Teller[$Status] + 1 }
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
    param([string]$Tekst)
    $linje = "`n=== $Tekst ==="
    if ($script:Farger) {
        try { Write-Host $linje -ForegroundColor White } catch { Write-Host $linje }
    } else {
        Write-Host $linje
    }
}

function Write-Melding {
    param([string]$Tekst, [string]$Farge = 'Gray')
    if ($script:Farger) {
        try { Write-Host $Tekst -ForegroundColor $Farge } catch { Write-Host $Tekst }
    } else {
        Write-Host $Tekst
    }
}

function Get-Feilmelding {
    param($Feil)
    try { if ($null -ne $Feil.Exception) { return [string]$Feil.Exception.Message } } catch { }
    return [string]$Feil
}

function Format-Tall {
    param([double]$Verdi, [int]$Desimaler = 1)
    return $Verdi.ToString('F' + $Desimaler, $script:Inv)
}

function Resolve-Sti {
    # Gjør en sti absolutt i forhold til PowerShells gjeldende mappe (også for stier som ikke finnes ennå).
    param([string]$Sti)
    if (-not $Sti) { return '' }
    $s = $Sti
    if (-not $script:PaaWindows) { $s = $s.Replace('\', '/') }
    try { return [string]$ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($s) } catch { }
    try { return [System.IO.Path]::GetFullPath($s) } catch { }
    return $s
}

function Find-Inndatafil {
    # Finner en inndatafil: som angitt, ellers (bare for standardverdien) i mappen skriptet ligger i.
    param([string]$Sti, [string]$Standardnavn, [bool]$ErStandard)
    $k = Resolve-Sti $Sti
    if ($k -and (Test-Path -LiteralPath $k -PathType Leaf)) { return $k }
    if ($ErStandard -and $script:SkriptMappe) {
        $k2 = Join-Path $script:SkriptMappe $Standardnavn
        if (Test-Path -LiteralPath $k2 -PathType Leaf) { return $k2 }
    }
    return ''
}

function Read-Tekstfil {
    # Leser en fil som UTF-8 med noen forsøk (filen kan være låst et øyeblikk etter at prosessen ble avsluttet).
    param([string]$Sti)
    if (-not $Sti) { return '' }
    if (-not (Test-Path -LiteralPath $Sti -PathType Leaf)) { return '' }
    for ($i = 0; $i -lt 5; $i++) {
        try { return [System.IO.File]::ReadAllText($Sti, [System.Text.Encoding]::UTF8) } catch { Start-Sleep -Milliseconds 200 }
    }
    return ''
}

function Write-Tekstfil {
    param([string]$Sti, [string]$Innhold)
    try { [System.IO.File]::WriteAllText($Sti, $Innhold, $script:Utf8UtenBom); return $true } catch {
        Write-Status 'WARN' 'Rapport' ("kunne ikke skrive {0}" -f $Sti) (Get-Feilmelding $_)
        return $false
    }
}

function ConvertTo-Filnavn {
    # Lager et trygt fil-/mappenavn av et AP-navn, en IP eller en kommando.
    param([string]$Tekst)
    if ($null -eq $Tekst) { return 'ukjent' }
    $t = $Tekst.Trim()
    $t = [regex]::Replace($t, '[^A-Za-z0-9._\-]+', '_')
    $t = $t.Trim([char[]]@([char]'_', [char]'.'))
    if ($t -eq '') { $t = 'ukjent' }
    if ($t.Length -gt 80) { $t = $t.Substring(0, 80) }
    return $t
}

function ConvertTo-Argument {
    # Setter anførselstegn rundt et argument etter Windows-reglene (CommandLineToArgvW) slik at plink får det uendret.
    param([string]$Tekst)
    if ($null -eq $Tekst) { $Tekst = '' }
    if ($Tekst -ne '' -and $Tekst -notmatch '[\s"]') { return $Tekst }
    $sb = New-Object System.Text.StringBuilder
    $null = $sb.Append('"')
    $bs = 0
    foreach ($c in $Tekst.ToCharArray()) {
        if ($c -eq [char]'\') { $bs++; continue }
        if ($c -eq [char]'"') {
            $null = $sb.Append('\' * (2 * $bs + 1))
            $null = $sb.Append('"')
            $bs = 0
            continue
        }
        if ($bs -gt 0) { $null = $sb.Append('\' * $bs); $bs = 0 }
        $null = $sb.Append($c)
    }
    if ($bs -gt 0) { $null = $sb.Append('\' * (2 * $bs)) }
    $null = $sb.Append('"')
    return $sb.ToString()
}

function ConvertTo-MdCelle {
    param([string]$Tekst)
    if ($null -eq $Tekst) { return '' }
    $t = $Tekst -replace '\r?\n', ' '
    $t = $t.Replace('|', '\|').Trim()
    if ($t -eq '') { $t = '–' }
    return $t
}

function ConvertFrom-SikkerStreng {
    # Konverterer SecureString til klartekst – kun i minnet, brukes bare til -pw for plink.
    param([System.Security.SecureString]$Sikker)
    if ($null -eq $Sikker) { return '' }
    if ($Sikker.Length -eq 0) { return '' }
    try { return [string](New-Object System.Net.NetworkCredential('', $Sikker)).Password } catch { }
    $bstr = [IntPtr]::Zero
    try {
        $bstr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($Sikker)
        return [string][System.Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
    } catch {
        return ''
    } finally {
        if ($bstr -ne [IntPtr]::Zero) { [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr) }
    }
}

function Read-Passord {
    # Spør om passord maskert (Read-Host -AsSecureString). Er standard inn omdirigert (rør, fil, oppgaveplanlegger),
    # kan konsollen ikke lese tastetrykk maskert – og under PowerShell 7 avsluttes hele prosessen uten feilmelding.
    # Da leses i stedet én linje umaskert fra standard inn, slik at skriptet aldri stopper uventet.
    param([string]$Ledetekst)
    $omdirigert = $false
    try { $omdirigert = [bool][Console]::IsInputRedirected } catch { $omdirigert = $false }
    $konsoll = $false
    try { $konsoll = ([string]$Host.Name -eq 'ConsoleHost') } catch { $konsoll = $false }
    if ($omdirigert -and $konsoll) {
        Write-Status 'WARN' 'Oppsett' 'passord' 'standard inn er omdirigert — passordet leses umaskert som én linje fra standard inn'
        $linje = $null
        try { $linje = [Console]::In.ReadLine() } catch { $linje = $null }
        if ($null -eq $linje) { return '' }
        return ([string]$linje).Trim()
    }
    $sikker = $null
    try { $sikker = Read-Host -Prompt $Ledetekst -AsSecureString } catch { $sikker = $null }
    return (ConvertFrom-SikkerStreng $sikker)
}

function Test-KommandoTrygg {
    # Sikkerhetsfilter: sann hvis kommandolinjen IKKE inneholder noe som kan endre konfigurasjon.
    param([string]$Kommando)
    if ($null -eq $Kommando) { return $true }
    return -not ($Kommando -match $script:FilterRegex)
}

# ------------------------------------------------------------------------------------
# Inndata: AP-liste og kommandoer
# ------------------------------------------------------------------------------------
function Read-ApListe {
    param([string]$Sti)
    $liste = New-Object System.Collections.Generic.List[object]
    $linjer = @()
    try { $linjer = @(Get-Content -LiteralPath $Sti -Encoding UTF8 -ErrorAction Stop) } catch {
        Write-Status 'FAIL' 'Oppsett' 'AP-liste' ("kunne ikke lese {0}: {1}" -f $Sti, (Get-Feilmelding $_))
        return @()
    }
    $nr = 0
    foreach ($raa in $linjer) {
        $nr++
        if ($null -eq $raa) { continue }
        $l = ([string]$raa).Trim()
        if ($l -eq '' -or $l.StartsWith('#')) { continue }
        if ($l -match '\s#') { $l = ($l -split '\s#', 2)[0].Trim() }
        $navn = ''
        $ip = ''
        $deler = @($l -split '[;,\t]' | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' })
        if ($deler.Count -ge 2) {
            $navn = $deler[0]
            $ip = $deler[1]
        } elseif ($deler.Count -eq 1) {
            if ($deler[0] -match '^(.+?)\s+(\S+)$') {
                $navn = $Matches[1]
                $ip = $Matches[2]
            } else {
                $navn = $deler[0]
                $ip = $deler[0]
            }
        } else {
            continue
        }
        if ($ip -notmatch '^[A-Za-z0-9.\-:_\[\]]+$') {
            Write-Status 'WARN' 'Oppsett' ("AP-liste linje {0}" -f $nr) ("ugyldig adresse «{0}» — linjen hoppes over" -f $ip)
            continue
        }
        $liste.Add([pscustomobject]@{ Navn = $navn; Ip = $ip; Linje = $nr })
    }
    return $liste.ToArray()
}

function Read-Kommandoer {
    param([string]$Sti)
    $ut = New-Object System.Collections.Generic.List[string]
    $linjer = @()
    try { $linjer = @(Get-Content -LiteralPath $Sti -Encoding UTF8 -ErrorAction Stop) } catch {
        Write-Status 'FAIL' 'Oppsett' 'Kommandofil' ("kunne ikke lese {0}: {1}" -f $Sti, (Get-Feilmelding $_))
        return @()
    }
    foreach ($raa in $linjer) {
        if ($null -eq $raa) { continue }
        $l = ([string]$raa).Trim()
        if ($l -eq '' -or $l.StartsWith('#')) { continue }
        if ($l -match '\s#') { $l = ($l -split '\s#', 2)[0].Trim() }
        if ($l -eq '') { continue }
        $ut.Add($l)
    }
    return $ut.ToArray()
}

# ------------------------------------------------------------------------------------
# plink: finne, kjøre med tidsavbrudd, tolke feil
# ------------------------------------------------------------------------------------
function Find-Plink {
    param([string]$Angitt)
    if ($Angitt) {
        $k = Resolve-Sti $Angitt
        if (Test-Path -LiteralPath $k -PathType Leaf) { return $k }
        if (Test-Path -LiteralPath $k -PathType Container) {
            $k2 = Join-Path $k 'plink.exe'
            if (Test-Path -LiteralPath $k2 -PathType Leaf) { return $k2 }
        }
        return ''
    }
    foreach ($navn in @('plink.exe', 'plink')) {
        $cmd = $null
        try { $cmd = Get-Command -Name $navn -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1 } catch { $cmd = $null }
        if ($null -ne $cmd) {
            $sti = ''
            try { $sti = [string]$cmd.Path } catch { $sti = '' }
            if (-not $sti) { try { $sti = [string]$cmd.Source } catch { $sti = '' } }
            if ($sti -and (Test-Path -LiteralPath $sti -PathType Leaf)) { return $sti }
        }
    }
    $kandidater = New-Object System.Collections.Generic.List[string]
    $pf = [string]$env:ProgramFiles
    if ($pf) { $kandidater.Add((Join-Path $pf 'PuTTY\plink.exe')) }
    $pf86 = [string]${env:ProgramFiles(x86)}
    if ($pf86) { $kandidater.Add((Join-Path $pf86 'PuTTY\plink.exe')) }
    $kandidater.Add('C:\Program Files\PuTTY\plink.exe')
    $kandidater.Add('C:\Program Files (x86)\PuTTY\plink.exe')
    if ($script:SkriptMappe) { $kandidater.Add((Join-Path $script:SkriptMappe 'plink.exe')) }
    foreach ($k in $kandidater) {
        try { if (Test-Path -LiteralPath $k -PathType Leaf) { return $k } } catch { }
    }
    return ''
}

function Invoke-Prosess {
    # Kjører et program med Start-Process (-NoNewWindow, omdirigert stdout/stderr til filer) og tidsavbrudd.
    # Ved tidsavbrudd avsluttes prosessen. Returnerer utdata, feilutdata, avslutningskode og tidsbruk.
    param(
        [string]$Exe,
        [string]$Argumenter,
        [string]$UtFil,
        [string]$FeilFil,
        [int]$TimeoutSekunder,
        [string]$InnFil = ''
    )
    $res = [pscustomobject]@{
        Startet = $false; ExitCode = -1; TidsAvbrutt = $false; Sekunder = 0.0; Utdata = ''; Feil = ''; Melding = ''
    }
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $p = $null
    try {
        $sp = @{
            FilePath = $Exe
            NoNewWindow = $true
            PassThru = $true
            RedirectStandardOutput = $UtFil
            RedirectStandardError = $FeilFil
            ErrorAction = 'Stop'
        }
        if ($Argumenter) { $sp['ArgumentList'] = $Argumenter }
        if ($InnFil) { $sp['RedirectStandardInput'] = $InnFil }
        $p = Start-Process @sp
    } catch {
        $sw.Stop()
        $res.Melding = ("kunne ikke starte {0}: {1}" -f $Exe, (Get-Feilmelding $_))
        return $res
    }
    if ($null -eq $p) {
        $sw.Stop()
        $res.Melding = ("kunne ikke starte {0}: Start-Process ga ingen prosess" -f $Exe)
        return $res
    }
    $res.Startet = $true
    $ferdig = $false
    try { $ferdig = $p.WaitForExit($TimeoutSekunder * 1000) } catch { $ferdig = $false }
    if (-not $ferdig) {
        $res.TidsAvbrutt = $true
        # Kill($true) tar med underprosesser (PowerShell 7 / .NET Core); Windows PowerShell 5.1 har bare Kill().
        $drept = $false
        try { $p.Kill($true); $drept = $true } catch { $drept = $false }
        if (-not $drept) { try { $p.Kill() } catch { } }
        try { $null = $p.WaitForExit(3000) } catch { }
        $res.Melding = ("tidsavbrudd etter {0} s — prosessen ble avsluttet" -f $TimeoutSekunder)
    } else {
        try { $p.WaitForExit() } catch { }
        try { $null = $p.HasExited } catch { }
        try { $res.ExitCode = [int]$p.ExitCode } catch { $res.ExitCode = -1 }
    }
    $sw.Stop()
    $res.Sekunder = [math]::Round($sw.Elapsed.TotalSeconds, 1)
    try { $p.Dispose() } catch { }
    $res.Utdata = Read-Tekstfil $UtFil
    $res.Feil = Read-Tekstfil $FeilFil
    return $res
}

function Get-PlinkArgumenter {
    # Bygger argumentlinjen til plink. $Batch = $false brukes bare for vertsnøkkel-forbindelsen (-HostKeyGodta).
    param([string]$Ip, [string]$Kommando, [bool]$Batch, [bool]$Maskert = $false)
    $deler = New-Object System.Collections.Generic.List[string]
    $deler.Add('-ssh')
    if ($Batch) { $deler.Add('-batch') }
    if ($Session) {
        $deler.Add('-load')
        $deler.Add((ConvertTo-Argument $Session))
        if ($script:BrukerAngitt) { $deler.Add('-l'); $deler.Add((ConvertTo-Argument $Bruker)) }
    } else {
        $deler.Add('-l')
        $deler.Add((ConvertTo-Argument $Bruker))
        if ($script:Passord -ne '') {
            $deler.Add('-pw')
            if ($Maskert) { $deler.Add('********') } else { $deler.Add((ConvertTo-Argument $script:Passord)) }
        }
    }
    $deler.Add((ConvertTo-Argument $Ip))
    $deler.Add((ConvertTo-Argument $Kommando))
    return ($deler.ToArray() -join ' ')
}

function Get-PlinkHint {
    # Oversetter kjente plink-feilmeldinger til et norsk råd.
    param([string]$Feil)
    if (-not $Feil) { return '' }
    # Mest spesifikke feil først; vertsnøkkel-rådet sist (plink skriver også vertsnøkkel-teksten ved andre feil).
    if ($Feil -match 'Access denied|Unable to authenticate|authentication|password') {
        return 'pålogging avvist — sjekk brukernavn (-Bruker) og passord, eller bruk -Session med nøkkel'
    }
    if ($Feil -match 'Connection refused') {
        return 'port 22 avviste tilkoblingen — SSH kan være slått av på AP-en (sjekk SSH-innstillingen i ExtremeCloudIQ)'
    }
    if ($Feil -match 'timed out|Network error|Unable to open connection|Host does not exist|Name or service not known|unreachable') {
        return 'nettverksfeil — AP-en svarer ikke på SSH (feil IP, VLAN/brannmur, eller AP-en er nede)'
    }
    if ($Feil -match 'unknown option|invalid option|unrecognised option') {
        return 'plink forsto ikke et flagg — for gammel plink-versjon? Oppdater PuTTY fra https://www.putty.org'
    }
    if ($Feil -match 'Server unexpectedly closed|Disconnected') {
        return 'AP-en lukket forbindelsen — for mange samtidige SSH-økter, eller kommandoen støttes ikke over SSH-exec'
    }
    if ($Feil -match 'not cached|host key') {
        if ($HostKeyGodta) {
            return 'vertsnøkkelen ble ikke lagret selv med -HostKeyGodta — koble til AP-en én gang manuelt (plink -ssh ' + $Bruker + '@<ip>) og svar y'
        }
        return 'vertsnøkkelen er ikke lagret i PuTTY-cachen — koble til AP-en én gang manuelt (plink -ssh ' + $Bruker + '@<ip>) og svar y, eller kjør med -HostKeyGodta'
    }
    return ''
}

function Test-TcpPort {
    # TCP-connect med tidsavbrudd (BeginConnect + WaitOne). Endrer ingenting.
    param([string]$Vert, [int]$Port = 22, [int]$TimeoutMs = 3000)
    $res = [pscustomobject]@{ Ok = $false; Ms = $null; Feil = '' }
    $tc = $null
    try {
        $tc = New-Object System.Net.Sockets.TcpClient
        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        $ar = $tc.BeginConnect($Vert, $Port, $null, $null)
        if (-not $ar.AsyncWaitHandle.WaitOne($TimeoutMs)) {
            $res.Feil = ("tidsavbrudd etter {0} ms" -f $TimeoutMs)
            try { $tc.Close() } catch { }
            return $res
        }
        $tc.EndConnect($ar)
        $sw.Stop()
        $res.Ok = $true
        $res.Ms = [math]::Round($sw.Elapsed.TotalMilliseconds, 1)
    } catch {
        $m = Get-Feilmelding $_
        if ($m -match 'refused|avvist') { $res.Feil = 'tilkobling avvist (port 22 lukket)' }
        elseif ($m -match 'No such host|not known|kunne ikke løses|could not be resolved') { $res.Feil = 'navnet kunne ikke slås opp i DNS' }
        else { $res.Feil = $m }
    } finally {
        if ($null -ne $tc) { try { $tc.Close() } catch { } }
    }
    return $res
}

# ------------------------------------------------------------------------------------
# Tolkning av AP-utdata (show version, show capwap client, show station)
# ------------------------------------------------------------------------------------
function Get-KommandoUtdata {
    param($Res, [string]$Monster)
    foreach ($k in $Res.Kommandoer) {
        if ($k.Status -eq 'SKIP') { continue }
        if ($k.Kommando -match $Monster) { return [string]$k.Utdata }
    }
    return ''
}

function Get-ApSammendrag {
    # Fyller Versjon, Plattform, Oppetid, Capwap, CapwapOk og Klienter ut fra lagret utdata.
    param($Res)
    $ver = Get-KommandoUtdata $Res '^show\s+version\b'
    if ($ver) {
        if ($ver -match '(?i)(HiveOS|IQ\s*Engine)\s*:?\s*v?(\d+(?:\.\d+)+[A-Za-z0-9]*)') {
            # Kopier gruppene før neste -match (den overskriver $Matches)
            $navn = [string]$Matches[1]
            $nummer = [string]$Matches[2]
            if ($navn -match '(?i)^IQ') { $navn = 'IQ Engine' } else { $navn = 'HiveOS' }
            $Res.Versjon = ('{0} {1}' -f $navn, $nummer)
        } elseif ($ver -match '(?im)^\s*Version\s*:\s*(.+?)\s*$') {
            $Res.Versjon = $Matches[1]
        }
        if ($ver -match '(?im)^\s*Platform\s*:\s*(.+?)\s*$') { $Res.Plattform = $Matches[1] }
        if ($ver -match '(?im)^\s*Uptime\s*:\s*(.+?)\s*$') { $Res.Oppetid = $Matches[1] }
        elseif ($ver -match '(?im)\bup\s+(\d+\s+days?.*?)\s*$') { $Res.Oppetid = $Matches[1] }
    }
    $cap = Get-KommandoUtdata $Res '^show\s+capwap\s+client\b'
    if ($cap) {
        $tekst = ''
        if ($cap -match '(?im)^\s*RUN\s*state\s*:\s*(.+?)\s*$') { $tekst = $Matches[1] }
        elseif ($cap -match '(?im)^.*\bconnected\b.*$') { $tekst = $Matches[0].Trim() }
        elseif ($cap -match '(?im)^.*\bRUN\b.*$') { $tekst = $Matches[0].Trim() }
        if ($tekst) {
            $Res.Capwap = $tekst
            if ($tekst -match '(?i)\bconnected\b' -and $tekst -notmatch '(?i)not\s+connected|disconnected') { $Res.CapwapOk = $true }
            else { $Res.CapwapOk = $false }
        } else {
            $Res.Capwap = 'ukjent (fant ikke RUN state)'
            $Res.CapwapOk = $false
        }
    }
    $sta = Get-KommandoUtdata $Res '^show\s+station\b'
    if ($sta) {
        $antall = 0
        foreach ($linje in ($sta -split "`r?`n")) {
            if ($linje -match '(?i)\b[0-9a-f]{4}:[0-9a-f]{4}:[0-9a-f]{4}\b|\b(?:[0-9a-f]{2}[:-]){5}[0-9a-f]{2}\b') { $antall++ }
        }
        $Res.Klienter = $antall
    }
}

# ------------------------------------------------------------------------------------
# Per AP: nåbarhet, vertsnøkkel, kommandoer, filer
# ------------------------------------------------------------------------------------
function New-ApResultat {
    param($Ap)
    return [pscustomobject]@{
        Navn = [string]$Ap.Navn; Ip = [string]$Ap.Ip; Mappe = ''; MappeNavn = ''
        Naabar = $false; NaabarMs = $null; NaabarFeil = ''
        Versjon = ''; Plattform = ''; Oppetid = ''; Capwap = ''; CapwapOk = $null; Klienter = $null
        Feil = (New-Object System.Collections.Generic.List[string])
        Kommandoer = (New-Object System.Collections.Generic.List[object])
        AntallOk = 0; AntallFeil = 0; AntallTidsavbrudd = 0; AntallFiltrert = 0; Sekunder = 0.0
    }
}

function Invoke-ApStatus {
    param($Ap)
    $res = New-ApResultat $Ap
    Write-Overskrift ("AP: {0} ({1})" -f $res.Navn, $res.Ip)
    $swAp = [System.Diagnostics.Stopwatch]::StartNew()

    # Nåbarhet: TCP 22 med 3 s tidsavbrudd
    $tcp = Test-TcpPort -Vert $res.Ip -Port 22 -TimeoutMs 3000
    if ($tcp.Ok) {
        $res.Naabar = $true
        $res.NaabarMs = $tcp.Ms
        Write-Status 'PASS' $res.Navn 'TCP 22 (SSH)' ("nåbar, {0} ms" -f (Format-Tall $tcp.Ms 1)) '3 s'
    } else {
        $res.NaabarFeil = $tcp.Feil
        $res.Feil.Add(("TCP 22 ikke nåbar: {0}" -f $tcp.Feil))
        Write-Status 'FAIL' $res.Navn 'TCP 22 (SSH)' ("ikke nåbar — {0}" -f $tcp.Feil) '3 s'
    }
    if ($KunNaabar) { $swAp.Stop(); $res.Sekunder = [math]::Round($swAp.Elapsed.TotalSeconds, 1); return $res }
    if (-not $res.Naabar) {
        Write-Status 'SKIP' $res.Navn 'plink' 'hoppet over — AP-en er ikke nåbar på TCP 22'
        $swAp.Stop(); $res.Sekunder = [math]::Round($swAp.Elapsed.TotalSeconds, 1)
        return $res
    }

    # Mappe per AP
    $res.MappeNavn = (ConvertTo-Filnavn $res.Navn) + '_' + (ConvertTo-Filnavn $res.Ip)
    $res.Mappe = Join-Path $script:RapportSti $res.MappeNavn
    try { $null = New-Item -ItemType Directory -Path $res.Mappe -Force -ErrorAction Stop } catch {
        $res.Feil.Add(("kunne ikke opprette mappen {0}: {1}" -f $res.Mappe, (Get-Feilmelding $_)))
        Write-Status 'FAIL' $res.Navn 'rapportmappe' (Get-Feilmelding $_)
        $swAp.Stop(); $res.Sekunder = [math]::Round($swAp.Elapsed.TotalSeconds, 1)
        return $res
    }

    $all = New-Object System.Text.StringBuilder
    $null = $all.AppendLine(("# ap-status {0} — {1} ({2}) — {3}" -f $script:Versjon, $res.Navn, $res.Ip, $script:StartTid.ToString('yyyy-MM-dd HH:mm:ss')))
    $null = $all.AppendLine(("# plink: {0}" -f $script:PlinkExe))
    $null = $all.AppendLine(("# argumenter: {0}" -f (Get-PlinkArgumenter -Ip $res.Ip -Kommando '<kommando>' -Batch $true -Maskert $true)))
    $null = $all.AppendLine('# Endrer ingenting — kun lesing.')
    $null = $all.AppendLine('')

    $avbrutt = $false

    # Valgfritt: én forbindelse uten -batch med «y» på standard inn for å lagre vertsnøkkelen
    if ($HostKeyGodta) {
        $utPre = Join-Path $res.Mappe '_vertsnokkel.txt'
        $feilPre = Join-Path $res.Mappe '_vertsnokkel.stderr.txt'
        $argPre = Get-PlinkArgumenter -Ip $res.Ip -Kommando 'show version' -Batch $false
        $pre = Invoke-Prosess -Exe $script:PlinkExe -Argumenter $argPre -UtFil $utPre -FeilFil $feilPre -TimeoutSekunder $TimeoutSek -InnFil $script:SvarFil
        $null = $all.AppendLine(("=== vertsnøkkel (plink uten -batch, «y» på stdin) === (exit {0}, {1} s)" -f $pre.ExitCode, (Format-Tall $pre.Sekunder 1)))
        if ($pre.Utdata) { $null = $all.AppendLine($pre.Utdata.TrimEnd()) }
        if ($pre.Feil) { $null = $all.AppendLine('--- stderr ---'); $null = $all.AppendLine($pre.Feil.TrimEnd()) }
        if ($pre.Melding) { $null = $all.AppendLine('--- melding ---'); $null = $all.AppendLine($pre.Melding) }
        $null = $all.AppendLine('')
        if ($pre.TidsAvbrutt) {
            $res.Feil.Add(("vertsnøkkel-forbindelse: {0}" -f $pre.Melding))
            Write-Status 'FAIL' $res.Navn 'vertsnøkkel (plink uten -batch)' $pre.Melding ("{0} s" -f $TimeoutSek)
            $avbrutt = $true
        } elseif (-not $pre.Startet) {
            $res.Feil.Add(("vertsnøkkel-forbindelse: {0}" -f $pre.Melding))
            Write-Status 'FAIL' $res.Navn 'vertsnøkkel (plink uten -batch)' $pre.Melding
            $avbrutt = $true
        } elseif ($pre.Feil -match 'FATAL ERROR|Connection abandoned|Access denied|Unable to authenticate') {
            $hint = Get-PlinkHint $pre.Feil
            $kort = (($pre.Feil -split "`r?`n") | Where-Object { $_ -match 'FATAL|denied|abandoned|authenticate' } | Select-Object -First 1)
            if (-not $kort) { $kort = $pre.Feil.Trim() }
            $res.Feil.Add(("vertsnøkkel-forbindelse: {0}" -f $kort))
            $melding = [string]$kort
            if ($hint) { $melding = ("{0} — {1}" -f $kort, $hint) }
            Write-Status 'FAIL' $res.Navn 'vertsnøkkel (plink uten -batch)' $melding
            $avbrutt = $true
        } elseif ($pre.Feil -match 'Store key in cache|not cached|host key') {
            Write-Status 'INFO' $res.Navn 'vertsnøkkel' ("ukjent vertsnøkkel godtatt og lagret i PuTTY-cachen (uten verifisering), {0} s" -f (Format-Tall $pre.Sekunder 1))
        } else {
            Write-Status 'INFO' $res.Navn 'vertsnøkkel' ("vertsnøkkel var allerede lagret — forbindelsen fungerer, {0} s" -f (Format-Tall $pre.Sekunder 1))
        }
    }

    # Kommandoer
    $brukteFilnavn = @{}
    foreach ($kmd in $script:KommandoListe) {
        $post = [pscustomobject]@{
            Kommando = $kmd; Status = 'SKIP'; ExitCode = $null; Sekunder = 0.0; Linjer = 0; Fil = ''; Melding = ''; Utdata = ''; Stderr = ''
        }
        $res.Kommandoer.Add($post)

        if (-not (Test-KommandoTrygg $kmd)) {
            if (-not $TillatEndringer) {
                $post.Status = 'SKIP'
                $post.Melding = 'stoppet av sikkerhetsfilteret (kan endre konfigurasjon) — kjøres bare med -TillatEndringer'
                $res.AntallFiltrert++
                Write-Status 'SKIP' $res.Navn $kmd $post.Melding
                $null = $all.AppendLine(("=== {0} === [SKIP] {1}" -f $kmd, $post.Melding))
                $null = $all.AppendLine('')
                continue
            }
            Write-Status 'WARN' $res.Navn $kmd 'kommandolinjen treffer sikkerhetsfilteret, men kjøres fordi -TillatEndringer er angitt'
        }
        if ($avbrutt) {
            $post.Status = 'SKIP'
            $post.Melding = 'hoppet over etter tilkoblingsfeil mot AP-en'
            Write-Status 'SKIP' $res.Navn $kmd $post.Melding
            $null = $all.AppendLine(("=== {0} === [SKIP] {1}" -f $kmd, $post.Melding))
            $null = $all.AppendLine('')
            continue
        }

        $base = ConvertTo-Filnavn $kmd
        $filnavn = $base
        $n = 1
        while ($brukteFilnavn.ContainsKey($filnavn)) { $n++; $filnavn = ('{0}_{1}' -f $base, $n) }
        $brukteFilnavn[$filnavn] = $true
        $utFil = Join-Path $res.Mappe ($filnavn + '.txt')
        $feilFil = Join-Path $res.Mappe ($filnavn + '.stderr.txt')
        $post.Fil = $utFil

        $argTekst = Get-PlinkArgumenter -Ip $res.Ip -Kommando $kmd -Batch $true
        $r = Invoke-Prosess -Exe $script:PlinkExe -Argumenter $argTekst -UtFil $utFil -FeilFil $feilFil -TimeoutSekunder $TimeoutSek
        $post.ExitCode = $r.ExitCode
        $post.Sekunder = $r.Sekunder
        $post.Utdata = $r.Utdata
        $post.Stderr = $r.Feil
        $linjer = @()
        if ($r.Utdata) { $linjer = @(($r.Utdata -split "`r?`n") | Where-Object { $_.Trim() -ne '' }) }
        $post.Linjer = $linjer.Count
        $tid = Format-Tall $r.Sekunder 1

        if ($r.TidsAvbrutt) {
            $post.Status = 'FAIL'
            $post.Melding = $r.Melding
            $res.AntallTidsavbrudd++
            $res.AntallFeil++
            $res.Feil.Add(("{0}: {1}" -f $kmd, $r.Melding))
            Write-Status 'FAIL' $res.Navn $kmd $r.Melding ("{0} s" -f $TimeoutSek)
        } elseif (-not $r.Startet) {
            $post.Status = 'FAIL'
            $post.Melding = $r.Melding
            $res.AntallFeil++
            $res.Feil.Add(("{0}: {1}" -f $kmd, $r.Melding))
            Write-Status 'FAIL' $res.Navn $kmd $r.Melding
            $avbrutt = $true
        } elseif ($r.Feil -match 'FATAL ERROR|Connection abandoned' -or ($r.ExitCode -ne 0 -and $post.Linjer -eq 0)) {
            $post.Status = 'FAIL'
            $kort = ''
            if ($r.Feil) { $kort = [string](($r.Feil -split "`r?`n") | Where-Object { $_ -match 'FATAL|denied|abandoned|error|Error|cached' } | Select-Object -First 1) }
            if (-not $kort) { $kort = ("plink avsluttet med kode {0} uten utdata" -f $r.ExitCode) }
            $hint = Get-PlinkHint $r.Feil
            $post.Melding = $kort
            if ($hint) { $post.Melding = ("{0} — {1}" -f $kort, $hint) }
            $res.AntallFeil++
            $res.Feil.Add(("{0}: {1}" -f $kmd, $post.Melding))
            Write-Status 'FAIL' $res.Navn $kmd $post.Melding ("{0} s" -f $TimeoutSek)
            if ($r.Feil -match $script:AvbruddRegex) {
                $avbrutt = $true
                Write-Status 'INFO' $res.Navn 'plink' 'tilkoblingsfeil — resten av kommandoene for denne AP-en hoppes over'
            }
        } elseif ($post.Linjer -eq 0) {
            $post.Status = 'WARN'
            $post.Melding = ("ingen utdata (exit {0}, {1} s)" -f $r.ExitCode, $tid)
            Write-Status 'WARN' $res.Navn $kmd $post.Melding ("{0} s" -f $TimeoutSek)
        } elseif ($post.Linjer -le 3 -and $linjer[0] -match '^\s*(ERROR|Error|error|Invalid|invalid|Unknown|unknown|Unrecognized|Ambiguous|%)') {
            $post.Status = 'WARN'
            $post.Melding = ("AP-en svarte med feil: {0}" -f $linjer[0].Trim())
            Write-Status 'WARN' $res.Navn $kmd $post.Melding
        } else {
            $post.Status = 'PASS'
            $post.Melding = ("{0} linjer, {1} s" -f $post.Linjer, $tid)
            $res.AntallOk++
            Write-Status 'PASS' $res.Navn $kmd $post.Melding ("{0} s" -f $TimeoutSek)
        }

        $null = $all.AppendLine(("=== {0} === [{1}] exit {2}, {3} s" -f $kmd, $post.Status, $r.ExitCode, $tid))
        if ($r.Utdata) { $null = $all.AppendLine($r.Utdata.TrimEnd()) }
        if ($r.Feil) { $null = $all.AppendLine('--- stderr ---'); $null = $all.AppendLine($r.Feil.TrimEnd()) }
        if ($post.Melding -and $post.Status -ne 'PASS') { $null = $all.AppendLine('--- melding ---'); $null = $all.AppendLine($post.Melding) }
        $null = $all.AppendLine('')

        # Tomme stderr-filer fjernes for ryddighet (bare filer skriptet selv har laget i denne kjøringen)
        if (-not $r.Feil) { try { if (Test-Path -LiteralPath $feilFil) { Remove-Item -LiteralPath $feilFil -Force -ErrorAction SilentlyContinue } } catch { } }
    }

    $null = Write-Tekstfil (Join-Path $res.Mappe 'all.txt') $all.ToString()

    # Sammendrag fra utdata
    Get-ApSammendrag $res
    $deler = New-Object System.Collections.Generic.List[string]
    if ($res.Versjon) { $deler.Add(("versjon {0}" -f $res.Versjon)) }
    if ($res.Plattform) { $deler.Add(("plattform {0}" -f $res.Plattform)) }
    if ($res.Oppetid) { $deler.Add(("oppetid {0}" -f $res.Oppetid)) }
    if ($null -ne $res.Klienter) { $deler.Add(("{0} klienter" -f $res.Klienter)) }
    if ($deler.Count -gt 0) { Write-Status 'INFO' $res.Navn 'sammendrag' ($deler.ToArray() -join ', ') }
    elseif ($res.AntallOk -gt 0) { Write-Status 'INFO' $res.Navn 'sammendrag' 'fant ikke versjon/oppetid/klienter i utdata (sjekk all.txt)' }
    if ($res.Capwap) {
        if ($res.CapwapOk) { Write-Status 'PASS' $res.Navn 'CAPWAP mot ExtremeCloudIQ' $res.Capwap 'connected' }
        else { Write-Status 'WARN' $res.Navn 'CAPWAP mot ExtremeCloudIQ' ("{0} — AP-en trenger DNS, UDP 12222 og TCP 443 mot XIQ" -f $res.Capwap) 'connected' }
    }

    $swAp.Stop()
    $res.Sekunder = [math]::Round($swAp.Elapsed.TotalSeconds, 1)
    Write-Status 'INFO' $res.Navn 'filer' ("{0} ({1} kommandoer OK, {2} feil, {3} tidsavbrudd, {4} filtrert, {5} s)" -f $res.Mappe, $res.AntallOk, $res.AntallFeil, $res.AntallTidsavbrudd, $res.AntallFiltrert, (Format-Tall $res.Sekunder 1))
    return $res
}

# ------------------------------------------------------------------------------------
# Oppsummering (oppsummering.md + konsoll)
# ------------------------------------------------------------------------------------
function Get-FeilTekst {
    param($Res, [int]$MaksLengde = 160)
    if ($Res.Feil.Count -eq 0) { return '' }
    $forste = [string]$Res.Feil[0]
    if ($forste.Length -gt $MaksLengde) { $forste = $forste.Substring(0, $MaksLengde) + '…' }
    if ($Res.Feil.Count -gt 1) { $forste = ('{0} (+{1} til)' -f $forste, ($Res.Feil.Count - 1)) }
    return $forste
}

function Write-Oppsummering {
    param([string]$Avslutning = '')
    $sb = New-Object System.Text.StringBuilder
    $antall = $script:Resultater.Count
    $naabare = @($script:Resultater | Where-Object { $_.Naabar }).Count
    $medFeil = @($script:Resultater | Where-Object { $_.Feil.Count -gt 0 }).Count
    $kmdOk = 0; $kmdFeil = 0; $kmdTid = 0; $kmdFiltrert = 0
    foreach ($r in $script:Resultater) { $kmdOk += $r.AntallOk; $kmdFeil += $r.AntallFeil; $kmdTid += $r.AntallTidsavbrudd; $kmdFiltrert += $r.AntallFiltrert }
    $modus = 'full (plink)'
    if ($KunNaabar) { $modus = 'kun nåbarhet (TCP 22, uten plink)' }
    $paalogging = ("bruker {0}, passord via -pw" -f $Bruker)
    if ($Session) { $paalogging = ("lagret PuTTY-økt «{0}» (ingen -pw)" -f $Session) }
    elseif ($script:Passord -eq '') { $paalogging = ("bruker {0}, tomt passord (ingen -pw — Pageant/nøkkel)" -f $Bruker) }
    $vertsnokkel = '-batch (vertsnøkler må være lagret fra før)'
    if ($HostKeyGodta) { $vertsnokkel = '-HostKeyGodta (ukjente vertsnøkler godtas automatisk uten verifisering)' }
    $filter = 'aktivt (config|reset|reboot|save|write|erase|clear|delete|no |set  stoppes)'
    if ($TillatEndringer) { $filter = 'AV (-TillatEndringer) — kommandoer som kan endre konfigurasjon ble tillatt' }
    $psTekst = ('{0} {1}' -f $script:PsUtgave, $PSVersionTable.PSVersion.ToString())
    $osTekst = ''
    try { $osTekst = [string][System.Environment]::OSVersion.VersionString } catch { $osTekst = 'ukjent' }

    $null = $sb.AppendLine(("# ap-status {0} — oppsummering ({1})" -f $script:Versjon, $script:StartTid.ToString('yyyy-MM-dd HH:mm:ss')))
    $null = $sb.AppendLine('')
    $null = $sb.AppendLine('Endrer ingenting — kun lesing og målinger. Lim inn denne filen i chatten for analyse; legg ved all.txt for AP-er med feil.')
    $null = $sb.AppendLine('')
    $null = $sb.AppendLine('## Kjøring')
    $null = $sb.AppendLine('')
    $null = $sb.AppendLine(("- Tid: {0} — varighet {1} s" -f $script:StartTid.ToString('yyyy-MM-dd HH:mm:ss'), (Format-Tall ((Get-Date) - $script:StartTid).TotalSeconds 0)))
    $null = $sb.AppendLine(("- Kjørt fra: {0} ({1}, PowerShell {2})" -f $script:Vertsnavn, $osTekst, $psTekst))
    $null = $sb.AppendLine(("- Modus: {0}" -f $modus))
    $null = $sb.AppendLine(("- AP-liste: {0} ({1} AP-er)" -f $script:ApListeSti, $antall))
    if (-not $KunNaabar) {
        $null = $sb.AppendLine(("- Kommandofil: {0} ({1} kommandoer)" -f $script:KommandoSti, @($script:KommandoListe).Count))
        $null = $sb.AppendLine(("- plink: {0} ({1})" -f $script:PlinkExe, $script:PlinkVersjon))
        $null = $sb.AppendLine(("- Pålogging: {0}" -f $paalogging))
        $null = $sb.AppendLine(("- Vertsnøkler: {0}" -f $vertsnokkel))
        $null = $sb.AppendLine(("- Sikkerhetsfilter: {0}" -f $filter))
        $null = $sb.AppendLine(("- Tidsavbrudd per kommando: {0} s" -f $TimeoutSek))
    }
    $null = $sb.AppendLine(("- Rapportmappe: {0}" -f $script:RapportSti))
    if ($Avslutning) { $null = $sb.AppendLine(("- Avslutning: {0}" -f $Avslutning)) }
    $null = $sb.AppendLine('')
    $null = $sb.AppendLine('## Oversikt')
    $null = $sb.AppendLine('')
    $null = $sb.AppendLine('| navn | ip | nåbar | versjon | oppetid | CAPWAP-status | antall klienter | feil |')
    $null = $sb.AppendLine('|---|---|---|---|---|---|---|---|')
    foreach ($r in $script:Resultater) {
        $naabar = 'nei'
        if ($r.Naabar) {
            $naabar = 'ja'
            if ($null -ne $r.NaabarMs) { $naabar = ('ja ({0} ms)' -f (Format-Tall $r.NaabarMs 0)) }
        }
        $klienter = '–'
        if ($null -ne $r.Klienter) { $klienter = [string]$r.Klienter }
        $null = $sb.AppendLine(('| {0} | {1} | {2} | {3} | {4} | {5} | {6} | {7} |' -f (ConvertTo-MdCelle $r.Navn), (ConvertTo-MdCelle $r.Ip), $naabar, (ConvertTo-MdCelle $r.Versjon), (ConvertTo-MdCelle $r.Oppetid), (ConvertTo-MdCelle $r.Capwap), $klienter, (ConvertTo-MdCelle (Get-FeilTekst $r))))
    }
    $null = $sb.AppendLine('')
    $null = $sb.AppendLine(("Totalt: {0} AP-er, {1} nåbare på TCP 22, {2} med feil." -f $antall, $naabare, $medFeil))
    if (-not $KunNaabar) {
        $null = $sb.AppendLine(("Kommandoer: {0} OK, {1} feil, {2} tidsavbrudd, {3} stoppet av sikkerhetsfilteret." -f $kmdOk, $kmdFeil, $kmdTid, $kmdFiltrert))
    }
    $null = $sb.AppendLine('')
    $null = $sb.AppendLine(("Statuslinjer: PASS {0}, WARN {1}, FAIL {2}, SKIP {3}, INFO {4}." -f $script:Teller['PASS'], $script:Teller['WARN'], $script:Teller['FAIL'], $script:Teller['SKIP'], $script:Teller['INFO']))
    $null = $sb.AppendLine('')

    if (-not $KunNaabar) {
        $null = $sb.AppendLine('## Detaljer per AP')
        $null = $sb.AppendLine('')
        foreach ($r in $script:Resultater) {
            $null = $sb.AppendLine(("### {0} ({1})" -f $r.Navn, $r.Ip))
            $null = $sb.AppendLine('')
            if (-not $r.Naabar) {
                $null = $sb.AppendLine(("- Ikke nåbar på TCP 22: {0}. Ingen kommandoer kjørt." -f $r.NaabarFeil))
                $null = $sb.AppendLine('')
                continue
            }
            if ($r.Mappe) { $null = $sb.AppendLine(("- Mappe: {0}" -f $r.Mappe)) }
            if ($r.Plattform) { $null = $sb.AppendLine(("- Plattform: {0}" -f $r.Plattform)) }
            $null = $sb.AppendLine(("- Kommandoer: {0} OK, {1} feil, {2} tidsavbrudd, {3} stoppet av filter, {4} s totalt" -f $r.AntallOk, $r.AntallFeil, $r.AntallTidsavbrudd, $r.AntallFiltrert, (Format-Tall $r.Sekunder 1)))
            if ($r.Feil.Count -gt 0) {
                $null = $sb.AppendLine('- Feil:')
                foreach ($f in $r.Feil) { $null = $sb.AppendLine(("  - {0}" -f $f)) }
            }
            $null = $sb.AppendLine('')
            if ($r.Kommandoer.Count -gt 0) {
                $null = $sb.AppendLine('| kommando | status | exit | tid (s) | linjer | melding |')
                $null = $sb.AppendLine('|---|---|---|---|---|---|')
                foreach ($k in $r.Kommandoer) {
                    $exit = '–'
                    if ($null -ne $k.ExitCode) { $exit = [string]$k.ExitCode }
                    $null = $sb.AppendLine(('| {0} | {1} | {2} | {3} | {4} | {5} |' -f (ConvertTo-MdCelle $k.Kommando), $k.Status, $exit, (Format-Tall $k.Sekunder 1), $k.Linjer, (ConvertTo-MdCelle $k.Melding)))
                }
                $null = $sb.AppendLine('')
            }
        }
        $null = $sb.AppendLine('## Kommandoer som ble forsøkt')
        $null = $sb.AppendLine('')
        $null = $sb.AppendLine('```')
        foreach ($k in $script:KommandoListe) { $null = $sb.AppendLine($k) }
        $null = $sb.AppendLine('```')
        $null = $sb.AppendLine('')
        $null = $sb.AppendLine('## Tolkning')
        $null = $sb.AppendLine('')
        $null = $sb.AppendLine('- CAPWAP-status skal være «Connected …» mot ExtremeCloudIQ. Ellers: sjekk at AP-en får DNS-svar, og at UDP 12222 og TCP 443 er åpne ut mot redirector.aerohive.com / extremecloudiq.com (tidligere hendelse: «CAPWAP connection was lost»).')
        $null = $sb.AppendLine('- Kort oppetid på én AP kan bety strømbrudd/PoE-problem på svitsjporten eller omstart fra XIQ; se «show logging buffered».')
        $null = $sb.AppendLine('- «show acsp» / «show acsp neighbor» viser kanal, effekt og naboer (kanalvalg og støy); «show station» viser klienter med RSSI og rate; «show roaming cache» viser naboer for roaming.')
        $null = $sb.AppendLine('- «show lldp neighbor» viser hvilken svitsj og port AP-en henger på (nyttig når svitsjmodell/port skal dokumenteres).')
        $null = $sb.AppendLine('')
    }

    $sti = Join-Path $script:RapportSti 'oppsummering.md'
    if (Write-Tekstfil $sti $sb.ToString()) {
        Write-Status 'INFO' 'Oppsummering' 'rapport' $sti
    }
    return $sti
}

function Show-KonsollTabell {
    $rader = New-Object System.Collections.Generic.List[object]
    foreach ($r in $script:Resultater) {
        $naabar = 'nei'
        if ($r.Naabar) { $naabar = 'ja' }
        $klienter = '–'
        if ($null -ne $r.Klienter) { $klienter = [string]$r.Klienter }
        $rader.Add([pscustomobject]@{
            'navn' = $r.Navn; 'ip' = $r.Ip; 'nåbar' = $naabar; 'versjon' = $r.Versjon; 'oppetid' = $r.Oppetid
            'CAPWAP' = $r.Capwap; 'klienter' = $klienter; 'feil' = (Get-FeilTekst $r 70)
        })
    }
    if ($rader.Count -eq 0) { return }
    try {
        $tekst = ($rader.ToArray() | Format-Table -Property 'navn', 'ip', 'nåbar', 'versjon', 'oppetid', 'CAPWAP', 'klienter', 'feil' -AutoSize | Out-String -Width 220)
        foreach ($linje in ($tekst -split "`r?`n")) { if ($linje.Trim() -ne '') { Write-Melding $linje 'Gray' } }
    } catch { }
}

# ------------------------------------------------------------------------------------
# Hovedprogram
# ------------------------------------------------------------------------------------
$avslutningskode = 0
try {
    Write-Overskrift ("ap-status {0} — READ-ONLY status fra Extreme/Aerohive AP-er via plink (SSH)" -f $script:Versjon)
    Write-Melding 'Endrer ingenting — kun lesing og målinger. Ctrl-C avbryter.' 'Gray'
    Write-Overskrift 'Oppsett'

    # AP-liste
    $script:ApListeSti = Find-Inndatafil -Sti $ApListe -Standardnavn 'ap-liste.txt' -ErStandard (-not $PSBoundParameters.ContainsKey('ApListe'))
    if (-not $script:ApListeSti) {
        Write-Status 'FAIL' 'Oppsett' 'AP-liste' ("fant ikke {0}" -f $ApListe)
        Write-Melding ''
        Write-Melding ("Fant ikke AP-listen «{0}». Kopier ap-liste.eksempel.txt til ap-liste.txt (samme mappe som skriptet)," -f $ApListe) 'Yellow'
        Write-Melding 'rediger navn og IP-adresser (én AP per linje: navn;ip), eller angi filen med -ApListe <sti>.' 'Yellow'
        exit 3
    }
    $apListeData = @(Read-ApListe $script:ApListeSti)
    if ($apListeData.Count -eq 0) {
        Write-Status 'FAIL' 'Oppsett' 'AP-liste' ("{0} inneholder ingen AP-er (forventet én per linje: navn;ip)" -f $script:ApListeSti)
        exit 3
    }
    Write-Status 'INFO' 'Oppsett' 'AP-liste' ("{0} ({1} AP-er)" -f $script:ApListeSti, $apListeData.Count)

    if ($KunNaabar) {
        Write-Status 'INFO' 'Oppsett' 'modus' 'kun nåbarhet (TCP 22, 3 s) — plink brukes ikke, ingen passord'
    } else {
        # plink
        $script:PlinkExe = Find-Plink $PlinkPath
        if (-not $script:PlinkExe) {
            Write-Status 'FAIL' 'Oppsett' 'plink.exe' 'ikke funnet'
            Write-Melding ''
            if ($PlinkPath) {
                Write-Melding ("Fant ikke plink.exe på angitt sti: {0}" -f $PlinkPath) 'Yellow'
            } else {
                Write-Melding 'Fant ikke plink.exe (PuTTY). Søkte i PATH, C:\Program Files\PuTTY\plink.exe, C:\Program Files (x86)\PuTTY\plink.exe' 'Yellow'
                Write-Melding 'og i mappen skriptet ligger i.' 'Yellow'
            }
            Write-Melding 'Last ned PuTTY (inkluderer plink.exe) fra https://www.putty.org og installer, eller legg plink.exe ved siden av' 'Yellow'
            Write-Melding 'skriptet, eller angi stien med -PlinkPath "C:\sti\til\plink.exe". Bruk -KunNaabar for å teste AP-listen uten plink.' 'Yellow'
            exit 2
        }
        Write-Status 'INFO' 'Oppsett' 'plink.exe' $script:PlinkExe

        # Kommandofil
        $script:KommandoSti = Find-Inndatafil -Sti $Kommandoer -Standardnavn 'ap-kommandoer.txt' -ErStandard (-not $PSBoundParameters.ContainsKey('Kommandoer'))
        if (-not $script:KommandoSti) {
            Write-Status 'FAIL' 'Oppsett' 'kommandofil' ("fant ikke {0}" -f $Kommandoer)
            Write-Melding ("Fant ikke kommandofilen «{0}». Den følger med i nettsjekk-mappen (ap-kommandoer.txt) — angi sti med -Kommandoer." -f $Kommandoer) 'Yellow'
            exit 3
        }
        $script:KommandoListe = @(Read-Kommandoer $script:KommandoSti)
        if ($script:KommandoListe.Count -eq 0) {
            Write-Status 'FAIL' 'Oppsett' 'kommandofil' ("{0} inneholder ingen kommandoer" -f $script:KommandoSti)
            exit 3
        }
        $usikre = @($script:KommandoListe | Where-Object { -not (Test-KommandoTrygg $_) })
        Write-Status 'INFO' 'Oppsett' 'kommandofil' ("{0} ({1} kommandoer)" -f $script:KommandoSti, $script:KommandoListe.Count)
        if ($usikre.Count -gt 0) {
            if ($TillatEndringer) {
                Write-Status 'WARN' 'Oppsett' 'sikkerhetsfilter' ("AV (-TillatEndringer): {0} kommandolinje(r) som kan endre konfigurasjon vil bli kjørt: {1}" -f $usikre.Count, ($usikre -join ' | '))
            } else {
                Write-Status 'INFO' 'Oppsett' 'sikkerhetsfilter' ("{0} kommandolinje(r) stoppes fordi de kan endre konfigurasjon: {1}" -f $usikre.Count, ($usikre -join ' | '))
            }
        }

        # plink-versjon (plink -V er lesende og rask)
        try {
            $tmpUt = Join-Path ([System.IO.Path]::GetTempPath()) ('ap-status-plinkv-' + $PID + '.txt')
            $tmpFeil = Join-Path ([System.IO.Path]::GetTempPath()) ('ap-status-plinkv-' + $PID + '.stderr.txt')
            $pv = Invoke-Prosess -Exe $script:PlinkExe -Argumenter '-V' -UtFil $tmpUt -FeilFil $tmpFeil -TimeoutSekunder 10
            $vtekst = (($pv.Utdata + "`n" + $pv.Feil) -split "`r?`n" | Where-Object { $_ -match 'plink|Release|Snapshot|Unidentified' } | Select-Object -First 1)
            if ($vtekst) { $script:PlinkVersjon = ([string]$vtekst).Trim() } else { $script:PlinkVersjon = 'versjon ukjent' }
            if ($pv.TidsAvbrutt) { $script:PlinkVersjon = 'svarte ikke på -V (tidsavbrudd)' }
            Remove-Item -LiteralPath $tmpUt, $tmpFeil -Force -ErrorAction SilentlyContinue
        } catch { $script:PlinkVersjon = 'versjon ukjent' }
        Write-Status 'INFO' 'Oppsett' 'plink-versjon' $script:PlinkVersjon

        # Pålogging
        if ($Session) {
            Write-Status 'INFO' 'Oppsett' 'pålogging' ("lagret PuTTY-økt «{0}» (plink -load) — ingen -pw" -f $Session)
            if ($script:BrukerAngitt) { Write-Status 'INFO' 'Oppsett' 'bruker' ("{0} (overstyrer økten)" -f $Bruker) }
        } else {
            Write-Status 'INFO' 'Oppsett' 'bruker' $Bruker
            Write-Melding ''
            Write-Melding ("Passordet sendes til plink som -pw og er synlig i prosesslisten på denne PC-en mens hver kommando kjører." ) 'Yellow'
            Write-Melding 'Bedre: lagret PuTTY-økt med privat nøkkel og -Session <navn>. Tomt passord = ingen -pw (Pageant/nøkkel).' 'Yellow'
            $script:Passord = Read-Passord ("Passord for {0} på AP-ene" -f $Bruker)
            if ($script:Passord -eq '') { Write-Status 'INFO' 'Oppsett' 'passord' 'tomt — plink kjøres uten -pw (Pageant/nøkkel må da finnes)' }
            else { Write-Status 'INFO' 'Oppsett' 'passord' 'mottatt (holdes bare i minnet, skrives aldri til fil)' }
        }

        if ($HostKeyGodta) {
            Write-Status 'WARN' 'Oppsett' 'vertsnøkler' 'ukjente SSH-vertsnøkler godtas automatisk (uten verifisering) — én forbindelse uten -batch per AP'
        } else {
            Write-Status 'INFO' 'Oppsett' 'vertsnøkler' 'plink -batch: vertsnøkkelen til hver AP må være lagret fra før (koble til manuelt én gang, eller bruk -HostKeyGodta)'
        }
        Write-Status 'INFO' 'Oppsett' 'tidsavbrudd' ("{0} s per kommando" -f $TimeoutSek)
    }

    # Rapportmappe
    if (-not $Rapportmappe) { $Rapportmappe = Join-Path (Get-Location).Path ('ap-status-' + $script:Stempel) }
    $script:RapportSti = Resolve-Sti $Rapportmappe
    try { $null = New-Item -ItemType Directory -Path $script:RapportSti -Force -ErrorAction Stop } catch {
        Write-Status 'FAIL' 'Oppsett' 'rapportmappe' ("kunne ikke opprette {0}: {1}" -f $script:RapportSti, (Get-Feilmelding $_))
        exit 3
    }
    Write-Status 'INFO' 'Oppsett' 'rapportmappe' $script:RapportSti

    if ($HostKeyGodta -and -not $KunNaabar) {
        $script:SvarFil = Join-Path ([System.IO.Path]::GetTempPath()) ('ap-status-svar-' + $PID + '.txt')
        try { [System.IO.File]::WriteAllText($script:SvarFil, "y`n", [System.Text.Encoding]::ASCII) } catch {
            Write-Status 'WARN' 'Oppsett' 'vertsnøkler' ("kunne ikke lage svarfilen for «y»: {0} — -HostKeyGodta får ingen virkning" -f (Get-Feilmelding $_))
            $script:SvarFil = ''
        }
    }

    # Per AP
    foreach ($ap in $apListeData) {
        $r = Invoke-ApStatus $ap
        $script:Resultater.Add($r)
    }

    Write-Overskrift 'Oppsummering'
    $antall = $script:Resultater.Count
    $naabare = @($script:Resultater | Where-Object { $_.Naabar }).Count
    $medFeil = @($script:Resultater | Where-Object { $_.Feil.Count -gt 0 }).Count
    $status = 'PASS'
    if ($medFeil -gt 0) { $status = 'WARN' }
    if ($naabare -eq 0) { $status = 'FAIL' }
    Write-Status $status 'Oppsummering' 'AP-er' ("{0} totalt, {1} nåbare på TCP 22, {2} med feil" -f $antall, $naabare, $medFeil) 'alle nåbare uten feil'
    Show-KonsollTabell
    $null = Write-Oppsummering
    Write-Status 'INFO' 'Oppsummering' 'statuslinjer' ("PASS {0}, WARN {1}, FAIL {2}, SKIP {3}, INFO {4}, varighet {5} s" -f $script:Teller['PASS'], $script:Teller['WARN'], $script:Teller['FAIL'], $script:Teller['SKIP'], $script:Teller['INFO'], (Format-Tall ((Get-Date) - $script:StartTid).TotalSeconds 0))
    Write-Melding ''
    Write-Melding ("Ferdig. Lim inn {0} i chatten for analyse (og all.txt for AP-er med feil)." -f (Join-Path $script:RapportSti 'oppsummering.md')) 'Green'
} catch {
    $avslutningskode = 4
    $melding = Get-Feilmelding $_
    Write-Status 'FAIL' 'Oppsummering' 'uventet feil' $melding
    try { if ($null -ne $_.ScriptStackTrace) { Write-Melding ([string]$_.ScriptStackTrace) 'DarkGray' } } catch { }
    if ($script:RapportSti -and (Test-Path -LiteralPath $script:RapportSti)) {
        try { $null = Write-Oppsummering -Avslutning ("uventet feil: {0}" -f $melding) } catch { }
    }
} finally {
    $script:Passord = ''
    if ($script:SvarFil) { try { Remove-Item -LiteralPath $script:SvarFil -Force -ErrorAction SilentlyContinue } catch { } }
}
exit $avslutningskode
