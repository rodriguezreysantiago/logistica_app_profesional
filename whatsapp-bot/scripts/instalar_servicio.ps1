# Instala el bot como servicio Windows con NSSM, configurado para:
#   - Arrancar al boot de Windows (incluso sin login).
#   - Auto-restart con backoff si el proceso muere.
#   - Logs persistentes en carpeta `logs/` del bot.
#
# Requiere ejecutar como Administrador.
#
# Uso:
#   1. Click derecho en PowerShell → "Ejecutar como administrador".
#   2. Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
#   3. cd "C:\Users\Colo Logistica\logistica_app_profesional\whatsapp-bot"
#   4. .\scripts\instalar_servicio.ps1
#
# Para desinstalar:
#   nssm stop SmartLogisticaBot
#   nssm remove SmartLogisticaBot confirm

$ErrorActionPreference = 'Stop'

# ─── 1. Variables ──────────────────────────────────────────────────
$serviceName = 'SmartLogisticaBot'
$botRoot     = 'C:\Users\Colo Logistica\logistica_app_profesional\whatsapp-bot'
$logsDir     = Join-Path $botRoot 'logs'
$nssmDir     = 'C:\nssm'
$nssmExe     = Join-Path $nssmDir 'nssm.exe'

# ─── 2. Verificar permisos de admin ────────────────────────────────
$isAdmin = ([Security.Principal.WindowsPrincipal] `
    [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Host "❌ Este script necesita ejecutarse como Administrador." -ForegroundColor Red
    Write-Host "Cerrá esta ventana, abrí PowerShell con click derecho → 'Ejecutar como administrador' y reintentá." -ForegroundColor Yellow
    exit 1
}

# ─── 3. Instalar NSSM si no está ───────────────────────────────────
if (-not (Test-Path $nssmExe)) {
    Write-Host "📥 NSSM no está instalado. Bajando..." -ForegroundColor Cyan
    $nssmZip = "$env:TEMP\nssm.zip"
    $nssmUrl = 'https://nssm.cc/release/nssm-2.24.zip'

    Invoke-WebRequest -Uri $nssmUrl -OutFile $nssmZip -UseBasicParsing
    Expand-Archive -Path $nssmZip -DestinationPath "$env:TEMP\nssm-extract" -Force

    # NSSM viene con 32-bit y 64-bit. Usamos el de 64-bit (win64).
    $nssm64 = Get-ChildItem "$env:TEMP\nssm-extract" -Recurse `
        -Filter 'nssm.exe' | Where-Object { $_.DirectoryName -match 'win64' } |
        Select-Object -First 1

    if (-not $nssm64) {
        throw "No encontré nssm.exe (64-bit) en el zip descargado."
    }

    New-Item -ItemType Directory -Force -Path $nssmDir | Out-Null
    Copy-Item $nssm64.FullName $nssmExe -Force

    Remove-Item $nssmZip -Force -ErrorAction SilentlyContinue
    Remove-Item "$env:TEMP\nssm-extract" -Recurse -Force -ErrorAction SilentlyContinue

    Write-Host "✓ NSSM instalado en $nssmExe" -ForegroundColor Green
} else {
    Write-Host "✓ NSSM ya estaba instalado." -ForegroundColor Green
}

# ─── 4. Verificar Node.js ──────────────────────────────────────────
$nodeExe = (Get-Command node -ErrorAction SilentlyContinue).Source
if (-not $nodeExe) {
    throw "Node.js no está en el PATH. Instalá desde https://nodejs.org/ y reabrí PowerShell."
}
Write-Host "✓ Node.js encontrado: $nodeExe" -ForegroundColor Green

# ─── 5. Crear carpeta de logs ──────────────────────────────────────
New-Item -ItemType Directory -Force -Path $logsDir | Out-Null

# ─── 6. Detener y borrar el servicio si ya existía ─────────────────
$existing = Get-Service -Name $serviceName -ErrorAction SilentlyContinue
if ($existing) {
    Write-Host "⚠️  Servicio '$serviceName' ya existe. Lo voy a recrear..." -ForegroundColor Yellow
    & $nssmExe stop $serviceName confirm 2>&1 | Out-Null
    & $nssmExe remove $serviceName confirm 2>&1 | Out-Null
    Start-Sleep -Seconds 2
}

