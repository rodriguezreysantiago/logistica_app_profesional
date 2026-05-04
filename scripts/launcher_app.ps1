# Launcher de Coopertrans Móvil — chequea GitHub Releases, baja la
# versión nueva si hay, y lanza la app.
#
# El icono "Coopertrans Móvil" del escritorio apunta a este script.
# El operador hace doble click → si hay update se actualiza solo →
# arranca la app. Sin ir PC por PC copiando archivos.
#
# Pre-requisito en cada PC:
#   - gh CLI instalado y autenticado (`winget install GitHub.cli` +
#     `gh auth login`).
#
# Ubicaciones:
#   - Instalación de la app: %LOCALAPPDATA%\CoopertransMovil\
#   - Ejecutable:             %LOCALAPPDATA%\CoopertransMovil\coopertrans_movil.exe
#   - Versión instalada:      %LOCALAPPDATA%\CoopertransMovil\VERSION.txt
#   - Log de updates:         %LOCALAPPDATA%\CoopertransMovil\update.log

$ErrorActionPreference = 'Stop'

# === CONFIG ========================================================
$repo      = 'rodriguezreysantiago/logistica_app_profesional'
$exeName   = 'coopertrans_movil.exe'
$installDir = Join-Path $env:LOCALAPPDATA 'CoopertransMovil'
$logFile   = Join-Path $installDir 'update.log'
$exePath   = Join-Path $installDir $exeName
$verFile   = Join-Path $installDir 'VERSION.txt'

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
        Log "ERROR: no existe $exePath. Update inicial debe completarse antes de lanzar." 'Red'
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
    Log "Cerrá la app antes de chequear updates." 'Yellow'
    Start-Sleep -Seconds 2
    exit 0
}

# === 2. Verificar gh CLI ===========================================
$gh = Get-Command gh -ErrorAction SilentlyContinue
if (-not $gh) {
    Log "ADVERTENCIA: gh CLI no instalado. Lanzando versión actual sin chequear updates." 'Yellow'
    Log "Para activar auto-update: winget install GitHub.cli && gh auth login" 'Yellow'
    Start-Sleep -Seconds 2
    Lanzar-App
    exit 0
}

# === 3. Crear installDir si no existe (primer arranque) ===========
if (-not (Test-Path $installDir)) {
    New-Item -ItemType Directory -Force -Path $installDir | Out-Null
    Log "Primer arranque — voy a bajar la última release." 'Cyan'
}

# === 4. Chequear última release ===================================
Log "Chequeando última release en GitHub..." 'Cyan'
$latestJson = & gh release view --repo $repo --json tagName,assets 2>&1
if ($LASTEXITCODE -ne 0) {
    Log "No pude consultar GitHub (capaz sin red). Lanzo versión local." 'Yellow'
    Log $latestJson 'DarkGray'
    Lanzar-App
    exit 0
}

try {
    $latest = $latestJson | ConvertFrom-Json
} catch {
    Log "Respuesta de gh no parseable. Lanzo versión local." 'Yellow'
    Lanzar-App
    exit 0
}

$tagRemoto = $latest.tagName       # ej "v1.0.0+1"
$versionRemota = $tagRemoto -replace '^v', ''  # "1.0.0+1"

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

# === 5. Hay versión nueva — bajar e instalar ======================
Log "" 'White'
Log "Hay versión nueva disponible: $versionRemota" 'Cyan'
Log "Descargando..." 'Cyan'

$asset = $latest.assets | Where-Object { $_.name -like '*.zip' } | Select-Object -First 1
if (-not $asset) {
    Log "ERROR: el release $tagRemoto no tiene asset .zip. Lanzo versión local." 'Red'
    Lanzar-App
    exit 1
}

$tempDir = Join-Path $env:TEMP "CoopertransMovil_update_$(Get-Random)"
New-Item -ItemType Directory -Force -Path $tempDir | Out-Null

try {
    & gh release download $tagRemoto --repo $repo --pattern $asset.name --dir $tempDir 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "gh release download falló" }

    $zipPath = Join-Path $tempDir $asset.name
    $stagingDir = Join-Path $tempDir 'staging'
    Log "Extrayendo $($asset.name)..." 'Cyan'
    Expand-Archive -Path $zipPath -DestinationPath $stagingDir -Force

    # Verificar que el extract tiene el .exe esperado
    if (-not (Test-Path (Join-Path $stagingDir $exeName))) {
        throw "El zip no contiene $exeName en la raíz"
    }

    # Backup del install actual (si existía)
    $backupDir = $null
    if (Test-Path (Join-Path $installDir $exeName)) {
        $backupDir = "$installDir.bak"
        if (Test-Path $backupDir) { Remove-Item $backupDir -Recurse -Force }
        Log "Backup de versión actual..." 'Cyan'
        # Move-Item del directorio entero (rápido, atómico en NTFS)
        Move-Item -Path $installDir -Destination $backupDir
        New-Item -ItemType Directory -Force -Path $installDir | Out-Null
    }

    # Copiar staging a installDir
    Log "Instalando $versionRemota..." 'Cyan'
    Copy-Item -Path "$stagingDir\*" -Destination $installDir -Recurse -Force

    # Asegurar VERSION.txt (debería venir en el zip pero por si acaso)
    if (-not (Test-Path $verFile)) {
        Set-Content -Path $verFile -Value $versionRemota -Encoding UTF8
    }

    Log "OK Actualizado a $versionRemota" 'Green'

    # Cleanup backup viejo (mantengo solo el último por las dudas)
    # Lo dejo: ocupa espacio pero es seguro tener rollback inmediato.
} catch {
    Log "ERROR durante el update: $($_.Exception.Message)" 'Red'
    # Restaurar desde backup si existía
    if ($backupDir -and (Test-Path $backupDir)) {
        Log "Restaurando versión anterior..." 'Yellow'
        if (Test-Path $installDir) { Remove-Item $installDir -Recurse -Force }
        Move-Item -Path $backupDir -Destination $installDir
    }
} finally {
    if (Test-Path $tempDir) { Remove-Item $tempDir -Recurse -Force -ErrorAction SilentlyContinue }
}

# === 6. Lanzar app =================================================
Lanzar-App
