# Configure une instance Minecraft (ATLauncher ou Prism Launcher) pour qu'elle
# synchronise automatiquement ses mods avec le pack packwiz du serveur.
# Compatible Windows PowerShell 5.1.

$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$PackUrl      = 'https://milograbie.github.io/aeronautics-pack/pack.toml'
$BootstrapUrl = 'https://github.com/packwiz/packwiz-installer-bootstrap/releases/download/v0.0.3/packwiz-installer-bootstrap.jar'
$McVersion    = '1.21.1'
$NeoVersion   = '21.1.264'
$Utf8NoBom    = New-Object System.Text.UTF8Encoding($false)

function Write-Step($msg) { Write-Host "`n==> $msg" -ForegroundColor Cyan }
function Write-Warn($msg) { Write-Host "/!\ $msg" -ForegroundColor Yellow }
function Fail($msg) { Write-Host "`nERREUR : $msg" -ForegroundColor Red; Read-Host 'Appuyez sur Entrée pour quitter'; exit 1 }
function Ask-YesNo($question, $default = $true) {
    $suffix = if ($default) { '[O/n]' } else { '[o/N]' }
    $r = Read-Host "$question $suffix"
    if ([string]::IsNullOrWhiteSpace($r)) { return $default }
    return $r -match '^[oOyY]'
}

# --- Recherche des instances ---------------------------------------------------

function Get-Instances {
    $list = @()

    $atl = Join-Path $env:APPDATA 'ATLauncher\instances'
    if (Test-Path $atl) {
        foreach ($dir in Get-ChildItem $atl -Directory) {
            $json = Join-Path $dir.FullName 'instance.json'
            if (-not (Test-Path $json)) { continue }
            $text = [IO.File]::ReadAllText($json, $Utf8NoBom)
            $name = if ($text -match '"name"\s*:\s*"([^"]*)"') { $Matches[1] } else { $dir.Name }
            $loader = if ($text -match '"loaderVersion"\s*:\s*\{[^}]*?"version"\s*:\s*"([^"]*)"') { $Matches[1] } else { '?' }
            $mc = if ($text -match '"id"\s*:\s*"(1\.\d+(\.\d+)?)"') { $Matches[1] } else { '?' }
            $list += [pscustomobject]@{ Launcher = 'ATLauncher'; Name = $name; Root = $dir.FullName; GameDir = $dir.FullName; Config = $json; Mc = $mc; Neo = $loader }
        }
    }

    foreach ($prismRoot in @((Join-Path $env:APPDATA 'PrismLauncher'), (Join-Path $env:APPDATA 'PolyMC'), (Join-Path $env:APPDATA 'MultiMC'))) {
        $inst = Join-Path $prismRoot 'instances'
        if (-not (Test-Path $inst)) { continue }
        foreach ($dir in Get-ChildItem $inst -Directory) {
            $cfg = Join-Path $dir.FullName 'instance.cfg'
            if (-not (Test-Path $cfg)) { continue }
            $name = $dir.Name
            foreach ($line in Get-Content $cfg) { if ($line -match '^name=(.*)$') { $name = $Matches[1] } }
            $game = Join-Path $dir.FullName 'minecraft'
            if (-not (Test-Path $game)) { $game = Join-Path $dir.FullName '.minecraft' }
            $mc = '?'; $neo = '?'
            $pack = Join-Path $dir.FullName 'mmc-pack.json'
            if (Test-Path $pack) {
                $p = Get-Content $pack -Raw | ConvertFrom-Json
                foreach ($c in $p.components) {
                    if ($c.uid -eq 'net.minecraft') { $mc = $c.version }
                    if ($c.uid -eq 'net.neoforged') { $neo = $c.version }
                }
            }
            $list += [pscustomobject]@{ Launcher = 'Prism'; Name = $name; Root = $dir.FullName; GameDir = $game; Config = $cfg; Mc = $mc; Neo = $neo }
        }
    }
    return $list
}

# --- Recherche de Java ---------------------------------------------------------