# ─── 7. Instalar el servicio ───────────────────────────────────────
Write-Host "📦 Creando servicio Windows '$serviceName'..." -ForegroundColor Cyan

& $nssmExe install $serviceName $nodeExe 'src\index.js' | Out-Null
& $nssmExe set $serviceName AppDirectory $botRoot | Out-Null

# Logs separados para stdout y stderr.
& $nssmExe set $serviceName AppStdout (Join-Path $logsDir 'bot.out.log') | Out-Null
& $nssmExe set $serviceName AppStderr (Join-Path $logsDir 'bot.err.log') | Out-Null

# Rotación de logs: cuando un log llega a 10 MB, lo rotamos.
& $nssmExe set $serviceName AppRotateFiles 1 | Out-Null
& $nssmExe set $serviceName AppRotateOnline 1 | Out-Null
& $nssmExe set $serviceName AppRotateBytes 10485760 | Out-Null  # 10 MB

# Auto-restart: si el proceso termina con cualquier código, reintentar.
& $nssmExe set $serviceName AppExit Default Restart | Out-Null
# Espera 10 segundos antes de reintentar (evita ráfaga de fallos rápidos).
& $nssmExe set $serviceName AppRestartDelay 10000 | Out-Null
# Si el proceso falla 3 veces en 60 segundos, esperar 5 minutos antes de reintentar de nuevo.
& $nssmExe set $serviceName AppThrottle 60000 | Out-Null

# Modo de inicio: Automatic = arranca al boot.
& $nssmExe set $serviceName Start SERVICE_AUTO_START | Out-Null

# Descripción visible en services.msc.
& $nssmExe set $serviceName DisplayName 'S.M.A.R.T. Logística — Bot WhatsApp' | Out-Null
& $nssmExe set $serviceName Description 'Bot Node.js que procesa la cola COLA_WHATSAPP de Firestore y envía avisos automáticos por WhatsApp Web. Reinicia automáticamente si crashea o vuelve internet.' | Out-Null

Write-Host "✓ Servicio '$serviceName' creado." -ForegroundColor Green

# ─── 8. Arrancar el servicio ───────────────────────────────────────
Write-Host "🚀 Arrancando servicio..." -ForegroundColor Cyan
& $nssmExe start $serviceName | Out-Null
Start-Sleep -Seconds 3

$svc = Get-Service -Name $serviceName
if ($svc.Status -eq 'Running') {
    Write-Host "✓ Servicio corriendo." -ForegroundColor Green
} else {
    Write-Host "⚠️  Servicio en estado: $($svc.Status). Revisá logs en $logsDir" -ForegroundColor Yellow
}

# ─── 9. Resumen ────────────────────────────────────────────────────
Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "INSTALACIÓN COMPLETA" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Servicio:     $serviceName"
Write-Host "Estado:       $($svc.Status)"
Write-Host "Ejecutable:   $nodeExe src\index.js"
Write-Host "Working dir:  $botRoot"
Write-Host "Logs:         $logsDir"
Write-Host ""
Write-Host "Comandos útiles:" -ForegroundColor Yellow
Write-Host "  Ver estado:           Get-Service $serviceName"
Write-Host "  Reiniciar:            Restart-Service $serviceName"
Write-Host "  Detener:              Stop-Service $serviceName"
Write-Host "  Arrancar:             Start-Service $serviceName"
Write-Host "  Ver log en vivo:      Get-Content $logsDir\bot.out.log -Tail 50 -Wait"
Write-Host "  Ver errores:          Get-Content $logsDir\bot.err.log -Tail 50 -Wait"
Write-Host "  Desinstalar:          $nssmExe remove $serviceName confirm"
Write-Host ""
Write-Host "El servicio arranca AUTOMÁTICAMENTE al boot de Windows." -ForegroundColor Green
Write-Host "No necesita que haya un usuario logueado." -ForegroundColor Green
