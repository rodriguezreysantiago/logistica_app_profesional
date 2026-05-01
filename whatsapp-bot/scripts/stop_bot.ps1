# Detiene el bot WhatsApp (servicio NSSM 'SmartLogisticaBot') de
# forma ordenada, esperando que termine cualquier mensaje en curso.
#
# Pensado para el flujo de 2 PCs (casa + oficina): SIEMPRE corre esto
# antes de irte de una PC para arrancar el bot en la otra. Sin esto,
# vas a tener 2 bots corriendo y eso lleva a mensajes duplicados +
# riesgo de que WhatsApp banee tu numero por trafico raro.
#
# Uso:
#   cd <ruta-al-repo>\whatsapp-bot
#   .\scripts\stop_bot.ps1

$ErrorActionPreference = 'Stop'
$serviceName = 'SmartLogisticaBot'

$svc = Get-Service -Name $serviceName -ErrorAction SilentlyContinue
if (-not $svc) {
    Write-Host "El servicio '$serviceName' no esta instalado en esta PC." -ForegroundColor Yellow
    Write-Host "Si estas en una PC nueva, no hay nada que detener." -ForegroundColor Yellow
    exit 0
}

if ($svc.Status -eq 'Stopped') {
    Write-Host "El bot ya estaba detenido." -ForegroundColor Yellow
    exit 0
}

Write-Host "Deteniendo bot '$serviceName'..." -ForegroundColor Cyan
# NSSM tiene un grace period configurado en index.js (DELAY_MAX_MS + 10s)
# para que un envio en curso termine antes de matar el proceso.
nssm stop $serviceName | Out-Null

# Esperamos hasta 90s a que el servicio quede en Stopped. Si tarda
# mas, casi seguro hay un envio largo en curso o el grace period
# esta agotando.
$timeout = 90
$elapsed = 0
while ((Get-Service -Name $serviceName).Status -ne 'Stopped' -and $elapsed -lt $timeout) {
    Start-Sleep -Seconds 1
    $elapsed++
    Write-Host "  esperando... ($elapsed/${timeout}s)" -ForegroundColor DarkGray
}

$svc = Get-Service -Name $serviceName
if ($svc.Status -eq 'Stopped') {
    Write-Host ""
    Write-Host "OK Bot detenido." -ForegroundColor Green
    Write-Host ""
    Write-Host "Si modificaste codigo y queres pushearlo:" -ForegroundColor Cyan
    Write-Host "  git add -A; git commit -m '...'; git push" -ForegroundColor White
    Write-Host ""
    Write-Host "Ahora podes arrancar el bot en la otra PC con seguridad." -ForegroundColor Cyan
} else {
    Write-Host ""
    Write-Host "ADVERTENCIA: el servicio no llego a Stopped despues de ${timeout}s." -ForegroundColor Yellow
    Write-Host "Estado actual: $($svc.Status)" -ForegroundColor Yellow
    Write-Host "Forzar parada con (puede dejar un envio incompleto):" -ForegroundColor Yellow
    Write-Host "  Stop-Service -Name $serviceName -Force" -ForegroundColor Yellow
    exit 1
}
