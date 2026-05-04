# Detiene el bot WhatsApp (servicio NSSM 'CoopertransMovilBot') de
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
$serviceName = 'CoopertransMovilBot'

function Test-IsAdmin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    $pr = New-Object Security.Principal.WindowsPrincipal($id)
    return $pr.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Invoke-ElevatedServiceAction {
    param(
        [Parameter(Mandatory)] [string]$Action,
        [Parameter(Mandatory)] [string]$Name
    )
    if (Test-IsAdmin) {
        if ($Action -eq 'Start') { Start-Service -Name $Name -ErrorAction Stop }
        elseif ($Action -eq 'Stop') { Stop-Service -Name $Name -ErrorAction Stop }
        return $true
    }
    Write-Host "Necesito permisos de admin para tocar el servicio." -ForegroundColor Yellow
    Write-Host "Vas a ver un prompt de UAC -- aceptalo." -ForegroundColor Yellow
    $verb = if ($Action -eq 'Start') { 'Start-Service' } else { 'Stop-Service' }
    $arg = "$verb -Name '$Name' -ErrorAction Stop"
    try {
        $proc = Start-Process powershell -ArgumentList @('-NoProfile','-Command',$arg) `
            -Verb RunAs -Wait -PassThru -ErrorAction Stop
        return ($proc.ExitCode -eq 0)
    } catch {
        Write-Host "El usuario rechazo el prompt de UAC, o el servicio fallo." -ForegroundColor Red
        return $false
    }
}

Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "DETENIENDO BOT - Coopertrans Movil" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host ""

$svc = Get-Service -Name $serviceName -ErrorAction SilentlyContinue
if (-not $svc) {
    Write-Host "==========================================" -ForegroundColor Yellow
    Write-Host "SERVICIO NO INSTALADO" -ForegroundColor Yellow
    Write-Host "==========================================" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "El servicio '$serviceName' no esta en esta PC." -ForegroundColor Yellow
    Write-Host "Si estas en una PC nueva, no hay nada que detener." -ForegroundColor Yellow
    Write-Host ""
    Write-Host "(Esta ventana se queda abierta. Cerrala cuando quieras.)" -ForegroundColor DarkGray
    exit 0
}

if ($svc.Status -eq 'Stopped') {
    Write-Host "==========================================" -ForegroundColor Yellow
    Write-Host "EL BOT YA ESTABA DETENIDO" -ForegroundColor Yellow
    Write-Host "==========================================" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "Estado: Stopped (no estaba corriendo en esta PC)" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "(Esta ventana se queda abierta. Cerrala cuando quieras.)" -ForegroundColor DarkGray
    exit 0
}

Write-Host "Estado actual: $($svc.Status)" -ForegroundColor Cyan
Write-Host "Deteniendo... (espera grace shutdown hasta 90s)" -ForegroundColor Cyan
Write-Host ""
$ok = Invoke-ElevatedServiceAction -Action 'Stop' -Name $serviceName
if (-not $ok) {
    Write-Host "No pude detener el servicio." -ForegroundColor Red
    exit 1
}

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
$ts = Get-Date -Format 'HH:mm:ss'
if ($svc.Status -eq 'Stopped') {
    Write-Host ""
    Write-Host "==========================================" -ForegroundColor Green
    Write-Host "OK BOT DETENIDO" -ForegroundColor Green
    Write-Host "==========================================" -ForegroundColor Green
    Write-Host ""
    Write-Host "Servicio:  $serviceName" -ForegroundColor White
    Write-Host "Estado:    Stopped" -ForegroundColor Green
    Write-Host "Cerrado:   $ts (despues de ${elapsed}s de espera)" -ForegroundColor White
    Write-Host ""
    Write-Host "Ya podes arrancar el bot en la otra PC con seguridad." -ForegroundColor Cyan
    Write-Host ""
    Write-Host "(Esta ventana se queda abierta. Cerrala cuando quieras.)" -ForegroundColor DarkGray
} else {
    Write-Host ""
    Write-Host "==========================================" -ForegroundColor Red
    Write-Host "FALLO AL DETENER" -ForegroundColor Red
    Write-Host "==========================================" -ForegroundColor Red
    Write-Host ""
    Write-Host "El servicio no llego a Stopped despues de ${timeout}s." -ForegroundColor Yellow
    Write-Host "Estado actual: $($svc.Status)" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "Forzar parada con (puede dejar un envio incompleto):" -ForegroundColor Yellow
    Write-Host "  Stop-Service -Name $serviceName -Force" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "(Esta ventana se queda abierta. Cerrala cuando quieras.)" -ForegroundColor DarkGray
    exit 1
}