function Find-Java($instance) {
    $candidates = @()
    if ($instance.Launcher -eq 'ATLauncher') {
        $rt = Join-Path $env:APPDATA 'ATLauncher\runtimes'
        if (Test-Path $rt) { $candidates += Get-ChildItem $rt -Recurse -Filter java.exe -ErrorAction SilentlyContinue | ForEach-Object FullName }
    } else {
        $cfg = Get-Content $instance.Config
        foreach ($line in $cfg) { if ($line -match '^JavaPath=(.+)$') { $candidates += ($Matches[1] -replace 'javaw\.exe$', 'java.exe') } }
        $pj = Join-Path (Split-Path (Split-Path $instance.Root)) 'java'
        if (Test-Path $pj) { $candidates += Get-ChildItem $pj -Recurse -Filter java.exe -ErrorAction SilentlyContinue | ForEach-Object FullName }
    }
    if ($env:JAVA_HOME) { $candidates += Join-Path $env:JAVA_HOME 'bin\java.exe' }
    $cmd = Get-Command java.exe -ErrorAction SilentlyContinue
    if ($cmd) { $candidates += $cmd.Source }
    foreach ($c in $candidates) { if ($c -and (Test-Path $c)) { return $c } }
    return $null
}

function Test-LauncherRunning($instance) {
    if ($instance.Launcher -eq 'ATLauncher') {
        return [bool](Get-CimInstance Win32_Process -Filter "Name='java.exe' OR Name='javaw.exe' OR Name='ATLauncher.exe'" |
            Where-Object { $_.Name -eq 'ATLauncher.exe' -or $_.CommandLine -match 'ATLauncher' })
    }
    return [bool](Get-Process prismlauncher, polymc, multimc -ErrorAction SilentlyContinue)
}

# --- Programme principal -------------------------------------------------------

Write-Host '=============================================' -ForegroundColor Green
Write-Host '  Installation du pack All of Create Aeronautics' -ForegroundColor Green
Write-Host '=============================================' -ForegroundColor Green

Write-Step 'Recherche des instances Minecraft'
$instances = @(Get-Instances)
if ($instances.Count -eq 0) {
    Fail ("Aucune instance ATLauncher ou Prism Launcher trouvée.`n" +
          "Installez d'abord le modpack 'All of Create Aeronautics' dans ATLauncher (ou créez une instance NeoForge $NeoVersion / Minecraft $McVersion), puis relancez ce script.")
}

for ($i = 0; $i -lt $instances.Count; $i++) {
    $it = $instances[$i]
    $ok = ($it.Neo -eq $NeoVersion)
    $mark = if ($ok) { '  (compatible)' } else { '' }
    Write-Host ('  [{0}] {1} - {2}  [MC {3}, NeoForge {4}]{5}' -f ($i + 1), $it.Launcher, $it.Name, $it.Mc, $it.Neo, $mark)
}
$choice = Read-Host "`nNuméro de l'instance à configurer"
if (-not ($choice -match '^\d+$') -or [int]$choice -lt 1 -or [int]$choice -gt $instances.Count) { Fail 'Choix invalide.' }
$inst = $instances[[int]$choice - 1]

if ($inst.Neo -ne $NeoVersion) {
    Write-Warn "Cette instance n'est pas en NeoForge $NeoVersion (trouvé : $($inst.Neo)). Le pack risque de ne pas démarrer."
    if (-not (Ask-YesNo 'Continuer quand même ?' $false)) { exit 1 }
}

while (Test-LauncherRunning $inst) {
    Write-Warn "$($inst.Launcher) est ouvert. Fermez-le complètement (sinon il écrasera la configuration)."
    Read-Host 'Appuyez sur Entrée une fois le launcher fermé'
}

Write-Step 'Recherche de Java'
$java = Find-Java $inst
if (-not $java) {
    Fail "Java introuvable. Lancez l'instance une fois depuis le launcher (il télécharge Java), puis relancez ce script."
}
Write-Host "  Java : $java"

Write-Step "Téléchargement de packwiz-installer-bootstrap"
New-Item -ItemType Directory -Force $inst.GameDir | Out-Null
$jar = Join-Path $inst.GameDir 'packwiz-installer-bootstrap.jar'
Invoke-WebRequest $BootstrapUrl -OutFile $jar -UseBasicParsing

Write-Step 'Création du script de synchronisation'
$bat = Join-Path $inst.GameDir 'packwiz-sync.bat'
$batContent = "@echo off`r`ncd /d `"%~dp0`"`r`n`"$java`" -jar packwiz-installer-bootstrap.jar -s client $PackUrl`r`n"
# cmd lit les .bat dans la page de code OEM (chemins avec accents)
$oem = [Text.Encoding]::GetEncoding([Globalization.CultureInfo]::CurrentCulture.TextInfo.OEMCodePage)
[IO.File]::WriteAllText($bat, $batContent, $oem)
Write-Host "  $bat"

