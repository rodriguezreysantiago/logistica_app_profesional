# Arranca el bot WhatsApp (servicio NSSM 'SmartLogisticaBot') despues
# de sincronizar el codigo con git y refrescar dependencias npm.
#
# Pensado para el flujo de 2 PCs (casa + oficina): cada vez que llegas
# a una de las dos, corres este script y queda todo listo. La otra
# PC tiene que estar APAGADA o haber corrido stop_bot.ps1 antes
# (sino se procesan los mismos mensajes 2 veces y WhatsApp puede
# bannear el numero).
#
# Uso:
#   cd <ruta-al-repo>\whatsapp-bot
#   .\scripts\start_bot.ps1
#
# Que hace:
#   1. git pull en la raiz del repo (trae los ultimos cambios).
#   2. npm install --silent en whatsapp-bot/ (solo instala si cambio package.json).
#   3. nssm start SmartLogisticaBot.
#   4. Te dice donde ver los logs en vivo.
#
# Que NO hace (de proposito):
#   - flutter pub get (la app la arrancas vos cuando quieras).
#   - Reiniciar el bot si ya estaba corriendo (te avisa y sale).

$ErrorActionPreference = 'Stop'
$serviceName = 'SmartLogisticaBot'

# Resolvemos paths desde el script para que funcione igual en
# cualquier PC, sin importar donde clonaste el repo.
$botRoot  = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$repoRoot = (Resolve-Path (Join-Path $botRoot '..')).Path
$logsDir  = Join-Path $botRoot 'logs'

Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "INICIANDO BOT - S.M.A.R.T. Logistica" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host ""

# --- 1. Verificar que el servicio este instalado -------------------
$svc = Get-Service -Name $serviceName -ErrorAction SilentlyContinue
if (-not $svc) {
    Write-Host "ERROR: el servicio '$serviceName' no esta instalado." -ForegroundColor Red
    Write-Host "Ejecuta primero (como administrador):" -ForegroundColor Yellow
    Write-Host "  .\scripts\instalar_servicio.ps1" -ForegroundColor Yellow
    exit 1
}

# --- 2. Verificar si ya esta corriendo -----------------------------
if ($svc.Status -eq 'Running') {
    Write-Host "El bot YA esta corriendo en esta PC." -ForegroundColor Yellow
    Write-Host "Si queres reiniciar (despues de un git pull con cambios), corre:" -ForegroundColor Yellow
    Write-Host "  nssm restart $serviceName" -ForegroundColor Yellow
    exit 0
}

# --- 3. git pull en el repo ----------------------------------------
Write-Host "[1/3] Sincronizando con git pull..." -ForegroundColor Cyan
Push-Location $repoRoot
try {
    # Verificamos primero que no haya cambios sin commitear, para
    # que el pull no falle por conflicto de merge inesperado.
    $dirty = git status --porcelain
    if ($dirty) {
        Write-Host "ADVERTENCIA: hay cambios sin commitear en el repo:" -ForegroundColor Yellow
        Write-Host $dirty -ForegroundColor Yellow
        Write-Host "Resolvelos (commit/stash) antes de seguir, o arranca el bot a mano con 'nssm start $serviceName'." -ForegroundColor Yellow
        exit 1
    }

    git pull
    if ($LASTEXITCODE -ne 0) {
        Write-Host "git pull fallo. Revisa el error arriba." -ForegroundColor Red
        exit 1
    }
}
finally {
    Pop-Location
}

# --- 4. npm install en el bot --------------------------------------
# Lo corremos siempre porque es idempotente y rapido si no cambio
# package.json. Mejor que olvidarse cuando si cambio.
Write-Host "[2/3] Refrescando dependencias del bot (npm install)..." -ForegroundColor Cyan
Push-Location $botRoot
try {
    npm install --silent
    if ($LASTEXITCODE -ne 0) {
        Write-Host "npm install fallo. Revisa el error arriba." -ForegroundColor Red
        exit 1
    }
}
finally {
    Pop-Location
}

# --- 5. Arrancar el servicio ---------------------------------------
Write-Host "[3/3] Arrancando servicio '$serviceName'..." -ForegroundColor Cyan
nssm start $serviceName | Out-Null
Start-Sleep -Seconds 3

$svc = Get-Service -Name $serviceName
if ($svc.Status -ne 'Running') {
    Write-Host "El servicio no llego a estado Running. Estado actual: $($svc.Status)" -ForegroundColor Red
    Write-Host "Revisa los logs:" -ForegroundColor Yellow
    Write-Host "  Get-Content $logsDir\bot.err.log -Tail 50" -ForegroundColor Yellow
    exit 1
}

Write-Host ""
Write-Host "==========================================" -ForegroundColor Green
Write-Host "OK BOT CORRIENDO" -ForegroundColor Green
Write-Host "==========================================" -ForegroundColor Green
Write-Host ""
Write-Host "Para ver los logs en vivo (en otra ventana):" -ForegroundColor Cyan
Write-Host "  Get-Content $logsDir\bot.out.log -Tail 50 -Wait" -ForegroundColor White
Write-Host ""
Write-Host "Para detener cuando termines de trabajar:" -ForegroundColor Cyan
Write-Host "  .\scripts\stop_bot.ps1" -ForegroundColor White
Write-Host ""
Write-Host "RECORDATORIO: si tenes el bot tambien en otra PC, asegurate" -ForegroundColor Yellow
Write-Host "de que esa otra este APAGADA o el bot detenido alla." -ForegroundColor Yellow
