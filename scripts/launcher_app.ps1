# Launcher de Coopertrans Móvil — chequea GitHub Releases (vía API
# pública, sin auth ni gh CLI), baja la versión nueva si hay, y lanza
# la app.
#
# El icono "Coopertrans Móvil" del escritorio apunta a este script.
# El operador hace doble click → si hay update se actualiza solo →
# arranca la app. Sin ir PC por PC copiando archivos.
#
# Como el repo es PÚBLICO, no hace falta instalar gh CLI ni autenticar
# nada. Usa Invoke-RestMethod / Invoke-WebRequest directos contra la
# API pública de GitHub. Cero setup en cada PC, solo bajar este archivo.
#
# Ubicaciones (por usuario, NO requiere admin):
#   - Instalación de la app: %LOCALAPPDATA%\CoopertransMovil\
#   - Ejecutable:             %LOCALAPPDATA%\CoopertransMovil\coopertrans_movil.exe
#   - Versión instalada:      %LOCALAPPDATA%\CoopertransMovil\VERSION.txt
#   - Log de updates:         %LOCALAPPDATA%\CoopertransMovil\update.log

$ErrorActionPreference = 'Stop'

# === CONFIG ========================================================
$repo       = 'rodriguezreysantiago/logistica_app_profesional'
$exeName    = 'coopertrans_movil.exe'
$installDir = Join-Path $env:LOCALAPPDATA 'CoopertransMovil'
$logFile    = Join-Path $installDir 'update.log'
$exePath    = Join-Path $installDir $exeName
$verFile    = Join-Path $installDir 'VERSION.txt'

# GitHub requiere User-Agent en cualquier request a la API.
$apiHeaders = @{
    'User-Agent' = 'CoopertransMovil-Launcher'
    'Accept'     = 'application/vnd.github+json'
}

# === HELPERS =======================================================
function Log {
    param([string]$Msg, [string]$Color = 'White')
    Write-Host $Msg -ForegroundColor $Color
    if (Test-Path $installDir) {
        $ts = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
        Add-Content -Path $logFile -Value "[$ts] $Msg" -Encoding UTF8
    }
}

function Lanzar-App {
    if (-not (Test-Path $exePath)) {
        Log "ERROR: no existe $exePath. El update inicial debe completarse primero." 'Red'
        Read-Host "Enter para cerrar"
        exit 1
    }
    Log "Lanzando $exeName..." 'Cyan'
    Start-Process -FilePath $exePath -WorkingDirectory $installDir
}

# === 1. ¿La app ya está corriendo? =================================
$running = Get-Process -Name ($exeName -replace '\.exe$') -ErrorAction SilentlyContinue
if ($running) {
    Log "La app ya está corriendo (PID $($running[0].Id)). No actualizo." 'Yellow'
    Log "Cerrá la app antes para chequear updates." 'Yellow'
    Start-Sleep -Seconds 2
    exit 0
}

# === 2. Crear installDir si no existe (primer arranque) ===========
if (-not (Test-Path $installDir)) {
    New-Item -ItemType Directory -Force -Path $installDir | Out-Null
    Log "Primer arranque — voy a bajar la última release." 'Cyan'
}

# === 3. Chequear última release vía GitHub API pública ============
Log "Chequeando última release en GitHub..." 'Cyan'

$latest = $null
try {
    $latest = Invoke-RestMethod `
        -Uri "https://api.github.com/repos/$repo/releases/latest" `
        -Headers $apiHeaders `
        -TimeoutSec 15
} catch {
    Log "No pude consultar GitHub (capaz sin red): $($_.Exception.Message)" 'Yellow'
    Log "Lanzo versión local sin chequear updates." 'Yellow'
    Lanzar-App
    exit 0
}

$tagRemoto = $latest.tag_name              # ej "v1.0.0+1"
$versionRemota = $tagRemoto -replace '^v', ''

$versionLocal = if (Test-Path $verFile) {
    (Get-Content $verFile -ErrorAction SilentlyContinue | Select-Object -First 1).Trim()
} else { '' }

Log "Versión local:  $(if ($versionLocal) { $versionLocal } else { '(ninguna instalada)' })" 'White'
Log "Versión remota: $versionRemota" 'White'

if ($versionLocal -eq $versionRemota) {
    Log "Estás al día. Lanzando app." 'Green'
    Lanzar-App
    exit 0
}

# === 4. Hay versión nueva — bajar e instalar ======================
Log "" 'White'
Log "Hay versión nueva disponible: $versionRemota" 'Cyan'

$asset = $latest.assets | Where-Object { $_.name -like '*.zip' } | Select-Object -First 1
if (-not $asset) {
    Log "ERROR: el release $tagRemoto no tiene asset .zip. Lanzo versión local." 'Red'
    Lanzar-App
    exit 1
}

Log "Descargando $($asset.name) ($([math]::Round($asset.size / 1MB, 1)) MB)..." 'Cyan'

$tempDir   = Join-Path $env:TEMP "CoopertransMovil_update_$(Get-Random)"
$backupDir = $null
New-Item -ItemType Directory -Force -Path $tempDir | Out-Null

try {
    $zipPath = Join-Path $tempDir $asset.name
    Invoke-WebRequest `
        -Uri $asset.browser_download_url `
        -OutFile $zipPath `
        -Headers $apiHeaders `
        -TimeoutSec 300

    $stagingDir = Join-Path $tempDir 'staging'
    Log "Extrayendo..." 'Cyan'
    Expand-Archive -Path $zipPath -DestinationPath $stagingDir -Force

    if (-not (Test-Path (Join-Path $stagingDir $exeName))) {
        throw "El zip no contiene $exeName en la raíz"
    }

    # Backup atómico de la versión actual (si existía algo instalado).
    if (Test-Path (Join-Path $installDir $exeName)) {
        $backupDir = "$installDir.bak"
        if (Test-Path $backupDir) { Remove-Item $backupDir -Recurse -Force }
        Log "Backup de versión actual..." 'Cyan'
        Move-Item -Path $installDir -Destination $backupDir
        New-Item -ItemType Directory -Force -Path $installDir | Out-Null
    }

    Log "Instalando $versionRemota..." 'Cyan'
    Copy-Item -Path "$stagingDir\*" -Destination $installDir -Recurse -Force

    if (-not (Test-Path $verFile)) {
        Set-Content -Path $verFile -Value $versionRemota -Encoding UTF8
    }

    Log "OK Actualizado a $versionRemota" 'Green'
} catch {
    Log "ERROR durante el update: $($_.Exception.Message)" 'Red'
    if ($backupDir -and (Test-Path $backupDir)) {
        Log "Restaurando versión anterior..." 'Yellow'
        if (Test-Path $installDir) { Remove-Item $installDir -Recurse -Force }
        Move-Item -Path $backupDir -Destination $installDir
    }
} finally {
    if (Test-Path $tempDir) { Remove-Item $tempDir -Recurse -Force -ErrorAction SilentlyContinue }
}

# === 5. Lanzar app =================================================
Lanzar-App