Write-Step "Configuration du lancement automatique dans $($inst.Launcher)"
Copy-Item $inst.Config "$($inst.Config).bak" -Force
if ($inst.Launcher -eq 'ATLauncher') {
    # ATLauncher découpe la commande sur les espaces sans gérer les guillemets :
    # on passe par cmd + le .bat (le dossier courant est celui de l'instance).
    $text = [IO.File]::ReadAllText($inst.Config, $Utf8NoBom)
    $text = $text -replace '\s*"(enableCommands|preLaunchCommand)"\s*:\s*("(?:[^"\\]|\\.)*"|true|false|null)\s*,', ''
    $text = [regex]::new('"launcher"\s*:\s*\{').Replace($text,
        '"launcher": {' + "`n    " + '"enableCommands": true,' + "`n    " + '"preLaunchCommand": "cmd /c .\\packwiz-sync.bat",', 1)
    [IO.File]::WriteAllText($inst.Config, $text, $Utf8NoBom)
} else {
    $lines = [Collections.Generic.List[string]](Get-Content $inst.Config)
    $wanted = [ordered]@{ OverrideCommands = 'true'; PreLaunchCommand = 'cmd /c .\packwiz-sync.bat' }
    foreach ($k in $wanted.Keys) {
        $idx = -1
        for ($j = 0; $j -lt $lines.Count; $j++) { if ($lines[$j] -match "^$k=") { $idx = $j } }
        if ($idx -ge 0) { $lines[$idx] = "$k=$($wanted[$k])" }
        else {
            $g = $lines.IndexOf('[General]')
            if ($g -ge 0) { $lines.Insert($g + 1, "$k=$($wanted[$k])") } else { $lines.Add("$k=$($wanted[$k])") }
        }
    }
    [IO.File]::WriteAllLines($inst.Config, $lines, $Utf8NoBom)
}
Write-Host "  OK (sauvegarde : $($inst.Config).bak)"

Write-Step 'Première synchronisation des mods (peut prendre quelques minutes)'
Push-Location $inst.GameDir
try { & $java -jar packwiz-installer-bootstrap.jar -s client $PackUrl } finally { Pop-Location }
if ($LASTEXITCODE -ne 0) { Fail 'La synchronisation a échoué (voir les messages ci-dessus).' }

# Les mods qui ne font pas partie du pack (anciennes versions, doublons...) peuvent
# empêcher le jeu de démarrer : on propose de les mettre de côté.
$state = Join-Path $inst.GameDir 'packwiz.json'
$modsDir = Join-Path $inst.GameDir 'mods'
if ((Test-Path $state) -and (Test-Path $modsDir)) {
    $managed = @{}
    $json = Get-Content $state -Raw | ConvertFrom-Json
    foreach ($p in $json.cachedFiles.PSObject.Properties) {
        if ($p.Value.cachedLocation) { $managed[($p.Value.cachedLocation -replace '/', '\').ToLower()] = $true }
    }
    $extra = @(Get-ChildItem $modsDir -File -Filter *.jar | Where-Object { -not $managed.ContainsKey(('mods\' + $_.Name).ToLower()) })
    if ($extra.Count -gt 0) {
        Write-Step "$($extra.Count) mod(s) présent(s) qui ne font pas partie du pack :"
        $extra | ForEach-Object { Write-Host "  - $($_.Name)" }
        if (Ask-YesNo 'Les déplacer dans un dossier de sauvegarde (recommandé, évite les doublons) ?' $true) {
            $backup = Join-Path $inst.GameDir ('mods_hors_pack_' + (Get-Date -Format 'yyyyMMdd_HHmmss'))
            New-Item -ItemType Directory $backup | Out-Null
            $extra | Move-Item -Destination $backup
            Write-Host "  Déplacés dans : $backup"
        }
    }
}

Write-Host "`nTerminé ! Les mods seront mis à jour automatiquement à chaque lancement de l'instance." -ForegroundColor Green
if ($inst.Launcher -eq 'ATLauncher') {
    Write-Warn "Conseil : dans ATLauncher, désactivez les mises à jour du modpack pour cette instance, sinon elles peuvent entrer en conflit avec la synchronisation."
}
Read-Host "`nAppuyez sur Entrée pour quitter"
